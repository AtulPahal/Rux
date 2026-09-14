use std::fmt;
use std::time::Duration;

/// Dynamic library loading mode corresponding to `dlopen()` flags.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum DlopenMode {
    /// Relocations are resolved when the library is loaded (`RTLD_NOW`).
    #[default]
    Now,
    /// Relocations are resolved as symbols are referenced (`RTLD_LAZY`).
    Lazy,
}

impl DlopenMode {
    /// Convert to Darwin libc flag bitmask.
    pub fn to_raw(self) -> libc::c_int {
        match self {
            Self::Now => libc::RTLD_NOW,
            Self::Lazy => libc::RTLD_LAZY,
        }
    }

    /// Parse from string identifier ("now", "lazy").
    pub fn from_str_lenient(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "now" | "rtld_now" => Some(Self::Now),
            "lazy" | "rtld_lazy" => Some(Self::Lazy),
            _ => None,
        }
    }

    /// String representation.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Now => "now",
            Self::Lazy => "lazy",
        }
    }
}

impl fmt::Display for DlopenMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Options controlling dynamic library injection behavior.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InjectionOptions {
    /// Emit verbose diagnostic messages to standard output / error.
    pub verbose: bool,
    /// Wait for remote execution and confirmation of `dlopen()`.
    pub wait_completion: bool,
    /// Maximum duration to wait when `wait_completion` is enabled.
    pub timeout: Duration,
    /// Flags passed to remote `dlopen()`.
    pub dlopen_mode: DlopenMode,
}

impl Default for InjectionOptions {
    fn default() -> Self {
        Self {
            verbose: false,
            wait_completion: true,
            timeout: Duration::from_millis(crate::config::DEFAULT_INJECTION_TIMEOUT_MS),
            dlopen_mode: DlopenMode::Now,
        }
    }
}

impl InjectionOptions {
    /// Create a new builder for `InjectionOptions`.
    pub fn builder() -> InjectionOptionsBuilder {
        InjectionOptionsBuilder::default()
    }
}

/// Builder for `InjectionOptions`.
#[derive(Debug, Clone, Default)]
pub struct InjectionOptionsBuilder {
    options: InjectionOptions,
}

impl InjectionOptionsBuilder {
    /// Set verbose diagnostic output.
    pub fn verbose(mut self, verbose: bool) -> Self {
        self.options.verbose = verbose;
        self
    }

    /// Set whether to wait for remote completion.
    pub fn wait_completion(mut self, wait: bool) -> Self {
        self.options.wait_completion = wait;
        self
    }

    /// Set wait timeout.
    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.options.timeout = timeout;
        self
    }

    /// Set wait timeout in milliseconds.
    pub fn timeout_ms(mut self, ms: u64) -> Self {
        self.options.timeout = Duration::from_millis(ms);
        self
    }

    /// Set dlopen loading mode.
    pub fn dlopen_mode(mut self, mode: DlopenMode) -> Self {
        self.options.dlopen_mode = mode;
        self
    }

    /// Build the finalized options struct.
    pub fn build(self) -> InjectionOptions {
        self.options
    }
}

/// Detailed outcome of a successful or completed injection attempt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InjectionResult {
    /// Remote module handle returned by `dlopen()` in the target process.
    pub remote_handle: u64,
    /// Execution status (0 = pending, 1 = success, -1 = dlopen failed).
    pub status: i32,
    /// Total duration elapsed during the injection procedure.
    pub elapsed: Duration,
}

impl InjectionResult {
    /// Returns true if the injection was verified successful.
    pub fn is_success(&self) -> bool {
        self.status == 1 && self.remote_handle != 0
    }
}
