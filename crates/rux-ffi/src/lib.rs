#![allow(clippy::missing_safety_doc)]
//! Rux C-ABI Foreign Function Interface (FFI)
//!
//! Provides binary- and source-compatible C declarations matching `mach_inject.h`
//! and `proc_utils.h` for seamless integration into C/C++ tooling.

use libc::{c_char, c_int, pid_t, size_t};
use rux_core::{CpuArchitecture, DlopenMode, InjectionOptions};
use std::ffi::{CStr, CString};
use std::path::Path;
use std::time::Duration;

/// C-compatible representation of `mach_inject_options_t`.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct mach_inject_options_t {
    pub verbose: bool,
    pub wait_completion: bool,
    pub timeout_ms: libc::c_uint,
    pub dlopen_mode: libc::c_int,
}

/// C-compatible representation of `mach_inject_result_t`.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct mach_inject_result_t {
    pub remote_handle: u64,
    pub status: i32,
}

/// Populate an options struct with safe defaults.
#[no_mangle]
pub unsafe extern "C" fn mach_inject_default_options(opts: *mut mach_inject_options_t) {
    if opts.is_null() {
        return;
    }
    unsafe {
        (*opts).verbose = false;
        (*opts).wait_completion = true;
        (*opts).timeout_ms = rux_core::config::DEFAULT_INJECTION_TIMEOUT_MS as libc::c_uint;
        (*opts).dlopen_mode = libc::RTLD_NOW;
    }
}

unsafe fn parse_options(options: *const mach_inject_options_t) -> InjectionOptions {
    if options.is_null() {
        InjectionOptions::default()
    } else {
        let opts = unsafe { &*options };
        let mode = if opts.dlopen_mode == libc::RTLD_LAZY {
            DlopenMode::Lazy
        } else {
            DlopenMode::Now
        };
        InjectionOptions {
            verbose: opts.verbose,
            wait_completion: opts.wait_completion,
            timeout: Duration::from_millis(opts.timeout_ms as u64),
            dlopen_mode: mode,
        }
    }
}

/// Inject a dynamic library into a target process by PID.
#[no_mangle]
pub unsafe extern "C" fn mach_inject_pid(
    pid: pid_t,
    dylib_path: *const c_char,
    options: *const mach_inject_options_t,
) -> c_int {
    mach_inject_pid_ext(pid, dylib_path, options, std::ptr::null_mut())
}

