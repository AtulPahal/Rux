use crate::settings::SettingsStore;
use parking_lot::Mutex;
use std::collections::VecDeque;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub use rux_core::config::{
    DEFAULT_IPC_MAX_MESSAGE_SIZE, DEFAULT_IPC_PORT_START, IPC_MSG_EXECUTE, IPC_MSG_PING,
    IPC_MSG_SETTING, IPC_PONG_BYTE, IPC_PORT_ATTEMPTS,
};
pub const DEFAULT_PORT_START: u16 = DEFAULT_IPC_PORT_START;
pub const MAX_PORT_ATTEMPTS: u16 = IPC_PORT_ATTEMPTS;
pub const DEFAULT_MAX_MESSAGE_SIZE: usize = DEFAULT_IPC_MAX_MESSAGE_SIZE;

pub const IPC_EXECUTE: u8 = IPC_MSG_EXECUTE;
pub const IPC_SETTING: u8 = IPC_MSG_SETTING;
pub const IPC_PING: u8 = IPC_MSG_PING;
pub const PONG_BYTE: u8 = IPC_PONG_BYTE;

/// Dynamically determine the IPC bind host.
pub fn get_ipc_host() -> String {
    use rux_core::config as cfg;
    let store = SettingsStore::global();
    if let Some(host) = store.get_string(cfg::SETTINGS_IPC_HOST) {
        if !host.trim().is_empty() {
            return host;
        }
    }
    if let Ok(host) = std::env::var(cfg::ENV_IPC_HOST) {
        if !host.trim().is_empty() {
            return host;
        }
    }
    cfg::DEFAULT_IPC_HOST.to_string()
}

/// Dynamically determine the default starting IPC port.
pub fn get_default_port_start() -> u16 {
    use rux_core::config as cfg;
    let store = SettingsStore::global();
    if let Some(port) = store.get_number(cfg::SETTINGS_IPC_PORT) {
        if (cfg::IPC_PORT_MIN..=cfg::IPC_PORT_MAX).contains(&port) {
            return port as u16;
        }
    }
    if let Ok(port_str) = std::env::var(cfg::ENV_IPC_PORT) {
        if let Ok(port) = port_str.parse::<u16>() {
            return port;
        }
    }
    DEFAULT_PORT_START
}

