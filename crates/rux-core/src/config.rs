//! Centralized runtime defaults for the Rux toolchain.
//!
//! Single source of truth for every tunable that was previously a duplicated
//! literal: IPC networking, HTTP limits, injection timing, environment variable
//! names, and settings-store keys. All values remain overridable at runtime via
//! the payload [`SettingsStore`](https://example.invalid) or environment; this
//! module only fixes *where the fallback lives* so no literal is repeated.

// -------------------------------------------------------------------------
// Injection timing
// -------------------------------------------------------------------------

/// Default wait-for-`dlopen` timeout in milliseconds.
pub const DEFAULT_INJECTION_TIMEOUT_MS: u64 = 3000;

/// Poll interval while waiting for the remote stub status flag, in milliseconds.
pub const INJECT_POLL_INTERVAL_MS: u64 = 10;

/// Grace period letting the remote thread finish `pthread_exit` before its
/// memory is deallocated, in milliseconds.
pub const INJECT_SETTLE_DELAY_MS: u64 = 25;

/// Default target process name used when the user passes neither `--pid`
/// nor `--name`. Overridable via `RUX_DEFAULT_TARGET_NAME` / `RUX_TARGET_PROCESS`.
pub const DEFAULT_TARGET_PROCESS_NAME: &str = "RobloxPlayer";

/// Environment variable overrides for CLI defaults.
pub const ENV_DEFAULT_TARGET_NAME: &str = "RUX_DEFAULT_TARGET_NAME";
pub const ENV_TARGET_PROCESS: &str = "RUX_TARGET_PROCESS";
pub const ENV_DEFAULT_TIMEOUT_MS: &str = "RUX_DEFAULT_TIMEOUT_MS";

// -------------------------------------------------------------------------
// IPC transport (payload <-> UI)
// -------------------------------------------------------------------------

/// Loopback host the payload binds to when nothing else is configured.
pub const DEFAULT_IPC_HOST: &str = "127.0.0.1";

/// First TCP port probed when binding the payload IPC server.
pub const DEFAULT_IPC_PORT_START: u16 = 5553;

/// Number of consecutive ports probed starting from the start port.
pub const IPC_PORT_ATTEMPTS: u16 = 10;

/// Lowest / highest valid TCP port accepted from configuration.
pub const IPC_PORT_MIN: i64 = 1024;
pub const IPC_PORT_MAX: i64 = 65535;

/// Upper bound for a single IPC message body in bytes (16 MiB).
pub const DEFAULT_IPC_MAX_MESSAGE_SIZE: usize = 16 * 1024 * 1024;

/// Retry delay after a failed `accept()` on the IPC listener, in milliseconds.
pub const IPC_ACCEPT_RETRY_DELAY_MS: u64 = 50;

/// Fixed wire size of [`IpcHeader`](https://example.invalid) on 64-bit Darwin
/// (`u8` type + 7 padding bytes + `usize` length). Both Rust and Swift peers
/// must agree on this value.
pub const IPC_HEADER_WIRE_SIZE: usize = 16;

/// Byte offset of the `size` field inside the wire header. Kept symbolic so a
/// future `repr(packed)` change only touches this constant.
pub const IPC_HEADER_SIZE_FIELD_OFFSET: usize = 8;

/// Poll interval of the payload script-queue dispatcher loop, in milliseconds.
pub const DISPATCHER_POLL_INTERVAL_MS: u64 = 10;

/// Wire message types. Must match the Swift `IpcClient` peer.
pub const IPC_MSG_EXECUTE: u8 = 0;
pub const IPC_MSG_SETTING: u8 = 1;
pub const IPC_MSG_PING: u8 = 2;

/// Single-byte acknowledgement sent in reply to `IPC_MSG_PING`.
pub const IPC_PONG_BYTE: u8 = 0x10;

/// Environment variable overrides for IPC transport tuning.
pub const ENV_IPC_HOST: &str = "RUX_IPC_HOST";
pub const ENV_IPC_PORT: &str = "RUX_IPC_PORT";
pub const ENV_IPC_MAX_MSG_SIZE: &str = "RUX_IPC_MAX_MSG_SIZE";
pub const ENV_IPC_AUTH_TOKEN: &str = "RUX_IPC_AUTH_TOKEN";

// -------------------------------------------------------------------------
// HTTP client
// -------------------------------------------------------------------------

