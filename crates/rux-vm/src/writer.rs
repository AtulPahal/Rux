use crate::allocation::RemoteAllocation;
use crate::prot::VmProtection;
use crate::sys::{
    mach_vm_allocate, mach_vm_deallocate, mach_vm_protect, mach_vm_read_overwrite, mach_vm_write,
    MACH_FALSE, VM_FLAGS_ANYWHERE,
};
use crate::task::MachTask;
use mach2::kern_return::KERN_SUCCESS;
use mach2::message::mach_msg_type_number_t;
use mach2::vm_types::{mach_vm_address_t, mach_vm_size_t, vm_offset_t};
use rux_core::{mach_error_string, InjectError, Result};
use std::mem;

/// High-level, type-safe remote memory writer and manipulator for Darwin tasks.
///
/// Encapsulates allocation, typed writes, typed reads, protection transitions,
/// and deallocation using Mach Virtual Memory primitives (`mach_vm_*`).
#[derive(Debug)]
pub struct MemoryWriter<'a> {
    task: &'a MachTask,
}

impl<'a> MemoryWriter<'a> {
    /// Create a new `MemoryWriter` borrowing a `MachTask`.
    pub fn new(task: &'a MachTask) -> Self {
        Self { task }
    }

    /// Access the underlying `MachTask`.
    pub fn task(&self) -> &MachTask {
        self.task
    }

    /// Allocate a virtual memory block in the target task with specified protection.
    pub fn allocate(&self, size: usize, prot: VmProtection) -> Result<RemoteAllocation> {
        if size == 0 {
            return Err(InjectError::InvalidArguments(
                "Cannot allocate 0 bytes".into(),
            ));
        }

        unsafe {
            let mut addr: mach_vm_address_t = 0;
            let kr = mach_vm_allocate(
                self.task.port(),
                &mut addr,
                size as mach_vm_size_t,
                VM_FLAGS_ANYWHERE,
            );

            if kr != KERN_SUCCESS || addr == 0 {
                return Err(InjectError::VmAllocateFailed {
                    kern_return: kr,
                    message: mach_error_string(kr),
                });
            }

            let mut alloc = RemoteAllocation::from_raw(self.task.port(), addr, size);
            // Default Mach allocation is VM_PROT_DEFAULT (read+write). If caller asked for something else:
            if prot != VmProtection::READ_WRITE {
                alloc.protect(prot)?;
            }

            Ok(alloc)
        }
    }

    /// Write raw byte slice into target process memory at `address`.
    pub fn write_bytes(&self, address: u64, bytes: &[u8]) -> Result<()> {
        if bytes.is_empty() {
            return Ok(());
        }

        unsafe {
            let kr = mach_vm_write(
                self.task.port(),
                address,
                bytes.as_ptr() as vm_offset_t,
                bytes.len() as mach_msg_type_number_t,
            );

            if kr != KERN_SUCCESS {
                return Err(InjectError::VmWriteFailed {
                    kern_return: kr,
                    address,
                    size: bytes.len(),
                    message: mach_error_string(kr),
                });
            }
        }

        Ok(())
    }

    /// Write a typed value into target process memory at `address`.
    pub fn write_val<T: Copy>(&self, address: u64, val: &T) -> Result<()> {
        let size = mem::size_of::<T>();
        let slice = unsafe { std::slice::from_raw_parts(val as *const T as *const u8, size) };
        self.write_bytes(address, slice)
    }

    /// Write a UTF-8 string with null terminator into target process memory.
    ///
    /// Short strings use a stack buffer (no heap allocation); longer ones fall
    /// back to one heap allocation. Either way the bytes land in a single
    /// `mach_vm_write` syscall.
    pub fn write_string(&self, address: u64, s: &str) -> Result<()> {
        const STACK_CAP: usize = rux_core::config::VM_WRITE_STRING_STACK_CAP;
        let bytes = s.as_bytes();
        if bytes.len() < STACK_CAP {
            let mut buf = [0u8; rux_core::config::VM_WRITE_STRING_STACK_CAP];
            buf[..bytes.len()].copy_from_slice(bytes);
            // buf[bytes.len()] is already 0 (null terminator).
            self.write_bytes(address, &buf[..bytes.len() + 1])
        } else {
            let mut vec = Vec::with_capacity(bytes.len() + 1);
            vec.extend_from_slice(bytes);
            vec.push(0);
            self.write_bytes(address, &vec)
        }
    }

