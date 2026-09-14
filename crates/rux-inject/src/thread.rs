use mach2::kern_return::KERN_SUCCESS;
use mach2::message::mach_msg_type_number_t;
use mach2::port::mach_port_t;
use rux_core::{mach_error_string, CpuArchitecture, InjectError, Result};
use rux_vm::sys::thread_create_running;
use rux_vm::MachTask;
use std::ffi::CString;
use std::mem;

pub const ARM_THREAD_STATE64: libc::c_int = 6;
pub const ARM_THREAD_STATE64_COUNT: mach_msg_type_number_t = 68;

#[repr(C, align(8))]
#[derive(Debug, Clone, Copy)]
pub struct arm_thread_state64_t {
    pub __x: [u64; 29],
    pub __fp: u64,
    pub __lr: u64,
    pub __sp: u64,
    pub __pc: u64,
    pub __cpsr: u32,
    pub __flags: u32,
}

impl Default for arm_thread_state64_t {
    fn default() -> Self {
        unsafe { mem::zeroed() }
    }
}

pub const X86_THREAD_STATE64: libc::c_int = 4;
pub const X86_THREAD_STATE64_COUNT: mach_msg_type_number_t = 42;

#[repr(C, align(8))]
#[derive(Debug, Clone, Copy)]
pub struct x86_thread_state64_t {
    pub __rax: u64,
    pub __rbx: u64,
    pub __rcx: u64,
    pub __rdx: u64,
    pub __rdi: u64,
    pub __rsi: u64,
    pub __rbp: u64,
    pub __rsp: u64,
    pub __r8: u64,
    pub __r9: u64,
    pub __r10: u64,
    pub __r11: u64,
    pub __r12: u64,
    pub __r13: u64,
    pub __r14: u64,
    pub __r15: u64,
    pub __rip: u64,
    pub __rflags: u64,
    pub __cs: u64,
    pub __fs: u64,
    pub __gs: u64,
}

impl Default for x86_thread_state64_t {
    fn default() -> Self {
        unsafe { mem::zeroed() }
    }
}

/// Resolved system symbol addresses in the Darwin dyld shared cache.
#[derive(Debug, Clone, Copy)]
pub struct SystemSymbols {
    pub dlopen_addr: u64,
    pub pthread_set_self_addr: u64,
    pub pthread_exit_addr: u64,
}

/// Resolve required injection function symbols from the shared cache.
pub fn resolve_system_symbols() -> Result<SystemSymbols> {
    unsafe {
        let dlopen_sym = CString::new("dlopen").unwrap();
        let psetself_sym = CString::new("_pthread_set_self").unwrap();
        let pexit_sym = CString::new("pthread_exit").unwrap();

        let mut dlopen_addr = libc::dlsym(libc::RTLD_DEFAULT, dlopen_sym.as_ptr()) as u64;
        let psetself_addr = libc::dlsym(libc::RTLD_DEFAULT, psetself_sym.as_ptr()) as u64;
        let mut pexit_addr = libc::dlsym(libc::RTLD_DEFAULT, pexit_sym.as_ptr()) as u64;

        if dlopen_addr == 0 {
            dlopen_addr = libc::dlopen as *const () as usize as u64;
        }
        if pexit_addr == 0 {
            pexit_addr = libc::pthread_exit as *const () as usize as u64;
        }

        if dlopen_addr == 0 {
            return Err(InjectError::NoSymbols(
                "Could not resolve dlopen address".into(),
            ));
        }

        Ok(SystemSymbols {
            dlopen_addr,
            pthread_set_self_addr: psetself_addr,
            pthread_exit_addr: pexit_addr,
        })
    }
}

/// Create and launch a remote thread inside the target task.
pub fn create_remote_thread(
    task: &MachTask,
    arch: CpuArchitecture,
    entry_pc: u64,
    stack_top: u64,
    param_addr: u64,
) -> Result<mach_port_t> {
    let mut thread_port: mach_port_t = 0;

    // Stack alignment: Darwin ABI requires 16-byte alignment
    let aligned_sp = stack_top & !0xF;

    unsafe {
        match arch {
            CpuArchitecture::Arm64 => {
                let mut x_regs = [0u64; 29];
                x_regs[0] = param_addr;
                let state = arm_thread_state64_t {
                    __x: x_regs,
                    __sp: aligned_sp,
                    __pc: entry_pc,
                    ..Default::default()
                };

                let kr = thread_create_running(
                    task.port(),
                    ARM_THREAD_STATE64,
                    &state as *const _ as *const libc::c_void,
                    ARM_THREAD_STATE64_COUNT,
                    &mut thread_port,
                );

                if kr != KERN_SUCCESS || thread_port == 0 {
                    return Err(InjectError::ThreadCreateFailed {
                        kern_return: kr,
                        message: mach_error_string(kr),
                    });
                }
            }
            CpuArchitecture::X86_64 => {
                let state = x86_thread_state64_t {
                    __rdi: param_addr,
                    __rsp: aligned_sp,
                    __rbp: aligned_sp,
                    __rip: entry_pc,
                    ..Default::default()
                };

                let kr = thread_create_running(
                    task.port(),
                    X86_THREAD_STATE64,
                    &state as *const _ as *const libc::c_void,
                    X86_THREAD_STATE64_COUNT,
                    &mut thread_port,
                );

                if kr != KERN_SUCCESS || thread_port == 0 {
                    return Err(InjectError::ThreadCreateFailed {
                        kern_return: kr,
                        message: mach_error_string(kr),
                    });
                }
            }
            other => {
                return Err(InjectError::ArchitectureMismatch {
                    target: other,
                    host: CpuArchitecture::host(),
                });
            }
        }
    }

    Ok(thread_port)
}

/// Terminate a remote Mach thread to safely abort execution.
pub fn terminate_remote_thread(thread_port: mach_port_t) -> Result<()> {
    if thread_port == 0 {
        return Ok(());
    }
    unsafe {
        let kr = rux_vm::sys::thread_terminate(thread_port);
        if kr != KERN_SUCCESS {
            return Err(InjectError::ThreadCreateFailed {
                kern_return: kr,
                message: mach_error_string(kr),
            });
        }
    }
    Ok(())
}
