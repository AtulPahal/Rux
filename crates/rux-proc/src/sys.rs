use std::mem;

pub const PROC_ALL_PIDS: u32 = 1;
pub const PROC_PIDTBSDINFO: libc::c_int = 3;
pub const PROC_PIDPATHINFO_MAXSIZE: usize = 4096;
pub const PROC_PIDTBSDINFO_SIZE: usize = mem::size_of::<proc_bsdinfo>();
pub const CTL_MAXNAME: usize = 12;

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct proc_bsdinfo {
    pub pbi_flags: u32,
    pub pbi_status: u32,
    pub pbi_xstatus: u32,
    pub pbi_pid: u32,
    pub pbi_ppid: u32,
    pub pbi_uid: libc::uid_t,
    pub pbi_gid: libc::gid_t,
    pub pbi_ruid: libc::uid_t,
    pub pbi_rgid: libc::gid_t,
    pub pbi_svuid: libc::uid_t,
    pub pbi_svgid: libc::gid_t,
    pub rfu_1: u32,
    pub pbi_comm: [libc::c_char; 16],
    pub pbi_name: [libc::c_char; 32],
    pub pbi_nfiles: u32,
    pub pbi_pgid: u32,
    pub pbi_pjobc: u32,
    pub e_tdev: u32,
    pub e_tpgid: u32,
    pub pbi_nice: i32,
    pub pbi_start_tvsec: u64,
    pub pbi_start_tvusec: u64,
}

unsafe extern "C" {
    pub fn proc_listpids(
        type_: u32,
        typeinfo: u32,
        buffer: *mut libc::c_void,
        buffersize: libc::c_int,
    ) -> libc::c_int;

    pub fn proc_pidinfo(
        pid: libc::c_int,
        flavor: libc::c_int,
        arg: u64,
        buffer: *mut libc::c_void,
        buffersize: libc::c_int,
    ) -> libc::c_int;

    pub fn proc_pidpath(
        pid: libc::c_int,
        buffer: *mut libc::c_void,
        buffersize: u32,
    ) -> libc::c_int;

    pub fn sysctlnametomib(
        name: *const libc::c_char,
        mibp: *mut libc::c_int,
        sizep: *mut libc::size_t,
    ) -> libc::c_int;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bsdinfo_layout() {
        assert_eq!(mem::size_of::<proc_bsdinfo>(), 136);
    }
}
