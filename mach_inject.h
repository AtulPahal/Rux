#ifndef MACH_INJECT_H
#define MACH_INJECT_H

#include <sys/types.h>
#include <stdbool.h>
#include <stdint.h>
#include <dlfcn.h>
#include <mach/machine.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Result error codes */
enum {
    MACH_INJECT_SUCCESS              = 0,
    MACH_INJECT_ERR_INVALID_ARG      = -1,
    MACH_INJECT_ERR_FILE_NOT_FOUND   = -2,
    MACH_INJECT_ERR_PROCESS_NOT_FOUND= -3,
    MACH_INJECT_ERR_TASK_FOR_PID     = -4,
    MACH_INJECT_ERR_ARCH_MISMATCH    = -5,
    MACH_INJECT_ERR_VM_ALLOC         = -6,
    MACH_INJECT_ERR_VM_WRITE         = -7,
    MACH_INJECT_ERR_VM_PROTECT       = -8,
    MACH_INJECT_ERR_THREAD_CREATE    = -9,
    MACH_INJECT_ERR_DLOPEN_FAILED    = -10,
    MACH_INJECT_ERR_TIMEOUT          = -11,
    MACH_INJECT_ERR_NO_SYMBOLS       = -12,
    MACH_INJECT_ERR_CLEANUP_FAILED   = -13,
};

/**
 * Injection options controlling behavior and verification.
 */
typedef struct {
    bool verbose;               /* Enable detailed diagnostic output */
    bool wait_completion;       /* Wait for remote thread to execute dlopen() */
    unsigned int timeout_ms;    /* Max wait time in ms when wait_completion is true */
    int dlopen_mode;            /* Flags passed to remote dlopen() (e.g. RTLD_NOW) */
} mach_inject_options_t;

/**
 * Detailed injection execution result.
 */
typedef struct {
    uint64_t remote_handle;     /* Remote module handle returned by dlopen() */
    int32_t status;             /* 0 = pending, 1 = success, -1 = dlopen failed */
} mach_inject_result_t;

/**
 * Populate options struct with robust default values:
 * - verbose: false
 * - wait_completion: true
 * - timeout_ms: 3000
 * - dlopen_mode: RTLD_NOW
 */
void mach_inject_default_options(mach_inject_options_t *opts);

/**
 * Inject a dynamic library (.dylib) into a target process by PID.
 *
 * @param pid Target process ID
 * @param dylib_path Path to the dylib file (relative or absolute)
 * @param options Pointer to options struct, or NULL for default options
 * @return MACH_INJECT_SUCCESS (0) on success, or negative MACH_INJECT_ERR_* code
 */
int mach_inject_pid(pid_t pid, const char *dylib_path, const mach_inject_options_t *options);

/**
 * Extended injection function that returns execution results (remote dlopen handle).
 */
int mach_inject_pid_ext(pid_t pid, const char *dylib_path,
                        const mach_inject_options_t *options,
                        mach_inject_result_t *out_result);

/**
 * Inject a dynamic library into the first running process matching process_name.
 *
 * @param process_name Process name (e.g. "RobloxPlayer")
 * @param dylib_path Path to the dylib file
 * @param options Pointer to options struct, or NULL for default options
 * @return MACH_INJECT_SUCCESS on success, or negative error code
 */
int mach_inject_name(const char *process_name, const char *dylib_path, const mach_inject_options_t *options);

/**
 * Return a human-readable description of a MACH_INJECT_ERR_* code.
 */
const char *mach_inject_strerror(int err_code);

#ifdef __cplusplus
}
#endif

#endif /* MACH_INJECT_H */
