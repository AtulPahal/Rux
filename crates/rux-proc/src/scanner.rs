use crate::process::ProcessInfo;
use crate::sys::{
    proc_bsdinfo, proc_listpids, proc_pidinfo, proc_pidpath, sysctlnametomib, CTL_MAXNAME,
    PROC_ALL_PIDS, PROC_PIDPATHINFO_MAXSIZE, PROC_PIDTBSDINFO, PROC_PIDTBSDINFO_SIZE,
};
use rux_core::{CpuArchitecture, InjectError, Result};
use std::ffi::CString;
use std::mem::{self, MaybeUninit};
use std::path::PathBuf;
use std::sync::OnceLock;

static PROC_CPUTYPE_MIB: OnceLock<Option<([i32; CTL_MAXNAME], usize)>> = OnceLock::new();

/// Cached MIB prefix for `sysctl.proc_cputype` to avoid repeated sysctlnametomib syscalls.
fn get_proc_cputype_mib_base() -> Option<([i32; CTL_MAXNAME], usize)> {
    *PROC_CPUTYPE_MIB.get_or_init(|| {
        let name = CString::new("sysctl.proc_cputype").ok()?;
        let mut mib = [0i32; CTL_MAXNAME];
        let mut mib_len: libc::size_t = CTL_MAXNAME as libc::size_t;
        unsafe {
            if sysctlnametomib(name.as_ptr(), mib.as_mut_ptr(), &mut mib_len) == 0
                && mib_len < CTL_MAXNAME as libc::size_t
            {
                Some((mib, mib_len as usize))
            } else {
                None
            }
        }
    })
}

/// Check whether a process with the given PID is currently alive and accessible.
pub fn is_process_alive(pid: i32) -> bool {
    if pid <= 0 {
        return false;
    }
    unsafe {
        // Sending signal 0 performs error checking without sending an actual signal
        let ret = libc::kill(pid, 0);
        if ret == 0 {
            return true;
        }
        // EPERM means the process exists but belongs to another user (alive and active)
        let errno = *libc::__error();
        errno == libc::EPERM
    }
}

/// Retrieve the CPU architecture of a process by its PID using Darwin `sysctl.proc_cputype`.
///
/// Uses cached MIB prefix for high throughput process scanning.
pub fn get_process_cputype(pid: i32) -> Result<CpuArchitecture> {
    if pid <= 0 {
        return Err(InjectError::InvalidArguments(format!(
            "Invalid PID: {}",
            pid
        )));
    }

    let (mut mib, mib_len) = get_proc_cputype_mib_base().ok_or_else(|| {
        InjectError::ProcessNotFound(format!(
            "Failed to resolve sysctl.proc_cputype MIB for PID {}",
            pid
        ))
    })?;

    if mib_len >= CTL_MAXNAME {
        return Err(InjectError::ProcessNotFound(format!(
            "MIB length overflow for PID {}",
            pid
        )));
    }

    mib[mib_len] = pid;
    let query_len = (mib_len + 1) as libc::c_uint;

    let mut cputype: i32 = 0;
    let mut len: libc::size_t = mem::size_of::<i32>() as libc::size_t;

    unsafe {
        if libc::sysctl(
            mib.as_mut_ptr(),
            query_len,
            &mut cputype as *mut i32 as *mut libc::c_void,
            &mut len,
            std::ptr::null_mut(),
            0,
        ) != 0
        {
            return Err(InjectError::ProcessNotFound(format!(
                "sysctl query failed for PID {}",
                pid
            )));
        }
    }

    Ok(CpuArchitecture::from_raw(cputype))
}