    /// Read raw byte slice from target process memory at `address`.
    pub fn read_bytes(&self, address: u64, len: usize) -> Result<Vec<u8>> {
        if len == 0 {
            return Ok(Vec::new());
        }

        let mut buf = vec![0u8; len];
        let mut bytes_read: mach_vm_size_t = 0;

        unsafe {
            let kr = mach_vm_read_overwrite(
                self.task.port(),
                address,
                len as mach_vm_size_t,
                buf.as_mut_ptr() as mach_vm_address_t,
                &mut bytes_read,
            );

            if kr != KERN_SUCCESS {
                return Err(InjectError::VmWriteFailed {
                    kern_return: kr,
                    address,
                    size: len,
                    message: format!("read_overwrite failed: {}", mach_error_string(kr)),
                });
            }
        }

        buf.truncate(bytes_read as usize);
        Ok(buf)
    }

    /// Read a typed value from target process memory at `address`.
    ///
    /// Uses `MaybeUninit` so callers only need `Copy` (no `Default`), and
    /// large structs skip a wasted zeroing pass before the kernel overwrites them.
    pub fn read_val<T: Copy>(&self, address: u64) -> Result<T> {
        let size = mem::size_of::<T>();
        let mut val = mem::MaybeUninit::<T>::uninit();
        let mut bytes_read: mach_vm_size_t = 0;

        unsafe {
            let kr = mach_vm_read_overwrite(
                self.task.port(),
                address,
                size as mach_vm_size_t,
                val.as_mut_ptr() as mach_vm_address_t,
                &mut bytes_read,
            );

            if kr != KERN_SUCCESS || (bytes_read as usize) != size {
                return Err(InjectError::VmWriteFailed {
                    kern_return: kr,
                    address,
                    size,
                    message: format!("read_val failed: {}", mach_error_string(kr)),
                });
            }

            Ok(val.assume_init())
        }
    }

    /// Modify protection flags on a memory range in the target process.
    pub fn protect(&self, address: u64, size: usize, prot: VmProtection) -> Result<()> {
        if size == 0 {
            return Ok(());
        }

        unsafe {
            let kr = mach_vm_protect(
                self.task.port(),
                address,
                size as mach_vm_size_t,
                MACH_FALSE,
                prot.to_raw(),
            );

            if kr != KERN_SUCCESS {
                return Err(InjectError::VmProtectFailed {
                    kern_return: kr,
                    address,
                    message: mach_error_string(kr),
                });
            }
        }

        Ok(())
    }

    /// Deallocate a virtual memory block in the target task.
    pub fn deallocate(&self, address: u64, size: usize) -> Result<()> {
        if address == 0 || size == 0 {
            return Ok(());
        }

        unsafe {
            let kr = mach_vm_deallocate(self.task.port(), address, size as mach_vm_size_t);
            if kr != KERN_SUCCESS {
                return Err(InjectError::VmDeallocateFailed {
                    kern_return: kr,
                    address,
                    message: mach_error_string(kr),
                });
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_writer_alloc_write_read() {
        let task = MachTask::self_task();
        let writer = MemoryWriter::new(&task);

        let mut alloc = writer
            .allocate(4096, VmProtection::READ_WRITE)
            .expect("allocate failed");
        assert_ne!(alloc.address(), 0);

        let test_payload = b"Rux Mach-O Dynamic Library Injection Framework (Rust 2026)";
        writer
            .write_bytes(alloc.address(), test_payload)
            .expect("write_bytes failed");

        let read_back = writer
            .read_bytes(alloc.address(), test_payload.len())
            .expect("read_bytes failed");
        assert_eq!(&read_back[..], test_payload);

        // Test typed struct writing
        #[repr(C)]
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
        struct TestHeader {
            magic: u32,
            version: u16,
            flags: u16,
            target_addr: u64,
        }

        let header = TestHeader {
            magic: 0xDEADBEEF,
            version: 2,
            flags: 0x00FF,
            target_addr: 0x1000200030004000,
        };

        writer
            .write_val(alloc.address() + 128, &header)
            .expect("write_val failed");
        let read_header: TestHeader = writer
            .read_val(alloc.address() + 128)
            .expect("read_val failed");
        assert_eq!(read_header, header);

        // Change protection to READ
        alloc
            .protect(VmProtection::READ)
            .expect("protect to read failed");

        // Verify deallocation on drop or manual
        alloc.deallocate().expect("deallocate failed");
    }
}
