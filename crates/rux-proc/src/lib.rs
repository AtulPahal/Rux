//! Rux Process Inspection Library
//!
//! Darwin process enumeration, query, architecture detection, and lifecycle monitoring.

pub mod process;
pub mod scanner;
pub mod sys;

pub use process::ProcessInfo;
pub use scanner::{
    find_all_by_name, find_by_name, find_by_pid, get_process_cputype, get_process_name,
    get_process_path, is_process_alive, list_all, list_pids,
};