/// Retrieve the canonical executable path for a process by its PID.
///
/// Uses stack-allocated buffer (zero heap allocation during syscall).
pub fn get_process_path(pid: i32) -> Result<PathBuf> {
    if pid <= 0 {
        return Err(InjectError::InvalidArguments(format!(
            "Invalid PID: {}",
            pid
        )));
    }

    // Stack allocated buffer - zero heap allocation overhead
    let mut buf = [0u8; PROC_PIDPATHINFO_MAXSIZE];
    unsafe {
        let ret = proc_pidpath(pid, buf.as_mut_ptr() as *mut libc::c_void, buf.len() as u32);
        if ret <= 0 {
            return Err(InjectError::ProcessNotFound(format!(
                "Failed to get path for PID {}",
                pid
            )));
        }

        let slice = &buf[..ret as usize];
        let s = std::str::from_utf8(slice)
            .map_err(|_| InjectError::ProcessNotFound("Invalid UTF-8 in proc path".into()))?;
        Ok(PathBuf::from(s.trim_end_matches('\0')))
    }
}

/// Retrieve the process name for a given PID.
///
/// Safe bounds-checking ensures no out-of-bounds reads past `pbi_name` buffer.
pub fn get_process_name(pid: i32) -> Result<String> {
    if pid <= 0 {
        return Err(InjectError::InvalidArguments(format!(
            "Invalid PID: {}",
            pid
        )));
    }

    unsafe {
        let mut bsd_info: MaybeUninit<proc_bsdinfo> = MaybeUninit::uninit();
        let ret = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            bsd_info.as_mut_ptr() as *mut libc::c_void,
            PROC_PIDTBSDINFO_SIZE as libc::c_int,
        );

        if ret == PROC_PIDTBSDINFO_SIZE as libc::c_int {
            let info = bsd_info.assume_init();
            // Bound read safely within pbi_name's fixed 32-byte boundary
            let raw_bytes: &[u8] = std::slice::from_raw_parts(
                info.pbi_name.as_ptr() as *const u8,
                info.pbi_name.len(),
            );
            let nul_pos = raw_bytes
                .iter()
                .position(|&b| b == 0)
                .unwrap_or(raw_bytes.len());
            if let Ok(name_str) = std::str::from_utf8(&raw_bytes[..nul_pos]) {
                let trimmed = name_str.trim();
                if !trimmed.is_empty() {
                    return Ok(trimmed.to_string());
                }
            }
        }
    }

    // Fallback: extract base filename from executable path
    if let Ok(path) = get_process_path(pid) {
        if let Some(file_name) = path.file_name().and_then(|f| f.to_str()) {
            return Ok(file_name.to_string());
        }
    }

    Err(InjectError::ProcessNotFound(format!(
        "Failed to determine process name for PID {}",
        pid
    )))
}

/// Retrieve the full list of running PIDs on the system.
pub fn list_pids() -> Result<Vec<i32>> {
    unsafe {
        let bytes_needed = proc_listpids(PROC_ALL_PIDS, 0, std::ptr::null_mut(), 0);
        if bytes_needed <= 0 {
            return Err(InjectError::ProcessNotFound(
                "proc_listpids returned non-positive size".into(),
            ));
        }

        // Add margin for newly created processes
        let alloc_bytes = (bytes_needed as usize)
            + (rux_core::config::PROC_LIST_SLACK_ENTRIES * mem::size_of::<i32>());
        let count = alloc_bytes / mem::size_of::<i32>();
        let mut pids = vec![0i32; count];

        let bytes_read = proc_listpids(
            PROC_ALL_PIDS,
            0,
            pids.as_mut_ptr() as *mut libc::c_void,
            alloc_bytes as libc::c_int,
        );

        if bytes_read <= 0 {
            return Err(InjectError::ProcessNotFound(
                "proc_listpids failed to populate buffer".into(),
            ));
        }

        let actual_count = (bytes_read as usize) / mem::size_of::<i32>();
        pids.truncate(actual_count);
        // Filter out PID 0 and invalid PIDs
        pids.retain(|&p| p > 0);
        Ok(pids)
    }
}

/// Query information for all running processes on the system.
pub fn list_all() -> Result<Vec<ProcessInfo>> {
    let pids = list_pids()?;
    let mut processes = Vec::with_capacity(pids.len());

    for pid in pids {
        if let Ok(Some(proc)) = find_by_pid(pid) {
            processes.push(proc);
        }
    }

    Ok(processes)
}

