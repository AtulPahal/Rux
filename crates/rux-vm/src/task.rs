use crate::sys::{mach_port_deallocate, mach_task_self, task_for_pid};
use mach2::kern_return::KERN_SUCCESS;
use mach2::port::mach_port_t;
use rux_core::{mach_error_string, InjectError, Result};

/// Safe RAII wrapper around a Darwin Mach task port.
#[derive(Debug)]
pub struct MachTask {
    port: mach_port_t,
    pid: Option<i32>,
    owned: bool,
}

impl MachTask {
    /// Retrieve a reference to the current process's task port.
    pub fn self_task() -> Self {
        unsafe {
            Self {
                port: mach_task_self(),
                pid: Some(std::process::id() as i32),
                owned: false,
            }
        }
    }

    /// Acquire the Mach task port for a target process by PID using `task_for_pid()`.
    ///
    /// # Safety and Permissions
    /// Calling `task_for_pid()` on another process requires root privileges (`sudo`)
    /// or appropriate entitlements / debugging permissions on macOS.
    pub fn for_pid(pid: i32) -> Result<Self> {
        if pid <= 0 {
            return Err(InjectError::InvalidArguments(format!(
                "Invalid PID: {}",
                pid
            )));
        }

        let my_pid = std::process::id() as i32;
        if pid == my_pid {
            return Ok(Self::self_task());
        }

        unsafe {
            let self_port = mach_task_self();
            let mut target_port: mach_port_t = 0;
            let kr = task_for_pid(self_port, pid, &mut target_port);

            if kr != KERN_SUCCESS || target_port == 0 {
                let is_root = libc::geteuid() == 0;
                let message = mach_error_string(kr);
                return Err(InjectError::TaskForPidFailed {
                    pid,
                    kern_return: kr,
                    message,
                    is_root,
                });
            }

            Ok(Self {
                port: target_port,
                pid: Some(pid),
                owned: true,
            })
        }
    }

    /// Construct a `MachTask` from an existing raw task port.
    ///
    /// # Safety
    /// Caller must ensure `port` is valid. If `owned` is true, `port` will be deallocated upon drop.
    pub unsafe fn from_raw_port(port: mach_port_t, pid: Option<i32>, owned: bool) -> Self {
        Self { port, pid, owned }
    }

    /// Retrieve the raw Mach task port.
    pub fn port(&self) -> mach_port_t {
        self.port
    }

    /// Associated PID if known.
    pub fn pid(&self) -> Option<i32> {
        self.pid
    }

    /// Check if this task port represents the current host process.
    pub fn is_self(&self) -> bool {
        self.pid == Some(std::process::id() as i32)
    }
}

impl Drop for MachTask {
    fn drop(&mut self) {
        if self.owned && self.port != 0 {
            unsafe {
                let self_port = mach_task_self();
                mach_port_deallocate(self_port, self.port);
                self.port = 0;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_self_task() {
        let task = MachTask::self_task();
        assert_ne!(task.port(), 0);
        assert!(task.is_self());
    }

    #[test]
    fn test_task_for_self_pid() {
        let my_pid = std::process::id() as i32;
        let task = MachTask::for_pid(my_pid).expect("failed to get self task");
        assert_ne!(task.port(), 0);
    }
}
