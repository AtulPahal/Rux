use crate::stubs::{InjectParams, ARM64_STUB, CODE_ALLOC_SIZE, STACK_SIZE, X86_64_STUB};
use crate::thread::{create_remote_thread, resolve_system_symbols};
use mach2::traps::mach_task_self;
use rux_core::{CpuArchitecture, InjectError, InjectionOptions, InjectionResult, Result};
use rux_proc::scanner::{find_by_name, get_process_cputype, get_process_name, is_process_alive};
use rux_vm::prot::VmProtection;
use rux_vm::sys::mach_port_deallocate;
use rux_vm::task::MachTask;
use rux_vm::writer::MemoryWriter;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

/// Inject a dynamic library into a target process specified by process name.
pub fn inject_name(
    process_name: &str,
    dylib_path: impl AsRef<Path>,
    options: &InjectionOptions,
) -> Result<InjectionResult> {
    if process_name.is_empty() {
        return Err(InjectError::InvalidArguments("Empty process name".into()));
    }

    let target = find_by_name(process_name)?
        .ok_or_else(|| InjectError::ProcessNotFound(process_name.to_string()))?;

    if options.verbose {
        println!(
            "[MachInject] Found process '{}' with PID {}",
            target.name, target.pid
        );
    }

    inject_pid(target.pid, dylib_path, options)
}

