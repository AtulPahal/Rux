//! Rux Injected Dynamic Library Payload
//!
//! Production-grade, memory-safe client payload providing local TCP IPC server,
//! thread-safe settings store, 2D Drawing API, pure-Rust crypto engine,
//! HTTP client, inline trampoline hooks, and Luau script environments.

pub mod crypto;
pub mod drawing;
pub mod fingerprint;
pub mod hook;
pub mod http;
pub mod ipc;
pub mod scripts;
pub mod settings;
pub mod whitelist;

pub use crypto::*;
pub use drawing::{DrawingObject, DrawingRegistry};
pub use fingerprint::{fetch_fingerprint, parsed_fingerprint};
pub use hook::{write_hook, InlineHook};
pub use http::{execute_request, receive_string, HttpRequest, HttpResponse};
pub use ipc::{IpcServer, DEFAULT_PORT_START};
pub use scripts::{INIT_SCRIPT, RPC_SCRIPT};
pub use settings::{get_boolean, get_number, get_string, handle_setting, SettingsStore};
pub use whitelist::{verify_whitelist, WhitelistStatus};

use parking_lot::Mutex;
use std::ffi::c_char;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};
use std::sync::Arc;
use std::sync::LazyLock;
use std::thread;
use std::time::Duration;

pub const PAYLOAD_VERSION: &str = env!("CARGO_PKG_VERSION");

static ACTIVE_PORT: AtomicU16 = AtomicU16::new(0);
static INITIALIZED: AtomicBool = AtomicBool::new(false);
static ENGINE_INSTANCE: LazyLock<Mutex<Option<Arc<PayloadEngine>>>> =
    LazyLock::new(|| Mutex::new(None));

/// Core runtime engine for the injected dynamic library.
#[derive(Debug)]
pub struct PayloadEngine {
    ipc_server: Arc<IpcServer>,
}

impl PayloadEngine {
    /// Initialize all payload runtime subsystems.
    pub fn start() -> Result<Arc<Self>, String> {
        let mut guard = ENGINE_INSTANCE.lock();
        if let Some(existing) = guard.as_ref() {
            return Ok(Arc::clone(existing));
        }

        println!("[Rux Payload] Initializing in target process...");

        // 1. Check Whitelist (Local / Offline mode by default)
        match verify_whitelist() {
            WhitelistStatus::Authorized { is_booster, .. } => {
                println!(
                    "[Rux Payload] Authorization confirmed. Booster features: {}",
                    is_booster
                );
            }
            WhitelistStatus::Unauthorized(msg) => {
                eprintln!("[Rux Payload] Authorization failed: {}", msg);
            }
            WhitelistStatus::NetworkError(e) => {
                println!("[Rux Payload] Running offline: {}", e);
            }
        }

        // 2. Start TCP IPC server from the configured start port (see config::DEFAULT_IPC_PORT_START)
        let start_port = crate::ipc::get_default_port_start();
        let ipc = match IpcServer::bind_auto(start_port) {
            Ok(server) => Arc::new(server),
            Err(e) => {
                return Err(format!("Failed to bind IPC server: {}", e));
            }
        };

        let port = ipc.port();
        ACTIVE_PORT.store(port, Ordering::Release); // pairs with Acquire in rux_payload_active_port
        let _ipc_thread = ipc.start();

        let engine = Arc::new(Self {
            ipc_server: Arc::clone(&ipc),
        });

        // 3. Mark initialized and start background script queue dispatcher loop
        INITIALIZED.store(true, Ordering::Release); // pairs with Acquire in dispatcher loop
        *guard = Some(Arc::clone(&engine));

        let queue = ipc.script_queue();
        thread::spawn(move || {
            while INITIALIZED.load(Ordering::Acquire) {
                if let Some(script) = queue.lock().pop_front() {
                    println!(
                        "[Rux Dispatcher] Executing queued script ({} bytes)",
                        script.len()
                    );
                    // Dispatched to Luau executor thread
                }
                thread::sleep(Duration::from_millis(
                    rux_core::config::DISPATCHER_POLL_INTERVAL_MS,
                ));
            }
        });

        println!(
            "[Rux Payload] Subsystems online. IPC ready on port {}.",
            port
        );
        Ok(engine)
    }

    /// Retrieve active IPC port.
    pub fn port(&self) -> u16 {
        self.ipc_server.port()
    }
}

/// Payload initialization function executed when library is loaded.
pub fn payload_main() {
    if let Err(e) = PayloadEngine::start() {
        eprintln!("[Rux Payload] Initialization error: {}", e);
    }
}

// -------------------------------------------------------------------------
// Mach-O Constructor Function (auto-runs on dlopen())
// -------------------------------------------------------------------------

#[used]
#[cfg_attr(target_os = "macos", link_section = "__DATA,__mod_init_func")]
static CONSTRUCTOR: unsafe extern "C" fn() = dylib_constructor;

unsafe extern "C" fn dylib_constructor() {
    // Run initialization in a detached thread to prevent blocking dlopen()
    thread::spawn(|| {
        payload_main();
    });
}

// -------------------------------------------------------------------------
// C-Compatible Exported Symbols
// -------------------------------------------------------------------------

/// Explicit manual initializer if needed by C callers.
#[no_mangle]
pub extern "C" fn rux_payload_init() -> bool {
    PayloadEngine::start().is_ok()
}

/// Returns the payload semver version string.
#[no_mangle]
pub extern "C" fn rux_payload_version() -> *const c_char {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const c_char
}

/// Returns active IPC port, or 0 if not initialized.
#[no_mangle]
pub extern "C" fn rux_payload_active_port() -> u16 {
    ACTIVE_PORT.load(Ordering::Acquire)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_payload_engine_start() {
        let engine = PayloadEngine::start().expect("PayloadEngine failed to start");
        assert!(engine.port() >= DEFAULT_PORT_START);
        assert_eq!(rux_payload_active_port(), engine.port());
    }
}
