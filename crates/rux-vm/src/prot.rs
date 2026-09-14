use crate::sys::{
    VM_PROT_ALL, VM_PROT_DEFAULT, VM_PROT_EXECUTE, VM_PROT_NONE, VM_PROT_READ, VM_PROT_WRITE,
};
use mach2::vm_prot::vm_prot_t;
use std::fmt;
use std::ops::{BitOr, BitOrAssign};

/// Virtual memory page protection flags.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VmProtection(pub vm_prot_t);

impl VmProtection {
    /// No permissions
    pub const NONE: Self = Self(VM_PROT_NONE);
    /// Read permission
    pub const READ: Self = Self(VM_PROT_READ);
    /// Write permission
    pub const WRITE: Self = Self(VM_PROT_WRITE);
    /// Execute permission
    pub const EXECUTE: Self = Self(VM_PROT_EXECUTE);
    /// Read and Write (Default)
    pub const READ_WRITE: Self = Self(VM_PROT_DEFAULT);
    /// Read and Execute
    pub const READ_EXECUTE: Self = Self(VM_PROT_READ | VM_PROT_EXECUTE);
    /// Read, Write, and Execute
    pub const ALL: Self = Self(VM_PROT_ALL);

    /// Convert from raw Mach `vm_prot_t`.
    pub fn from_raw(raw: vm_prot_t) -> Self {
        Self(raw)
    }

    /// Convert to raw Mach `vm_prot_t`.
    pub fn to_raw(self) -> vm_prot_t {
        self.0
    }

    /// Check if this protection contains another protection.
    pub fn contains(self, other: Self) -> bool {
        (self.0 & other.0) == other.0
    }
}

impl BitOr for VmProtection {
    type Output = Self;

    fn bitor(self, rhs: Self) -> Self::Output {
        Self(self.0 | rhs.0)
    }
}

impl BitOrAssign for VmProtection {
    fn bitor_assign(&mut self, rhs: Self) {
        self.0 |= rhs.0;
    }
}

impl fmt::Display for VmProtection {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let r = if self.contains(Self::READ) { "r" } else { "-" };
        let w = if self.contains(Self::WRITE) { "w" } else { "-" };
        let x = if self.contains(Self::EXECUTE) {
            "x"
        } else {
            "-"
        };
        write!(f, "{}{}{}", r, w, x)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vm_protection_flags() {
        let rw = VmProtection::READ | VmProtection::WRITE;
        assert_eq!(rw, VmProtection::READ_WRITE);
        assert!(rw.contains(VmProtection::READ));
        assert!(rw.contains(VmProtection::WRITE));
        assert!(!rw.contains(VmProtection::EXECUTE));
        assert_eq!(format!("{}", rw), "rw-");
        assert_eq!(format!("{}", VmProtection::READ_EXECUTE), "r-x");
    }
}