/// Dynamically determine the maximum allowed IPC message size in bytes.
pub fn get_max_message_size() -> usize {
    use rux_core::config as cfg;
    let store = SettingsStore::global();
    if let Some(size) = store.get_number(cfg::SETTINGS_IPC_MAX_MESSAGE_SIZE) {
        if size > 0 {
            return size as usize;
        }
    }
    if let Ok(size_str) = std::env::var(cfg::ENV_IPC_MAX_MSG_SIZE) {
        if let Ok(size) = size_str.parse::<usize>() {
            return size;
        }
    }
    DEFAULT_MAX_MESSAGE_SIZE
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IpcHeader {
    pub msg_type: u8,
    pub size: usize,
}

impl IpcHeader {
    pub const SIZE: usize = std::mem::size_of::<Self>();

    /// Safe decoding of header bytes avoiding unaligned memory dereferencing.
    pub fn from_raw_bytes(bytes: &[u8]) -> Option<Self> {
        use rux_core::config as cfg;
        debug_assert_eq!(Self::SIZE, cfg::IPC_HEADER_WIRE_SIZE);
        if bytes.len() >= Self::SIZE {
            let msg_type = bytes[0];
            let offset = cfg::IPC_HEADER_SIZE_FIELD_OFFSET;
            let size_bytes: [u8; 8] = bytes[offset..offset + 8].try_into().ok()?;
            let size = usize::from_ne_bytes(size_bytes);
            Some(Self { msg_type, size })
        } else {
            None
        }
    }
}

/// Thread-safe IPC command receiver coordinating UI execution commands with the payload.
#[derive(Debug)]
pub struct IpcServer {
    active_host: String,
    active_port: u16,
    listener: TcpListener,
    script_queue: Arc<Mutex<VecDeque<String>>>,
    running: Arc<AtomicBool>,
}

impl IpcServer {
    /// Bind to the first available TCP port starting from `base_port` (or dynamically configured).
    pub fn bind_auto(base_port: u16) -> std::io::Result<Self> {
        let host = get_ipc_host();
        let mut last_err = None;

        for offset in 0..MAX_PORT_ATTEMPTS {
            let port = base_port + offset;
            match TcpListener::bind((host.as_str(), port)) {
                Ok(listener) => {
                    let _ = listener.set_nonblocking(false);
                    return Ok(Self {
                        active_host: host,
                        active_port: port,
                        listener,
                        script_queue: Arc::new(Mutex::new(VecDeque::new())),
                        running: Arc::new(AtomicBool::new(true)),
                    });
                }
                Err(e) => {
                    last_err = Some(e);
                }
            }
        }

        Err(last_err.unwrap_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::AddrInUse,
                format!(
                    "No available ports in IPC range {}:{}..{}",
                    host,
                    base_port,
                    base_port + MAX_PORT_ATTEMPTS
                ),
            )
        }))
    }

    /// Retrieve the active TCP port the server is listening on.
    pub fn port(&self) -> u16 {
        self.active_port
    }

    /// Retrieve the host IP the server is bound to.
    pub fn host(&self) -> &str {
        &self.active_host
    }

    /// Retrieve a clone of the script queue handle.
    pub fn script_queue(&self) -> Arc<Mutex<VecDeque<String>>> {
        Arc::clone(&self.script_queue)
    }

    /// Pop the next pending script to execute.
    pub fn pop_script(&self) -> Option<String> {
        self.script_queue.lock().pop_front()
    }

    /// Stop the server thread loop.
    pub fn stop(&self) {
        // Release pairs with the Acquire loads in the accept/client loops below.
        self.running.store(false, Ordering::Release);
    }

    /// Spawn the IPC listener in a background worker thread.
    ///
    /// Spawns separate worker tasks for attached clients to prevent blocking the accept loop.
    pub fn start(&self) -> thread::JoinHandle<()> {
        let listener = self.listener.try_clone().expect("Failed to clone listener");
        let queue = Arc::clone(&self.script_queue);
        let running = Arc::clone(&self.running);
        let host = self.active_host.clone();
        let port = self.active_port;

        thread::spawn(move || {
            println!("[IPC] Listening on {}:{}.", host, port);

            for stream_res in listener.incoming() {
                if !running.load(Ordering::Acquire) {
                    break;
                }

                match stream_res {
                    Ok(stream) => {
                        println!("[IPC] UI Attached.");
                        let client_queue = Arc::clone(&queue);
                        let client_running = Arc::clone(&running);
                        // Concurrent client handling prevents one slow/hanging client from deadlocking the server
                        thread::spawn(move || {
                            handle_client(stream, &client_queue, &client_running);
                        });
                    }
                    Err(e) => {
                        if !running.load(Ordering::Acquire) {
                            break;
                        }
                        eprintln!("[IPC] Accept error: {}", e);
                        thread::sleep(Duration::from_millis(
                            rux_core::config::IPC_ACCEPT_RETRY_DELAY_MS,
                        ));
                    }
                }
            }
        })
    }
}

