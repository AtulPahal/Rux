use crate::prot::VmProtection;
use crate::sys::{mach_vm_deallocate, mach_vm_protect, MACH_FALSE};
use mach2::kern_return::KERN_SUCCESS;
use mach2::port::mach_port_t;
use mach2::vm_types::mach_vm_size_t;
use rux_core::{mach_error_string, InjectError, Result};

/// An RAII-guarded allocation of virtual memory inside a target Darwin task.
///
/// Automatically deallocates the remote memory block when dropped, unless explicitly
/// consumed via [`RemoteAllocation::leak`] or [`RemoteAllocation::forget`].
#[derive(Debug)]
pub struct RemoteAllocation {
    task_port: mach_port_t,
    address: u64,
    size: usize,
    active: bool,
}

impl RemoteAllocation {
    /// Create a new `RemoteAllocation` wrapping an allocated remote memory span.
    ///
    /// # Safety
    /// Caller must guarantee `address` and `size` describe an active allocation inside `task_port`.
    pub unsafe fn from_raw(task_port: mach_port_t, address: u64, size: usize) -> Self {
        Self {
            task_port,
            address,
            size,
            active: true,
        }
    }

    /// Retrieve the base address of the allocated remote memory range.
    pub fn address(&self) -> u64 {
        self.address
    }

    /// Retrieve the allocated size in bytes.
    pub fn size(&self) -> usize {
        self.size
    }

    /// Change the memory protection for this allocation.
    pub fn protect(&mut self, prot: VmProtection) -> Result<()> {
        unsafe {
            let kr = mach_vm_protect(
                self.task_port,
                self.address,
                self.size as mach_vm_size_t,
                MACH_FALSE,
                prot.to_raw(),
            );
            if kr != KERN_SUCCESS {
                return Err(InjectError::VmProtectFailed {
                    kern_return: kr,
                    address: self.address,
                    message: mach_error_string(kr),
                });
            }
        }
        Ok(())
    }

    /// Explicitly deallocate this memory region immediately, consuming the handle.
    pub fn deallocate(mut self) -> Result<()> {
        if self.active && self.address != 0 && self.size != 0 {
            self.active = false;
            unsafe {
                let kr =
                    mach_vm_deallocate(self.task_port, self.address, self.size as mach_vm_size_t);
                if kr != KERN_SUCCESS {
                    return Err(InjectError::VmDeallocateFailed {
                        kern_return: kr,
                        address: self.address,
                        message: mach_error_string(kr),
                    });
                }
            }
        }
        Ok(())
    }

    /// Disarm the RAII destructor and return the remote address, preventing automatic deallocation.
    pub fn leak(mut self) -> u64 {
        self.active = false;
        self.address
    }

    /// Disarm the RAII destructor without returning the address.
    pub fn forget(mut self) {
        self.active = false;
    }
}

impl Drop for RemoteAllocation {
    fn drop(&mut self) {
        if self.active && self.address != 0 && self.size != 0 {
            unsafe {
                let _ =
                    mach_vm_deallocate(self.task_port, self.address, self.size as mach_vm_size_t);
            }
        }
    }
}
