#ifndef PROC_UTILS_H
#define PROC_UTILS_H

#include <sys/types.h>
#include <stdbool.h>
#include <stddef.h>
#include <mach/machine.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Find the first running process matching process_name (case-insensitive search
 * against both process name and full executable path).
 * Returns PID if found, or 0 if not found.
 */
pid_t proc_find_by_name(const char *process_name);

/**
 * Find all running processes matching process_name.
 * Populates out_pids up to max_pids.
 * Returns the total number of matching PIDs found.
 */
int proc_find_all_by_name(const char *process_name, pid_t *out_pids, size_t max_pids);

/**
 * Retrieve the process name for a given PID.
 * Returns true on success, false on failure.
 */
bool proc_get_name(pid_t pid, char *out_name, size_t max_len);

/**
 * Retrieve the full executable file path for a given PID.
 * Returns true on success, false on failure.
 */
bool proc_get_path(pid_t pid, char *out_path, size_t max_len);

/**
 * Check whether a process with the given PID is currently alive.
 */
bool proc_is_alive(pid_t pid);

/**
 * Query the CPU architecture (e.g. CPU_TYPE_ARM64 or CPU_TYPE_X86_64) of a PID.
 * Returns 0 on success, or -1 on failure.
 */
int proc_get_cputype(pid_t pid, cpu_type_t *out_cputype);

/**
 * Returns a human-readable string for a cpu_type_t (e.g. "arm64", "x86_64", "unknown").
 */
const char *proc_cputype_to_string(cpu_type_t cputype);

/**
 * Returns the native CPU architecture of the current host process.
 */
cpu_type_t proc_host_cputype(void);

#ifdef __cplusplus
}
#endif

#endif /* PROC_UTILS_H */