fn handle_client(
    mut stream: TcpStream,
    queue: &Arc<Mutex<VecDeque<String>>>,
    running: &Arc<AtomicBool>,
) {
    let header_size = IpcHeader::SIZE;
    let mut header_buf = [0u8; rux_core::config::IPC_HEADER_WIRE_SIZE]; // stack, zero heap allocation
    let max_message_size = get_max_message_size();

    // Optional authentication token
    let auth_token = SettingsStore::global()
        .get_string(rux_core::config::SETTINGS_IPC_AUTH_TOKEN)
        .or_else(|| std::env::var(rux_core::config::ENV_IPC_AUTH_TOKEN).ok());

    while running.load(Ordering::Acquire) {
        // Read header
        if let Err(e) = stream.read_exact(&mut header_buf[..header_size]) {
            if e.kind() != std::io::ErrorKind::UnexpectedEof {
                eprintln!("[IPC] Client disconnected: {}", e);
            }
            break;
        }

        let header = match IpcHeader::from_raw_bytes(&header_buf[..header_size]) {
            Some(h) => h,
            None => {
                eprintln!("[IPC] Malformed message header received");
                break;
            }
        };

        // Handle PING
        if header.msg_type == IPC_PING {
            let _ = stream.write_all(&[PONG_BYTE]);
            let _ = stream.flush();
            continue;
        }

        // Validate payload length
        if header.size > max_message_size {
            eprintln!(
                "[IPC] Message size exceeds limit: {} bytes (max: {} bytes)",
                header.size, max_message_size
            );
            break;
        }

        // Read payload body safely
        let mut body = vec![0u8; header.size];
        if let Err(e) = stream.read_exact(&mut body) {
            eprintln!("[IPC] Failed to read message body: {}", e);
            break;
        }

        let body_str = String::from_utf8_lossy(&body).to_string();

        match header.msg_type {
            IPC_SETTING => {
                let mut parts = body_str.splitn(2, ' ');
                if let (Some(k), Some(v)) = (parts.next(), parts.next()) {
                    println!("[IPC] Setting Event -> {}: {}", k, v);
                    SettingsStore::global().handle_setting(k, v);
                }
            }
            IPC_EXECUTE => {
                // If an auth token is required, ensure it is verified
                if let Some(ref required_token) = auth_token {
                    let mut lines = body_str.splitn(2, '\n');
                    let provided_token = lines.next().unwrap_or("");
                    if provided_token != required_token {
                        eprintln!("[IPC] Unauthorized script execution attempt rejected.");
                        continue;
                    }
                    let actual_script = lines.next().unwrap_or("");
                    println!(
                        "[IPC] Received Authenticated Script Execution Request ({} bytes)",
                        actual_script.len()
                    );
                    queue.lock().push_back(actual_script.to_string());
                } else {
                    println!(
                        "[IPC] Received Script Execution Request ({} bytes)",
                        body.len()
                    );
                    queue.lock().push_back(body_str);
                }
            }
            _ => {
                eprintln!("[IPC] Unknown message type: {}", header.msg_type);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ipc_server_bind_and_ping() {
        let server = IpcServer::bind_auto(rux_core::config::IPC_TEST_PORT_START)
            .expect("Failed to bind test IPC server");
        let port = server.port();
        let _handle = server.start();

        // Connect as client and send PING
        let mut client = TcpStream::connect((rux_core::config::DEFAULT_IPC_HOST, port))
            .expect("Failed to connect to IPC");
        let header = IpcHeader {
            msg_type: IPC_PING,
            size: 0,
        };

        let header_bytes = unsafe {
            std::slice::from_raw_parts(
                &header as *const _ as *const u8,
                std::mem::size_of::<IpcHeader>(),
            )
        };
        client.write_all(header_bytes).expect("Failed to send ping");

        let mut pong = [0u8; 1];
        client.read_exact(&mut pong).expect("Failed to read pong");
        assert_eq!(pong[0], PONG_BYTE);

        // Send EXECUTE
        let script = "print('Hello from Rust IPC test!')";
        let exec_header = IpcHeader {
            msg_type: IPC_EXECUTE,
            size: script.len(),
        };
        let exec_header_bytes = unsafe {
            std::slice::from_raw_parts(
                &exec_header as *const _ as *const u8,
                std::mem::size_of::<IpcHeader>(),
            )
        };
        client.write_all(exec_header_bytes).unwrap();
        client.write_all(script.as_bytes()).unwrap();

        // Give the handler thread a moment to process
        thread::sleep(Duration::from_millis(
            rux_core::config::IPC_ACCEPT_RETRY_DELAY_MS,
        ));
        let popped = server.pop_script();
        assert_eq!(popped.as_deref(), Some(script));

        server.stop();
    }
}