/// Inject a dynamic library into a target process specified by PID.
pub fn inject_pid(
    pid: i32,
    dylib_path: impl AsRef<Path>,
    options: &InjectionOptions,
) -> Result<InjectionResult> {
    let start_time = Instant::now();

    // 1. Argument and target validation
    let resolved_path = validate_target(pid, dylib_path.as_ref(), options.verbose)?;

    // 2. Architecture compatibility check
    let host_arch = CpuArchitecture::host();
    if let Ok(target_arch) = get_process_cputype(pid) {
        if target_arch != host_arch {
            if options.verbose {
                eprintln!(
                    "[MachInject] Error: Architecture mismatch: target is {}, injector is {}.",
                    target_arch, host_arch
                );
            }
            return Err(InjectError::ArchitectureMismatch {
                target: target_arch,
                host: host_arch,
            });
        }
    }

    // 3. Acquire remote task port
    let task = MachTask::for_pid(pid)?;
    let writer = MemoryWriter::new(&task);

    if options.verbose {
        let name = get_process_name(pid).unwrap_or_else(|_| "unknown".into());
        println!(
            "[MachInject] Attached to process '{}' (PID {}), task port: {}",
            name,
            pid,
            task.port()
        );
    }

    // 4. Resolve system symbols from shared cache
    let symbols = resolve_system_symbols()?;
    if options.verbose {
        println!(
            "[MachInject] Resolved symbols: dlopen=0x{:x}, pthread_set_self=0x{:x}, pthread_exit=0x{:x}",
            symbols.dlopen_addr, symbols.pthread_set_self_addr, symbols.pthread_exit_addr
        );
    }

    // 5. Allocate remote memory (Stack, Params, Code)
    let stack_alloc = writer.allocate(STACK_SIZE, VmProtection::READ_WRITE)?;
    let params_alloc = writer.allocate(
        std::mem::size_of::<InjectParams>(),
        VmProtection::READ_WRITE,
    )?;
    let mut code_alloc = writer.allocate(CODE_ALLOC_SIZE, VmProtection::READ_WRITE)?;

    // 6. Prepare parameter block
    let params = InjectParams::new(
        resolved_path
            .to_str()
            .ok_or_else(|| InjectError::InvalidArguments("Invalid UTF-8 in dylib path".into()))?,
        options.dlopen_mode.to_raw(),
        symbols.dlopen_addr,
        symbols.pthread_set_self_addr,
        symbols.pthread_exit_addr,
    );

    // 7. Select position-independent machine code stub
    let stub_bytes = match host_arch {
        CpuArchitecture::Arm64 => ARM64_STUB,
        CpuArchitecture::X86_64 => X86_64_STUB,
        other => {
            return Err(InjectError::ArchitectureMismatch {
                target: other,
                host: host_arch,
            });
        }
    };

    // 8. Write parameters and stub into target address space
    writer.write_val(params_alloc.address(), &params)?;
    writer.write_bytes(code_alloc.address(), stub_bytes)?;

    // 9. Enforce W^X memory protection (Code is Read+Execute)
    code_alloc.protect(VmProtection::READ_EXECUTE)?;

    // 10. Compute aligned stack top and launch remote thread
    let stack_top = stack_alloc.address() + ((STACK_SIZE / 2) as u64);
    let remote_thread = create_remote_thread(
        &task,
        host_arch,
        code_alloc.address(),
        stack_top,
        params_alloc.address(),
    )?;

    if options.verbose {
        println!(
            "[MachInject] Remote thread {} launched (PC: 0x{:x}, SP: 0x{:x})",
            remote_thread,
            code_alloc.address(),
            stack_top
        );
    }

    // 11. Wait for remote dlopen confirmation if requested
    let mut result = InjectionResult {
        remote_handle: 0,
        status: 0,
        elapsed: start_time.elapsed(),
    };

    if options.wait_completion {
        let poll_interval = Duration::from_millis(rux_core::config::INJECT_POLL_INTERVAL_MS);
        let mut completed = false;

        while start_time.elapsed() < options.timeout {
            thread::sleep(poll_interval);

            if let Ok(current_params) = writer.read_val::<InjectParams>(params_alloc.address()) {
                if current_params.status != 0 {
                    completed = true;
                    result.remote_handle = current_params.dlopen_result;
                    result.status = current_params.status;
                    result.elapsed = start_time.elapsed();

                    if current_params.status == 1 && current_params.dlopen_result != 0 {
                        if options.verbose {
                            println!(
                                "[MachInject] Injection confirmed! Remote dlopen() handle: 0x{:x}",
                                current_params.dlopen_result
                            );
                        }
                    } else {
                        if options.verbose {
                            eprintln!(
                                "[MachInject] Error: Remote dlopen() returned NULL (failed to load library)."
                            );
                            eprintln!(
                                "[MachInject] Check library code signature, entitlements, and dependencies."
                            );
                        }
                        // Safely terminate remote thread before memory is deallocated
                        let _ = crate::thread::terminate_remote_thread(remote_thread);
                        unsafe {
                            mach_port_deallocate(mach_task_self(), remote_thread);
                        }
                        return Err(InjectError::DlopenFailed);
                    }
                    break;
                }
            }
        }

        if !completed {
            if options.verbose {
                eprintln!(
                    "[MachInject] Warning: Timeout waiting for remote thread completion after {:?}",
                    options.timeout
                );
            }
            // Terminate remote thread before deallocating memory to prevent crashing target process
            let _ = crate::thread::terminate_remote_thread(remote_thread);
            unsafe {
                mach_port_deallocate(mach_task_self(), remote_thread);
            }
            return Err(InjectError::Timeout {
                timeout_ms: options.timeout.as_millis() as u64,
            });
        }

        // Allow remote thread to cleanly finish pthread_exit before deallocating memory
        thread::sleep(Duration::from_millis(
            rux_core::config::INJECT_SETTLE_DELAY_MS,
        ));

        // Clean up remote memory allocations
        let _ = code_alloc.deallocate();
        let _ = params_alloc.deallocate();
        let _ = stack_alloc.deallocate();
    } else {
        // Detach allocations so remote thread can execute asynchronously
        stack_alloc.leak();
        params_alloc.leak();
        code_alloc.leak();
        result.status = 1;
    }

    // Release thread port
    unsafe {
        mach_port_deallocate(mach_task_self(), remote_thread);
    }

    result.elapsed = start_time.elapsed();
    Ok(result)
}

/// Validate process liveness and dynamic library accessibility.
fn validate_target(pid: i32, dylib_path: &Path, verbose: bool) -> Result<PathBuf> {
    if pid <= 0 {
        return Err(InjectError::InvalidArguments(format!(
            "Invalid PID: {}",
            pid
        )));
    }

    // Resolve canonical absolute path
    let canonical = dylib_path.canonicalize().map_err(|e| {
        if verbose {
            eprintln!(
                "[MachInject] Error: Failed to resolve path '{}': {}",
                dylib_path.display(),
                e
            );
        }
        InjectError::FileNotFound(dylib_path.to_path_buf())
    })?;

    if !canonical.exists() || !canonical.is_file() {
        if verbose {
            eprintln!(
                "[MachInject] Error: Dynamic library file does not exist at '{}'",
                canonical.display()
            );
        }
        return Err(InjectError::FileNotFound(canonical));
    }

    // Check target process liveness
    if !is_process_alive(pid) {
        if verbose {
            eprintln!("[MachInject] Error: Target process {} is not running.", pid);
        }
        return Err(InjectError::ProcessNotFound(format!("PID {}", pid)));
    }

    Ok(canonical)
}
