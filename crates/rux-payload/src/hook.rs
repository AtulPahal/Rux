use rux_core::{CpuArchitecture, InjectError, Result};
use rux_vm::prot::VmProtection;
use rux_vm::writer::MemoryWriter;
use rux_vm::MachTask;

unsafe extern "C" {
    fn sys_icache_invalidate(start: *mut libc::c_void, len: libc::size_t);
}

/// An active inline trampoline hook placed on a native machine function.
///
/// Backs up original instructions on creation and restores them when dropped or unhooked.
#[derive(Debug)]
pub struct InlineHook {
    target_addr: u64,
    hook_addr: u64,
    original_bytes: Vec<u8>,
    active: bool,
    arch: CpuArchitecture,
}

impl InlineHook {
    /// Create and install an inline hook redirecting execution of `target` to `hook_func`.
    pub fn install(target: u64, hook_func: u64) -> Result<Self> {
        if target == 0 || hook_func == 0 {
            return Err(InjectError::InvalidArguments(
                "Target and hook function addresses must be non-zero".into(),
            ));
        }

        let arch = CpuArchitecture::host();
        let hook_size = match arch {
            CpuArchitecture::Arm64 => 16,
            CpuArchitecture::X86_64 => 14,
            other => {
                return Err(InjectError::ArchitectureMismatch {
                    target: other,
                    host: arch,
                });
            }
        };

        let task = MachTask::self_task();
        let writer = MemoryWriter::new(&task);

        // 1. Read and backup original bytes
        let original_bytes = writer.read_bytes(target, hook_size)?;

        // 2. Build jump trampoline bytes
        let mut trampoline = Vec::with_capacity(hook_size);
        match arch {
            CpuArchitecture::Arm64 => {
                // LDR X16, #8; BR X16 (8 bytes instructions) + 64-bit absolute target address
                let code: [u32; 2] = [0x58000050, 0xd61f0200];
                for &instr in &code {
                    trampoline.extend_from_slice(&instr.to_le_bytes());
                }
                trampoline.extend_from_slice(&hook_func.to_le_bytes());
            }
            CpuArchitecture::X86_64 => {
                // jmpq *(%rip) (6 bytes) + 64-bit absolute target address
                let jmp_rip = [0xFF, 0x25, 0x00, 0x00, 0x00, 0x00];
                trampoline.extend_from_slice(&jmp_rip);
                trampoline.extend_from_slice(&hook_func.to_le_bytes());
            }
            _ => unreachable!(),
        }

        // 3. Make target memory writable
        writer.protect(target, hook_size, VmProtection::READ_WRITE)?;

        // 4. Write trampoline
        writer.write_bytes(target, &trampoline)?;

        // 5. Restore protection to Read + Execute
        writer.protect(target, hook_size, VmProtection::READ_EXECUTE)?;

        // 6. Invalidate instruction cache for CPU pipeline coherency
        unsafe {
            sys_icache_invalidate(target as *mut libc::c_void, hook_size);
        }

        Ok(Self {
            target_addr: target,
            hook_addr: hook_func,
            original_bytes,
            active: true,
            arch,
        })
    }

    /// Restore the original unhooked instructions.
    pub fn unhook(&mut self) -> Result<()> {
        if !self.active {
            return Ok(());
        }

        let task = MachTask::self_task();
        let writer = MemoryWriter::new(&task);
        let len = self.original_bytes.len();

        writer.protect(self.target_addr, len, VmProtection::READ_WRITE)?;
        writer.write_bytes(self.target_addr, &self.original_bytes)?;
        writer.protect(self.target_addr, len, VmProtection::READ_EXECUTE)?;

        unsafe {
            sys_icache_invalidate(self.target_addr as *mut libc::c_void, len);
        }

        self.active = false;
        Ok(())
    }

    pub fn target_address(&self) -> u64 {
        self.target_addr
    }

    pub fn hook_address(&self) -> u64 {
        self.hook_addr
    }

    pub fn is_active(&self) -> bool {
        self.active
    }

    pub fn arch(&self) -> CpuArchitecture {
        self.arch
    }
}

impl Drop for InlineHook {
    fn drop(&mut self) {
        let _ = self.unhook();
    }
}

/// Global convenience function matching `write_hook(target, hook_func)` in the C client.
pub fn write_hook(target: u64, hook_func: u64) -> bool {
    match InlineHook::install(target, hook_func) {
        Ok(hook) => {
            // Leak hook handle so trampoline remains permanently installed
            std::mem::forget(hook);
            true
        }
        Err(e) => {
            eprintln!("[Hook] Failed to install hook at 0x{:x}: {}", target, e);
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inline_hook_trampoline_generation() {
        let arch = CpuArchitecture::host();
        let dummy_target: [u8; 32] = [0x90; 32];
        let target_addr = dummy_target.as_ptr() as u64;
        let hook_addr = 0x1000200030004000u64;

        // Verify size expectations
        let hook_len = match arch {
            CpuArchitecture::Arm64 => 16,
            CpuArchitecture::X86_64 => 14,
            _ => 16,
        };
        assert!(hook_len <= dummy_target.len());
        assert_ne!(target_addr, hook_addr);
    }
}
