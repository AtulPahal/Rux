use std::fmt;

/// Darwin CPU architecture constants from `<mach/machine.h>`.
pub const CPU_TYPE_ANY: i32 = -1;
pub const CPU_TYPE_VAX: i32 = 1;
#[allow(non_upper_case_globals)]
pub const CPU_TYPE_MC680x0: i32 = 6;
pub const CPU_TYPE_X86: i32 = 7;
pub const CPU_TYPE_I386: i32 = CPU_TYPE_X86;
pub const CPU_ARCH_ABI64: i32 = 0x0100_0000;
pub const CPU_TYPE_X86_64: i32 = CPU_TYPE_X86 | CPU_ARCH_ABI64;
pub const CPU_TYPE_MC98000: i32 = 10;
pub const CPU_TYPE_HPPA: i32 = 11;
pub const CPU_TYPE_ARM: i32 = 12;
pub const CPU_TYPE_ARM64: i32 = CPU_TYPE_ARM | CPU_ARCH_ABI64;
pub const CPU_TYPE_MC88000: i32 = 13;
pub const CPU_TYPE_SPARC: i32 = 14;
pub const CPU_TYPE_I860: i32 = 15;
pub const CPU_TYPE_POWERPC: i32 = 18;
pub const CPU_TYPE_POWERPC64: i32 = CPU_TYPE_POWERPC | CPU_ARCH_ABI64;

/// Strongly typed CPU architecture representation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CpuArchitecture {
    /// 64-bit ARM (Apple Silicon)
    Arm64,
    /// 64-bit x86 (Intel 64-bit)
    X86_64,
    /// 32-bit ARM
    Arm32,
    /// 32-bit x86
    X86_32,
    /// Unknown or unsupported CPU architecture code
    Unknown(i32),
}

impl CpuArchitecture {
    /// Convert from Darwin Mach-O `cpu_type_t` integer.
    pub fn from_raw(raw: i32) -> Self {
        match raw {
            CPU_TYPE_ARM64 => Self::Arm64,
            CPU_TYPE_X86_64 => Self::X86_64,
            CPU_TYPE_ARM => Self::Arm32,
            CPU_TYPE_X86 => Self::X86_32,
            other => Self::Unknown(other),
        }
    }

    /// Convert to Darwin Mach-O `cpu_type_t` integer.
    pub fn to_raw(self) -> i32 {
        match self {
            Self::Arm64 => CPU_TYPE_ARM64,
            Self::X86_64 => CPU_TYPE_X86_64,
            Self::Arm32 => CPU_TYPE_ARM,
            Self::X86_32 => CPU_TYPE_X86,
            Self::Unknown(code) => code,
        }
    }

    /// Retrieve the host CPU architecture at compile/runtime.
    pub fn host() -> Self {
        #[cfg(target_arch = "aarch64")]
        {
            Self::Arm64
        }
        #[cfg(target_arch = "x86_64")]
        {
            Self::X86_64
        }
        #[cfg(target_arch = "arm")]
        {
            Self::Arm32
        }
        #[cfg(target_arch = "x86")]
        {
            Self::X86_32
        }
        #[cfg(not(any(
            target_arch = "aarch64",
            target_arch = "x86_64",
            target_arch = "arm",
            target_arch = "x86"
        )))]
        {
            Self::Unknown(0)
        }
    }

    /// Returns a human-readable string identifier for the architecture.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Arm64 => "arm64",
            Self::X86_64 => "x86_64",
            Self::Arm32 => "arm32",
            Self::X86_32 => "x86",
            Self::Unknown(_) => "unknown",
        }
    }

    /// Returns whether this architecture is a 64-bit target supported for injection.
    pub fn is_supported_64bit(self) -> bool {
        matches!(self, Self::Arm64 | Self::X86_64)
    }
}

impl fmt::Display for CpuArchitecture {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unknown(code) => write!(f, "unknown(0x{:x})", code),
            other => write!(f, "{}", other.as_str()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cpu_architecture_roundtrip() {
        assert_eq!(
            CpuArchitecture::from_raw(CPU_TYPE_ARM64),
            CpuArchitecture::Arm64
        );
        assert_eq!(
            CpuArchitecture::from_raw(CPU_TYPE_X86_64),
            CpuArchitecture::X86_64
        );
        assert_eq!(CpuArchitecture::Arm64.to_raw(), CPU_TYPE_ARM64);
        assert_eq!(CpuArchitecture::X86_64.to_raw(), CPU_TYPE_X86_64);
        assert_eq!(CpuArchitecture::Arm64.as_str(), "arm64");
        assert_eq!(CpuArchitecture::X86_64.as_str(), "x86_64");
    }

    #[test]
    fn test_host_architecture() {
        let host = CpuArchitecture::host();
        assert!(host.is_supported_64bit());
    }
}