/// Default request timeout in seconds.
pub const DEFAULT_HTTP_TIMEOUT_SECS: i64 = 30;

/// Upper bound for a response body in bytes (64 MiB).
pub const DEFAULT_HTTP_MAX_RESPONSE_SIZE: usize = 64 * 1024 * 1024;

/// Default `User-Agent` sent when the caller supplies none.
pub const DEFAULT_HTTP_USER_AGENT: &str = "Roblox/WinInet";

/// Default hardware-fingerprint header names.
pub const DEFAULT_FINGERPRINT_HEADER: &str = "Macsploit-Fingerprint";
pub const DEFAULT_COMPAT_FINGERPRINT_HEADER: &str = "Hydrogen-Fingerprint";

/// Environment variable override for the default user agent.
pub const ENV_HTTP_USER_AGENT: &str = "RUX_USER_AGENT";

// -------------------------------------------------------------------------
// Device identity / whitelist
// -------------------------------------------------------------------------

/// Anonymous fingerprint returned while `offlineMode` is enabled or when no
/// hardware UUID is available. 40 hex chars (SHA-1 length) of zeroes.
pub const ANONYMOUS_FINGERPRINT: &str = "0000000000000000000000000000000000000000";

/// Default client fingerprint suffix appended by `parsed_fingerprint()`.
pub const DEFAULT_FINGERPRINT_SUFFIX: &str = "5f4d53";

/// Markers parsed from the whitelist verification response body.
pub const WHITELIST_COMPLETE_MARKER: &str = "Whitelist check complete.";
pub const WHITELIST_BOOSTER_MARKER: &str = "Server Booster.";
pub const WHITELIST_EARLY_ACCESS_MARKER: &str = "Early Access.";
/// No remote verification endpoint is bundled: online whitelist checks require
/// explicit configuration via settings (`whitelistUrl`) or `RUX_WHITELIST_URL`.
/// An empty base disables remote verification instead of phoning home.
pub const DEFAULT_WHITELIST_URL: &str = "";

/// Timeout for the `gethostuuid` syscall, in seconds.
pub const GETHOSTUUID_TIMEOUT_SECS: i64 = 1;

/// Environment variable overrides for identity tuning.
pub const ENV_FINGERPRINT_SUFFIX: &str = "RUX_FINGERPRINT_SUFFIX";
pub const ENV_WHITELIST_URL: &str = "RUX_WHITELIST_URL";
pub const ENV_INIT_SCRIPT_PATH: &str = "RUX_INIT_SCRIPT_PATH";

// -------------------------------------------------------------------------
// Settings-store keys (shared by every payload subsystem)
// -------------------------------------------------------------------------

pub const SETTINGS_DEBUG_LIBRARY: &str = "debugLibrary";
pub const SETTINGS_EXECUTE_INSTANCES: &str = "executeInstances";
pub const SETTINGS_COMPATIBILITY_MODE: &str = "compatibilityMode";
pub const SETTINGS_HTTP_TRAFFIC: &str = "httpTraffic";
pub const SETTINGS_ROBLOX_RPC: &str = "robloxRpc";
pub const SETTINGS_DISCORD_RPC: &str = "discordRpc";
pub const SETTINGS_MACSPLIT: &str = "macsploit";
pub const SETTINGS_SERVER_TELEPORTS: &str = "serverTeleports";
pub const SETTINGS_PLACE_RESTRICTIONS: &str = "placeRestrictions";
pub const SETTINGS_OFFLINE_MODE: &str = "offlineMode";

pub const SETTINGS_IPC_HOST: &str = "ipcHost";
pub const SETTINGS_IPC_PORT: &str = "ipcPort";
pub const SETTINGS_IPC_MAX_MESSAGE_SIZE: &str = "ipcMaxMessageSize";
pub const SETTINGS_IPC_AUTH_TOKEN: &str = "ipcAuthToken";

pub const SETTINGS_HTTP_TIMEOUT: &str = "httpTimeout";
pub const SETTINGS_HTTP_MAX_RESPONSE_SIZE: &str = "httpMaxResponseSize";
pub const SETTINGS_USER_AGENT: &str = "userAgent";
pub const SETTINGS_FINGERPRINT_HEADER: &str = "fingerprintHeader";
pub const SETTINGS_COMPAT_FINGERPRINT_HEADER: &str = "compatFingerprintHeader";

