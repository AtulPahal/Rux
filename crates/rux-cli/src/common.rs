use rux_core::{CpuArchitecture, DlopenMode, InjectionOptions, InjectionResult};
use std::path::PathBuf;
use std::time::Duration;

pub use rux_core::config::{
    DEFAULT_INJECTION_TIMEOUT_MS as DEFAULT_TIMEOUT_MS,
    DEFAULT_TARGET_PROCESS_NAME as DEFAULT_PROCESS_NAME,
};

/// Dynamically determine the default target process name.
pub fn get_default_process_name() -> String {
    use rux_core::config as cfg;
    std::env::var(cfg::ENV_DEFAULT_TARGET_NAME)
        .or_else(|_| std::env::var(cfg::ENV_TARGET_PROCESS))
        .unwrap_or_else(|_| DEFAULT_PROCESS_NAME.to_string())
}

/// Dynamically determine the default timeout in milliseconds.
pub fn get_default_timeout_ms() -> u64 {
    use rux_core::config as cfg;
    std::env::var(cfg::ENV_DEFAULT_TIMEOUT_MS)
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(DEFAULT_TIMEOUT_MS)
}

#[derive(Debug, Clone)]
pub struct CliOptions {
    pub pid: Option<i32>,
    pub name: Option<String>,
    pub dylib_path: Option<PathBuf>,
    pub mode: DlopenMode,
    pub timeout_ms: u64,
    pub no_wait: bool,
    #[allow(dead_code)]
    pub list: bool,
    pub verbose: bool,
    #[allow(dead_code)]
    pub test: bool,
}

impl Default for CliOptions {
    fn default() -> Self {
        Self {
            pid: None,
            name: Some(get_default_process_name()),
            dylib_path: None,
            mode: DlopenMode::Now,
            timeout_ms: get_default_timeout_ms(),
            no_wait: false,
            list: false,
            verbose: false,
            test: false,
        }
    }
}

/// Print formatted list of processes matching a query.
pub fn list_matching_processes(query: &str) {
    println!(
        "[Process Scanner] Searching for processes matching '{}'...",
        query
    );
    match rux_proc::find_all_by_name(query) {
        Ok(procs) if procs.is_empty() => {
            println!("No running processes found matching '{}'.", query);
        }
        Ok(procs) => {
            println!("Found {} process(es) matching '{}':", procs.len(), query);
            for p in procs {
                let path_str = p
                    .path
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| "<unknown>".to_string());
                println!(
                    "  - PID: {:<6} Name: {:<20} Arch: {:<8} Path: {}",
                    p.pid, p.name, p.cputype, path_str
                );
            }
        }
        Err(e) => {
            eprintln!("Error scanning processes: {}", e);
        }
    }
}

/// Run full automated diagnostic and regression test suite.
#[allow(dead_code)]
pub fn run_diagnostic_tests(verbose: bool) -> i32 {
    println!("=== Rux Darwin Mach-O Test Suite ===");
    let mut passed = 0;
    let mut failed = 0;

    // Test 1: Host architecture detection
    print!("[TEST 1/5] Host Architecture Detection... ");
    let host_arch = CpuArchitecture::host();
    if host_arch.is_supported_64bit() {
        println!("PASS ({})", host_arch);
        passed += 1;
    } else {
        println!("FAIL (Unsupported: {})", host_arch);
        failed += 1;
    }

    // Test 2: Process enumeration
    print!("[TEST 2/5] Darwin Process Enumeration (libproc)... ");
    match rux_proc::list_pids() {
        Ok(pids) if !pids.is_empty() => {
            println!("PASS ({} active processes)", pids.len());
            passed += 1;
        }
        Ok(_) => {
            println!("FAIL (0 processes returned)");
            failed += 1;
        }
        Err(e) => {
            println!("FAIL ({})", e);
            failed += 1;
        }
    }

    // Test 3: Self-process inspection
    print!("[TEST 3/5] Process Inspection & Path Resolution... ");
    let my_pid = std::process::id() as i32;
    match rux_proc::find_by_pid(my_pid) {
        Ok(Some(info)) => {
            if verbose {
                println!();
                println!("          PID:  {}", info.pid);
                println!("          Name: {}", info.name);
                println!("          Arch: {}", info.cputype);
                println!("          Path: {:?}", info.path);
                print!("          Result: ");
            }
            println!("PASS ({})", info.name);
            passed += 1;
        }
        Ok(None) => {
            println!("FAIL (Current process not found)");
            failed += 1;
        }
        Err(e) => {
            println!("FAIL ({})", e);
            failed += 1;
        }
    }

    // Test 4: Virtual Memory allocation and write
    print!("[TEST 4/5] Mach Virtual Memory Writer & Allocation... ");
    let task = rux_vm::MachTask::self_task();
    let writer = rux_vm::MemoryWriter::new(&task);
    match writer.allocate(
        rux_core::config::DIAGNOSTIC_TEST_ALLOC_BYTES,
        rux_vm::VmProtection::READ_WRITE,
    ) {
        Ok(alloc) => {
            let payload = b"Rux Injector Diagnostic Payload 2026";
            if let Err(e) = writer.write_bytes(alloc.address(), payload) {
                println!("FAIL (write_bytes: {})", e);
                failed += 1;
            } else {
                match writer.read_bytes(alloc.address(), payload.len()) {
                    Ok(read_back) if read_back == payload => {
                        let _ = alloc.deallocate();
                        println!("PASS (Allocated 4KB, wrote & verified payload)");
                        passed += 1;
                    }
                    Ok(_) => {
                        println!("FAIL (Payload read mismatch)");
                        failed += 1;
                    }
                    Err(e) => {
                        println!("FAIL (read_bytes: {})", e);
                        failed += 1;
                    }
                }
            }
        }
        Err(e) => {
            println!("FAIL (allocate: {})", e);
            failed += 1;
        }
    }

    // Test 5: System symbols resolution
    print!("[TEST 5/5] Darwin Shared Cache Symbol Resolution... ");
    match rux_inject::resolve_system_symbols() {
        Ok(syms) => {
            if verbose {
                println!();
                println!("          dlopen:            0x{:x}", syms.dlopen_addr);
                println!(
                    "          _pthread_set_self: 0x{:x}",
                    syms.pthread_set_self_addr
                );
                println!(
                    "          pthread_exit:      0x{:x}",
                    syms.pthread_exit_addr
                );
                print!("          Result: ");
            }
            println!("PASS");
            passed += 1;
        }
        Err(e) => {
            println!("FAIL ({})", e);
            failed += 1;
        }
    }

    println!("=========================================");
    println!("Diagnostic Results: {} passed, {} failed.", passed, failed);

    if failed > 0 {
        1
    } else {
        0
    }
}