/// Find a specific process by PID.
pub fn find_by_pid(pid: i32) -> Result<Option<ProcessInfo>> {
    if !is_process_alive(pid) {
        return Ok(None);
    }

    let name = get_process_name(pid).unwrap_or_else(|_| format!("pid-{}", pid));
    let path = get_process_path(pid).ok();
    let cputype = get_process_cputype(pid).unwrap_or(CpuArchitecture::Unknown(0));

    Ok(Some(ProcessInfo::new(pid, name, path, cputype)))
}

/// Find the first running process matching process_name (case-insensitive search).
///
/// Optimized to check process name first before making expensive path/cputype queries.
pub fn find_by_name(process_name: &str) -> Result<Option<ProcessInfo>> {
    if process_name.is_empty() {
        return Err(InjectError::InvalidArguments("Empty process name".into()));
    }

    let pids = list_pids()?;
    let query_lower = process_name.to_ascii_lowercase();

    for pid in pids {
        // Fast name check first (zero-alloc substring search)
        if let Ok(name) = get_process_name(pid) {
            let name_matches = name.eq_ignore_ascii_case(process_name)
                || crate::process::contains_ascii_case_insensitive(&name, &query_lower);

            if name_matches {
                let path = get_process_path(pid).ok();
                let cputype = get_process_cputype(pid).unwrap_or(CpuArchitecture::Unknown(0));
                return Ok(Some(ProcessInfo::new(pid, name, path, cputype)));
            }

            // If name didn't match, check full path if available
            if let Ok(path) = get_process_path(pid) {
                if let Some(path_str) = path.to_str() {
                    if crate::process::contains_ascii_case_insensitive(path_str, &query_lower) {
                        let cputype =
                            get_process_cputype(pid).unwrap_or(CpuArchitecture::Unknown(0));
                        return Ok(Some(ProcessInfo::new(pid, name, Some(path), cputype)));
                    }
                }
            }
        }
    }

    Ok(None)
}

/// Find all running processes matching process_name (case-insensitive search).
pub fn find_all_by_name(process_name: &str) -> Result<Vec<ProcessInfo>> {
    if process_name.is_empty() {
        return Err(InjectError::InvalidArguments("Empty process name".into()));
    }

    let pids = list_pids()?;
    let query_lower = process_name.to_ascii_lowercase();
    let mut matching = Vec::new();

    for pid in pids {
        if let Ok(name) = get_process_name(pid) {
            let name_matches = name.eq_ignore_ascii_case(process_name)
                || crate::process::contains_ascii_case_insensitive(&name, &query_lower);

            if name_matches {
                let path = get_process_path(pid).ok();
                let cputype = get_process_cputype(pid).unwrap_or(CpuArchitecture::Unknown(0));
                matching.push(ProcessInfo::new(pid, name, path, cputype));
                continue;
            }

            // Path fallback
            if let Ok(path) = get_process_path(pid) {
                if let Some(path_str) = path.to_str() {
                    if crate::process::contains_ascii_case_insensitive(path_str, &query_lower) {
                        let cputype =
                            get_process_cputype(pid).unwrap_or(CpuArchitecture::Unknown(0));
                        matching.push(ProcessInfo::new(pid, name, Some(path), cputype));
                    }
                }
            }
        }
    }

    Ok(matching)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_current_process_alive() {
        let my_pid = std::process::id() as i32;
        assert!(is_process_alive(my_pid));
    }

    #[test]
    fn test_current_process_info() {
        let my_pid = std::process::id() as i32;
        let info = find_by_pid(my_pid).expect("find_by_pid failed");
        assert!(info.is_some());
        let info = info.unwrap();
        assert_eq!(info.pid, my_pid);
        assert!(!info.name.is_empty());
        assert!(info.path.is_some());
        assert!(info.cputype.is_supported_64bit());
    }

    #[test]
    fn test_find_by_name_self() {
        let my_pid = std::process::id() as i32;
        let my_info = find_by_pid(my_pid).unwrap().unwrap();
        let found = find_by_name(&my_info.name).expect("find_by_name failed");
        assert!(found.is_some());
    }
}
