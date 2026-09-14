use crate::arch::CpuArchitecture;
use std::ffi::CStr;
use std::path::PathBuf;
use thiserror::Error;

/// Format a Mach kernel return code (`kern_return_t`) into a human-readable string.
pub fn mach_error_string(kr: i32) -> String {
    unsafe {
        let err_ptr = libc::mach_error_string(kr);
        if !err_ptr.is_null() {
            if let Ok(s) = CStr::from_ptr(err_ptr).to_str() {
                return format!("{} (code {})", s, kr);
            }
        }
    }
    match kr {
        0 => "success (0)".to_string(),
        1 => "invalid address (1)".to_string(),
        2 => "protection failure (2)".to_string(),
        3 => "no space (3)".to_string(),
        4 => "invalid argument (4)".to_string(),
        5 => "failure (5)".to_string(),
        code => format!("mach error code {}", code),
    }
}

/// Comprehensive errors produced during Darwin Mach-O dynamic library injection.
#[derive(Debug, Error)]
pub enum InjectError {
    #[error("Invalid argument: {0}")]
    InvalidArguments(String),

    #[error("Dylib file not found or inaccessible at '{0}'")]
    FileNotFound(PathBuf),

    #[error("Target process '{0}' was not found or is not running")]
    ProcessNotFound(String),

    #[error(
        "task_for_pid() failed for PID {pid}: {message} (kern_return {kern_return}, running_as_root={is_root})"
    )]
    TaskForPidFailed {
        pid: i32,
        kern_return: i32,
        message: String,
        is_root: bool,
    },

    #[error("Architecture mismatch: target process is {target}, but injector host is {host}")]
    ArchitectureMismatch {
        target: CpuArchitecture,
        host: CpuArchitecture,
    },

    #[error("Failed to allocate remote virtual memory: {message}")]
    VmAllocateFailed { kern_return: i32, message: String },

    #[error("Failed to write to remote address 0x{address:x} ({size} bytes): {message}")]
    VmWriteFailed {
        kern_return: i32,
        address: u64,
        size: usize,
        message: String,
    },

    #[error("Failed to set memory protection for address 0x{address:x}: {message}")]
    VmProtectFailed {
        kern_return: i32,
        address: u64,
        message: String,
    },

    #[error("Failed to deallocate remote memory at 0x{address:x}: {message}")]
    VmDeallocateFailed {
        kern_return: i32,
        address: u64,
        message: String,
    },

    #[error("Failed to create and start remote thread: {message}")]
    ThreadCreateFailed { kern_return: i32, message: String },

    #[error("Remote dlopen() execution returned NULL; library failed to load")]
    DlopenFailed,

    #[error("Timeout after {timeout_ms} ms waiting for remote thread completion")]
    Timeout { timeout_ms: u64 },

    #[error("Failed to resolve required system symbols: {0}")]
    NoSymbols(String),

    #[error("Cleanup operation failed: {0}")]
    CleanupFailed(String),

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

impl InjectError {
    /// Convert error into a legacy C integer error code matching `mach_inject.h`.
    pub fn to_c_error_code(&self) -> i32 {
        match self {
            Self::InvalidArguments(_) => -1,
            Self::FileNotFound(_) => -2,
            Self::ProcessNotFound(_) => -3,
            Self::TaskForPidFailed { .. } => -4,
            Self::ArchitectureMismatch { .. } => -5,
            Self::VmAllocateFailed { .. } => -6,
            Self::VmWriteFailed { .. } => -7,
            Self::VmProtectFailed { .. } => -8,
            Self::ThreadCreateFailed { .. } => -9,
            Self::DlopenFailed => -10,
            Self::Timeout { .. } => -11,
            Self::NoSymbols(_) => -12,
            Self::CleanupFailed(_) => -13,
            Self::VmDeallocateFailed { .. } => -13,
            Self::Io(_) => -2,
        }
    }
}

/// Standard Result alias for injection operations.
pub type Result<T, E = InjectError> = std::result::Result<T, E>;