/// Execute dynamic library injection with given options.
pub fn execute_injection(opts: CliOptions) -> i32 {
    let dylib = match &opts.dylib_path {
        Some(path) => path,
        None => {
            eprintln!("Error: Dynamic library path is required.");
            return 1;
        }
    };

    let injection_opts = InjectionOptions {
        verbose: opts.verbose,
        wait_completion: !opts.no_wait,
        timeout: Duration::from_millis(opts.timeout_ms),
        dlopen_mode: opts.mode,
    };

    println!("[MachInject] Preparing dynamic library injection...");
    println!("  Target Library: {}", dylib.display());

    let result: Result<InjectionResult, rux_core::InjectError> = if let Some(pid) = opts.pid {
        println!("  Target Mode:    PID {}", pid);
        rux_inject::inject_pid(pid, dylib, &injection_opts)
    } else {
        let name = opts.name.as_deref().unwrap_or(DEFAULT_PROCESS_NAME);
        println!("  Target Mode:    Process Name '{}'", name);
        rux_inject::inject_name(name, dylib, &injection_opts)
    };

    match result {
        Ok(res) => {
            println!("\n[+] Injection Succeeded!");
            if res.remote_handle != 0 {
                println!("    Remote Module Handle: 0x{:x}", res.remote_handle);
            }
            println!("    Elapsed Time:         {:.2?}", res.elapsed);
            0
        }
        Err(err) => {
            eprintln!("\n[-] Injection Failed: {}", err);
            match &err {
                rux_core::InjectError::TaskForPidFailed { is_root: false, .. } => {
                    eprintln!("\n[!] Root privileges are required to attach to other processes.");
                    eprintln!("    Please re-run your command with sudo:");
                    if let Some(pid) = opts.pid {
                        eprintln!("    sudo rux inject {} -p {}", dylib.display(), pid);
                    } else {
                        let name = opts.name.as_deref().unwrap_or(DEFAULT_PROCESS_NAME);
                        eprintln!("    sudo rux inject {} -n {}", dylib.display(), name);
                    }
                }
                rux_core::InjectError::TaskForPidFailed { is_root: true, .. } => {
                    eprintln!("\n[!] task_for_pid was denied even with root privileges.");
                    eprintln!("    The target is likely Hardened Runtime without get-task-allow");
                    eprintln!(
                        "    (e.g. {}) with SIP debugging restrictions enabled,",
                        rux_core::config::DEFAULT_TARGET_PROCESS_NAME
                    );
                    eprintln!("    so the kernel refuses the task port regardless of sudo.");
                    eprintln!("    Options: inject a non-hardened test process, or reboot into");
                    eprintln!("    Recovery OS and run `csrutil enable --without debug`, then retry with sudo.");
                }
                _ => {}
            }
            1
        }
    }
}
