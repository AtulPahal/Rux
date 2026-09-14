/// Zero-allocation ASCII case-insensitive substring search.
///
/// `needle_lower` MUST already be ASCII-lowercase (callers pass
/// `query.to_ascii_lowercase()` once). Byte-wise comparison is exact for
/// ASCII-folded matching: ASCII bytes never appear inside multi-byte UTF-8
/// sequences, and folding only touches `A-Z`.
#[inline]
pub(crate) fn contains_ascii_case_insensitive(haystack: &str, needle_lower: &str) -> bool {
    if needle_lower.is_empty() {
        return true;
    }
    let hay = haystack.as_bytes();
    let ndl = needle_lower.as_bytes();
    if ndl.len() > hay.len() {
        return false;
    }
    let first = ndl[0];
    let max_start = hay.len() - ndl.len();
    let mut i = 0;
    while i <= max_start {
        if hay[i].to_ascii_lowercase() == first {
            let mut j = 1;
            while j < ndl.len() {
                if hay[i + j].to_ascii_lowercase() != ndl[j] {
                    break;
                }
                j += 1;
            }
            if j == ndl.len() {
                return true;
            }
        }
        i += 1;
    }
    false
}

use rux_core::CpuArchitecture;
use std::path::{Path, PathBuf};

/// Detailed information about a Darwin system process.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessInfo {
    /// Process Identifier (PID)
    pub pid: i32,
    /// Process base name (e.g. "RobloxPlayer")
    pub name: String,
    /// Canonical executable file path, if available
    pub path: Option<PathBuf>,
    /// Target process CPU architecture (e.g. `Arm64` or `X86_64`)
    pub cputype: CpuArchitecture,
}

impl ProcessInfo {
    /// Create a new `ProcessInfo` instance.
    pub fn new(
        pid: i32,
        name: impl Into<String>,
        path: Option<PathBuf>,
        cputype: CpuArchitecture,
    ) -> Self {
        Self {
            pid,
            name: name.into(),
            path,
            cputype,
        }
    }

    /// Check if the process is currently alive.
    pub fn is_alive(&self) -> bool {
        crate::scanner::is_process_alive(self.pid)
    }

    /// Check if this process matches the target search query.
    /// Case-insensitive match against process name or executable filename.
    pub fn matches_query(&self, query: &str) -> bool {
        if query.is_empty() {
            return false;
        }

        // 1. Direct case-insensitive match against process name
        if self.name.eq_ignore_ascii_case(query) {
            return true;
        }

        let query_lower = query.to_ascii_lowercase();

        // 2. Substring match against process name (zero-alloc)
        if contains_ascii_case_insensitive(&self.name, &query_lower) {
            return true;
        }

        // 3. Match against filename portion of path
        if let Some(path) = &self.path {
            if let Some(file_name) = path.file_name().and_then(|n| n.to_str()) {
                if file_name.eq_ignore_ascii_case(query)
                    || contains_ascii_case_insensitive(file_name, &query_lower)
                {
                    return true;
                }
            }

            // 4. Substring match against full path
            if let Some(path_str) = path.to_str() {
                if contains_ascii_case_insensitive(path_str, &query_lower) {
                    return true;
                }
            }
        }

        false
    }

    /// Match using a pre-computed lowercase query string for fast batch scanning.
    pub fn matches_query_precomputed(&self, query: &str, query_lower: &str) -> bool {
        if query.is_empty() {
            return false;
        }

        if self.name.eq_ignore_ascii_case(query) {
            return true;
        }

        if contains_ascii_case_insensitive(&self.name, query_lower) {
            return true;
        }

        if let Some(path) = &self.path {
            if let Some(file_name) = path.file_name().and_then(|n| n.to_str()) {
                if file_name.eq_ignore_ascii_case(query)
                    || contains_ascii_case_insensitive(file_name, query_lower)
                {
                    return true;
                }
            }

            if let Some(path_str) = path.to_str() {
                if contains_ascii_case_insensitive(path_str, query_lower) {
                    return true;
                }
            }
        }

        false
    }

    /// Full path reference if available.
    pub fn path_ref(&self) -> Option<&Path> {
        self.path.as_deref()
    }
}