/// Extended injection API returning remote dlopen handle and execution result.
#[no_mangle]
pub unsafe extern "C" fn mach_inject_pid_ext(
    pid: pid_t,
    dylib_path: *const c_char,
    options: *const mach_inject_options_t,
    out_result: *mut mach_inject_result_t,
) -> c_int {
    if dylib_path.is_null() || pid <= 0 {
        return -1; // MACH_INJECT_ERR_INVALID_ARG
    }

    let path_str = match unsafe { CStr::from_ptr(dylib_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let opts = unsafe { parse_options(options) };

    match rux_inject::inject_pid(pid, Path::new(path_str), &opts) {
        Ok(result) => {
            if !out_result.is_null() {
                unsafe {
                    (*out_result).remote_handle = result.remote_handle;
                    (*out_result).status = result.status;
                }
            }
            0 // MACH_INJECT_SUCCESS
        }
        Err(err) => err.to_c_error_code(),
    }
}

/// Inject a dynamic library into the first running process matching name.
#[no_mangle]
pub unsafe extern "C" fn mach_inject_name(
    process_name: *const c_char,
    dylib_path: *const c_char,
    options: *const mach_inject_options_t,
) -> c_int {
    if process_name.is_null() || dylib_path.is_null() {
        return -1;
    }

    let name_str = match unsafe { CStr::from_ptr(process_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let path_str = match unsafe { CStr::from_ptr(dylib_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let opts = unsafe { parse_options(options) };

    match rux_inject::inject_name(name_str, Path::new(path_str), &opts) {
        Ok(_) => 0,
        Err(err) => err.to_c_error_code(),
    }
}

/// Return human-readable description for a MACH_INJECT_ERR_* code.
#[no_mangle]
pub extern "C" fn mach_inject_strerror(err_code: c_int) -> *const c_char {
    let msg: &'static str = match err_code {
        0 => "Success\0",
        -1 => "Invalid arguments provided\0",
        -2 => "Dylib file not found or inaccessible\0",
        -3 => "Target process not found or not running\0",
        -4 => "Failed to obtain Mach task port (task_for_pid failed; root privileges required)\0",
        -5 => "Target process CPU architecture does not match injector\0",
        -6 => "Failed to allocate memory in target process\0",
        -7 => "Failed to write payload memory to target process\0",
        -8 => "Failed to set memory page protections in target process\0",
        -9 => "Failed to create remote thread in target process\0",
        -10 => "Remote dlopen() returned NULL (library failed to load in target process)\0",
        -11 => "Timed out waiting for remote thread completion\0",
        -12 => "Failed to resolve required system symbols (dlopen, pthread_set_self)\0",
        -13 => "Failed to clean up remote resources\0",
        _ => "Unknown error\0",
    };
    msg.as_ptr() as *const c_char
}

// -------------------------------------------------------------------------
// Process Utilities C FFI Implementation
// -------------------------------------------------------------------------

/// Find the first running process matching process_name. Returns PID or 0 if not found.
#[no_mangle]
pub unsafe extern "C" fn proc_find_by_name(process_name: *const c_char) -> pid_t {
    if process_name.is_null() {
        return 0;
    }
    let name_str = match unsafe { CStr::from_ptr(process_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    match rux_proc::find_by_name(name_str) {
        Ok(Some(info)) => info.pid,
        _ => 0,
    }
}

/// Find all running processes matching process_name.
#[no_mangle]
pub unsafe extern "C" fn proc_find_all_by_name(
    process_name: *const c_char,
    out_pids: *mut pid_t,
    max_pids: size_t,
) -> c_int {
    if process_name.is_null() || out_pids.is_null() || max_pids == 0 {
        return 0;
    }

    let name_str = match unsafe { CStr::from_ptr(process_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let procs = match rux_proc::find_all_by_name(name_str) {
        Ok(list) => list,
        Err(_) => return 0,
    };

    let count = procs.len().min(max_pids);
    for (i, proc) in procs.iter().take(count).enumerate() {
        unsafe {
            *out_pids.add(i) = proc.pid;
        }
    }

    count as c_int
}

/// Retrieve process name for a given PID.
#[no_mangle]
pub unsafe extern "C" fn proc_get_name(pid: pid_t, out_name: *mut c_char, max_len: size_t) -> bool {
    if out_name.is_null() || max_len == 0 || pid <= 0 {
        return false;
    }

    match rux_proc::get_process_name(pid) {
        Ok(name) => {
            if let Ok(c_str) = CString::new(name) {
                let bytes = c_str.as_bytes_with_nul();
                let copy_len = bytes.len().min(max_len);
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        bytes.as_ptr() as *const c_char,
                        out_name,
                        copy_len,
                    );
                    *out_name.add(copy_len - 1) = 0;
                }
                return true;
            }
            false
        }
        Err(_) => false,
    }
}

/// Retrieve full executable path for a given PID.
#[no_mangle]
pub unsafe extern "C" fn proc_get_path(pid: pid_t, out_path: *mut c_char, max_len: size_t) -> bool {
    if out_path.is_null() || max_len == 0 || pid <= 0 {
        return false;
    }

    match rux_proc::get_process_path(pid) {
        Ok(path) => {
            if let Some(path_str) = path.to_str() {
                if let Ok(c_str) = CString::new(path_str) {
                    let bytes = c_str.as_bytes_with_nul();
                    let copy_len = bytes.len().min(max_len);
                    unsafe {
                        std::ptr::copy_nonoverlapping(
                            bytes.as_ptr() as *const c_char,
                            out_path,
                            copy_len,
                        );
                        *out_path.add(copy_len - 1) = 0;
                    }
                    return true;
                }
            }
            false
        }
        Err(_) => false,
    }
}

/// Check if a process is alive.
#[no_mangle]
pub extern "C" fn proc_is_alive(pid: pid_t) -> bool {
    rux_proc::is_process_alive(pid)
}

/// Query CPU architecture of a process. Returns 0 on success, -1 on failure.
#[no_mangle]
pub unsafe extern "C" fn proc_get_cputype(pid: pid_t, out_cputype: *mut libc::c_int) -> c_int {
    if out_cputype.is_null() || pid <= 0 {
        return -1;
    }

    match rux_proc::get_process_cputype(pid) {
        Ok(arch) => {
            unsafe {
                *out_cputype = arch.to_raw();
            }
            0
        }
        Err(_) => -1,
    }
}

/// Convert `cpu_type_t` to human-readable string.
#[no_mangle]
pub extern "C" fn proc_cputype_to_string(cputype: libc::c_int) -> *const c_char {
    let arch = CpuArchitecture::from_raw(cputype);
    let s: &'static str = match arch {
        CpuArchitecture::Arm64 => "arm64\0",
        CpuArchitecture::X86_64 => "x86_64\0",
        CpuArchitecture::Arm32 => "arm\0",
        CpuArchitecture::X86_32 => "x86\0",
        CpuArchitecture::Unknown(_) => "unknown\0",
    };
    s.as_ptr() as *const c_char
}

/// Native host CPU architecture.
#[no_mangle]
pub extern "C" fn proc_host_cputype() -> libc::c_int {
    CpuArchitecture::host().to_raw()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proc_find_self_ffi() {
        let my_pid = std::process::id() as pid_t;
        let mut name_buf = [0i8; 256];
        let ok = unsafe { proc_get_name(my_pid, name_buf.as_mut_ptr(), name_buf.len()) };
        assert!(ok);

        let pid_found = unsafe { proc_find_by_name(name_buf.as_ptr()) };
        assert_eq!(pid_found, my_pid);
    }

    #[test]
    fn test_mach_inject_default_options_ffi() {
        let mut opts = mach_inject_options_t {
            verbose: true,
            wait_completion: false,
            timeout_ms: 0,
            dlopen_mode: 0,
        };
        unsafe {
            mach_inject_default_options(&mut opts);
        }
        assert!(!opts.verbose);
        assert!(opts.wait_completion);
        assert_eq!(
            opts.timeout_ms,
            rux_core::config::DEFAULT_INJECTION_TIMEOUT_MS as libc::c_uint
        );
        assert_eq!(opts.dlopen_mode, libc::RTLD_NOW);
    }
}