pub const SETTINGS_SPOOFED_HWID: &str = "spoofedHwid";
pub const SETTINGS_FINGERPRINT_SUFFIX: &str = "fingerprintSuffix";
pub const SETTINGS_WHITELIST_URL: &str = "whitelistUrl";

pub const SETTINGS_INIT_SCRIPT: &str = "initScript";
pub const SETTINGS_RPC_SCRIPT: &str = "rpcScript";

/// Stack buffer capacity for short NUL-terminated string writes (no heap alloc).
pub const VM_WRITE_STRING_STACK_CAP: usize = 512;

// -------------------------------------------------------------------------
// Diagnostics
// -------------------------------------------------------------------------

/// Scratch allocation size used by the self-test VM round-trip.
pub const DIAGNOSTIC_TEST_ALLOC_BYTES: usize = 4096;

/// Extra PID slots reserved in `list_pids` for processes spawned between the
/// size probe and the fill call.
pub const PROC_LIST_SLACK_ENTRIES: usize = 64;

/// Maximum bytes per `getentropy(2)` call; longer requests are chunked.
pub const GETENTROPY_MAX_CHUNK: usize = 256;

/// Base port used only by the IPC unit test (outside the 5553 production range).
pub const IPC_TEST_PORT_START: u16 = 15553;

// -------------------------------------------------------------------------
// Remote memory layout (injector <-> stub contract)
// -------------------------------------------------------------------------

/// Remote stack reserved for the injection thread (64 KiB).
pub const REMOTE_STACK_SIZE: usize = 64 * 1024;

/// Remote code block holding the position-independent stub (4 KiB).
pub const REMOTE_CODE_ALLOC_SIZE: usize = 4096;

/// Capacity of the null-terminated dylib path inside `InjectParams`, in bytes.
pub const INJECT_DYLIB_PATH_CAP: usize = 1024;

/// Byte offsets of `InjectParams` fields. Must match `ARM64_STUB`/`X86_64_STUB`.
pub const INJECT_OFF_MODE: usize = 1024;
pub const INJECT_OFF_STATUS: usize = 1028;
pub const INJECT_OFF_DLOPEN_ADDR: usize = 1032;
pub const INJECT_OFF_PTHREAD_SET_SELF_ADDR: usize = 1040;
pub const INJECT_OFF_PTHREAD_EXIT_ADDR: usize = 1048;
pub const INJECT_OFF_DLOPEN_RESULT: usize = 1056;

// -------------------------------------------------------------------------
// Swift UI defaults (mirrored so CLI and GUI agree)
// -------------------------------------------------------------------------

/// Default injection timeout surfaced in the Injector tab, in milliseconds.
pub const UI_DEFAULT_TIMEOUT_MS: f64 = 3000.0;
/// Slider bounds for the timeout control, in milliseconds.
pub const UI_TIMEOUT_SLIDER_MIN_MS: f64 = 500.0;
pub const UI_TIMEOUT_SLIDER_MAX_MS: f64 = 10_000.0;

/// Default socket timeouts used by the Swift IPC client, in seconds.
pub const UI_IPC_DEFAULT_TIMEOUT_SECS: i32 = 2;
pub const UI_IPC_PING_TIMEOUT_SECS: i32 = 1;

/// Cap for retained log entries in the Activity Logs tab.
pub const UI_LOG_MAX_ENTRIES: usize = 1000;
/// Refresh interval for the live log stream, in seconds.
pub const UI_LOG_REFRESH_INTERVAL_SECS: f64 = 0.25;
/// Delay before the process list applies its first filter, in seconds.
pub const UI_PROCESS_INITIAL_FILTER_DELAY_SECS: f64 = 0.3;
/// Poll interval while waiting for diagnostics to finish, in seconds.
pub const UI_DIAGNOSTICS_POLL_INTERVAL_SECS: f64 = 0.1;

/// Default window and content sizes, in points.
pub const UI_WINDOW_WIDTH: f64 = 880.0;
pub const UI_WINDOW_HEIGHT: f64 = 820.0;
pub const UI_WINDOW_MIN_WIDTH: f64 = 820.0;
pub const UI_WINDOW_MIN_HEIGHT: f64 = 700.0;
pub const UI_CONTENT_HEIGHT: f64 = 750.0;
