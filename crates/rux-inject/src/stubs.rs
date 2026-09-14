use rux_core::config::{INJECT_DYLIB_PATH_CAP, REMOTE_CODE_ALLOC_SIZE, REMOTE_STACK_SIZE};

/// Size of the remote stack allocated for the injection thread (64 KB).
pub const STACK_SIZE: usize = REMOTE_STACK_SIZE;

/// Size of the remote code block allocated for the injection shellcode stub (4 KB).
pub const CODE_ALLOC_SIZE: usize = REMOTE_CODE_ALLOC_SIZE;

/// Parameter block shared between injector and remote position-independent shellcode stub.
///
/// Must match exact memory offsets expected by [`ARM64_STUB`] and [`X86_64_STUB`].
#[repr(C, align(8))]
#[derive(Debug, Clone, Copy)]
pub struct InjectParams {
    /// Canonical null-terminated path to the dynamic library (offset 0x000, 1024 bytes)
    pub dylib_path: [u8; INJECT_DYLIB_PATH_CAP],
    /// Loading mode flags passed to `dlopen()` (offset 0x400 / 1024, 4 bytes)
    pub mode: i32,
    /// Completion status: 0 = pending, 1 = success, -1 = dlopen failed (offset 0x404 / 1028, 4 bytes)
    pub status: i32,
    /// Absolute address of `dlopen` in shared cache (offset 0x408 / 1032, 8 bytes)
    pub dlopen_addr: u64,
    /// Absolute address of `_pthread_set_self` in shared cache (offset 0x410 / 1040, 8 bytes)
    pub pthread_set_self_addr: u64,
    /// Absolute address of `pthread_exit` in shared cache (offset 0x418 / 1048, 8 bytes)
    pub pthread_exit_addr: u64,
    /// Remote module handle returned by `dlopen()` (offset 0x420 / 1056, 8 bytes)
    pub dlopen_result: u64,
}

impl Default for InjectParams {
    fn default() -> Self {
        Self {
            dylib_path: [0u8; INJECT_DYLIB_PATH_CAP],
            mode: libc::RTLD_NOW,
            status: 0,
            dlopen_addr: 0,
            pthread_set_self_addr: 0,
            pthread_exit_addr: 0,
            dlopen_result: 0,
        }
    }
}

impl InjectParams {
    /// Initialize parameter block with target library path, dlopen flags, and resolved symbol addresses.
    pub fn new(
        path: &str,
        mode: i32,
        dlopen_addr: u64,
        pthread_set_self_addr: u64,
        pthread_exit_addr: u64,
    ) -> Self {
        let mut params = Self::default();
        let path_bytes = path.as_bytes();
        let copy_len = path_bytes.len().min(params.dylib_path.len() - 1);
        params.dylib_path[..copy_len].copy_from_slice(&path_bytes[..copy_len]);
        params.dylib_path[copy_len] = 0; // Ensure null termination
        params.mode = mode;
        params.status = 0; // Pending
        params.dlopen_addr = dlopen_addr;
        params.pthread_set_self_addr = pthread_set_self_addr;
        params.pthread_exit_addr = pthread_exit_addr;
        params.dlopen_result = 0;
        params
    }
}

/// ARM64 position-independent injection stub machine code.
///
/// Execution flow:
/// 1. Prologue: Save frame pointer, link register, callee-saved registers x19, x20.
///    Copy params pointer from x0 to callee-saved x19.
/// 2. Call `pthread_set_self(NULL)` to initialize thread-local storage for new Mach thread.
/// 3. Call `dlopen(dylib_path, mode)` with params->dylib_path and params->mode.
/// 4. Store result into params->dlopen_result and write status:
///    - If result != 0: status = 1 (success)
///    - If result == 0: status = -1 (failed)
/// 5. Call `pthread_exit(NULL)` to cleanly terminate the thread without crashing host process.
/// 6. Epilogue: Restore registers and return.
pub const ARM64_STUB: &[u8] = &[
    0xfd, 0x7b, 0xbe, 0xa9, // stp  x29, x30, [sp, #-32]!
    0xfd, 0x03, 0x00, 0x91, // mov  x29, sp
    0xf3, 0x53, 0x01, 0xa9, // stp  x19, x20, [sp, #16]
    0xf3, 0x03, 0x00, 0xaa, // mov  x19, x0
    // 1. pthread_set_self(NULL)
    0x68, 0x0a, 0x42, 0xf9, // ldr  x8, [x19, #1040]
    0x68, 0x00, 0x00, 0xb4, // cbz  x8, +12 (skip)
    0x00, 0x00, 0x80, 0xd2, // mov  x0, #0
    0x00, 0x01, 0x3f, 0xd6, // blr  x8
    // 2. dlopen(dylib_path, mode)
    0x60, 0x02, 0x00, 0x91, // add  x0, x19, #0
    0x61, 0x02, 0x44, 0xb9, // ldr  w1, [x19, #1024]
    0x68, 0x06, 0x42, 0xf9, // ldr  x8, [x19, #1032]
    0x28, 0x01, 0x00, 0xb4, // cbz  x8, +36 (skip)
    0x00, 0x01, 0x3f, 0xd6, // blr  x8
    0x60, 0x12, 0x02, 0xf9, // str  x0, [x19, #1056]
    0x80, 0x00, 0x00, 0xb5, // cbnz x0, +16 (success)
    0x09, 0x00, 0x80, 0x12, // mov  w9, #-1
    0x69, 0x06, 0x04, 0xb9, // str  w9, [x19, #1028]
    0x03, 0x00, 0x00, 0x14, // b    +12 (done)
    0x29, 0x00, 0x80, 0x52, // mov  w9, #1
    0x69, 0x06, 0x04, 0xb9, // str  w9, [x19, #1028]
    // 3. pthread_exit(NULL)
    0x68, 0x0e, 0x42, 0xf9, // ldr  x8, [x19, #1048]
    0x68, 0x00, 0x00, 0xb4, // cbz  x8, +12 (skip)
    0x00, 0x00, 0x80, 0xd2, // mov  x0, #0
    0x00, 0x01, 0x3f, 0xd6, // blr  x8
    // Epilogue
    0xf3, 0x53, 0x41, 0xa9, // ldp  x19, x20, [sp, #16]
    0xfd, 0x7b, 0xc2, 0xa8, // ldp  x29, x30, [sp], #32
    0xc0, 0x03, 0x5f, 0xd6, // ret
];

/// x86_64 position-independent injection stub machine code.
///
/// Execution flow:
/// 1. Prologue: Push rbp, set rsp, push rbx, align stack (sub 8, rsp).
///    Move params pointer from rdi to callee-saved rbx.
/// 2. Call `pthread_set_self(NULL)`.
/// 3. Call `dlopen(dylib_path, mode)`.
/// 4. Store return handle and status flag (1 = success, -1 = fail).
/// 5. Call `pthread_exit(NULL)`.
/// 6. Epilogue: Restore stack and return.
pub const X86_64_STUB: &[u8] = &[
    0x55, // push   %rbp
    0x48, 0x89, 0xe5, // mov    %rsp, %rbp
    0x53, // push   %rbx
    0x48, 0x83, 0xec, 0x08, // sub    $8, %rsp
    0x48, 0x89, 0xfb, // mov    %rdi, %rbx
    // 1. pthread_set_self(NULL)
    0x48, 0x8b, 0x83, 0x10, 0x04, 0x00, 0x00, // mov    1040(%rbx), %rax
    0x48, 0x85, 0xc0, // test   %rax, %rax
    0x74, 0x04, // jz     +4
    0x31, 0xff, // xor    %edi, %edi
    0xff, 0xd0, // callq  *%rax
    // 2. dlopen(dylib_path, mode)
    0x48, 0x8d, 0x3b, // leaq   (%rbx), %rdi
    0x8b, 0xb3, 0x00, 0x04, 0x00, 0x00, // mov    1024(%rbx), %esi
    0x48, 0x8b, 0x83, 0x08, 0x04, 0x00, 0x00, // mov    1032(%rbx), %rax
    0x48, 0x85, 0xc0, // test   %rax, %rax
    0x74, 0x24, // jz     +36
    0xff, 0xd0, // callq  *%rax
    0x48, 0x89, 0x83, 0x20, 0x04, 0x00, 0x00, // mov    %rax, 1056(%rbx)
    0x48, 0x85, 0xc0, // test   %rax, %rax
    0x75, 0x0c, // jne    +12 (success)
    0xc7, 0x83, 0x04, 0x04, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, // movl   $-1, 1028(%rbx)
    0xeb, 0x0a, // jmp    +10
    0xc7, 0x83, 0x04, 0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, // movl   $1, 1028(%rbx)
    // 3. pthread_exit(NULL)
    0x48, 0x8b, 0x83, 0x18, 0x04, 0x00, 0x00, // mov    1048(%rbx), %rax
    0x48, 0x85, 0xc0, // test   %rax, %rax
    0x74, 0x04, // jz     +4
    0x31, 0xff, // xor    %edi, %edi
    0xff, 0xd0, // callq  *%rax
    0x48, 0x83, 0xc4, 0x08, // add    $8, %rsp
    0x5b, // pop    %rbx
    0x5d, // pop    %rbp
    0xc3, // retq
];

#[cfg(test)]
mod tests {
    use super::*;
    use rux_core::config::{
        INJECT_DYLIB_PATH_CAP, INJECT_OFF_DLOPEN_ADDR, INJECT_OFF_DLOPEN_RESULT, INJECT_OFF_MODE,
        INJECT_OFF_PTHREAD_EXIT_ADDR, INJECT_OFF_PTHREAD_SET_SELF_ADDR, INJECT_OFF_STATUS,
    };
    use std::mem;

    #[test]
    fn test_inject_params_offsets() {
        let dummy = InjectParams::default();
        let base = &dummy as *const _ as usize;

        assert_eq!((&dummy.dylib_path as *const _ as usize) - base, 0);
        assert_eq!((&dummy.mode as *const _ as usize) - base, INJECT_OFF_MODE);
        assert_eq!(
            (&dummy.status as *const _ as usize) - base,
            INJECT_OFF_STATUS
        );
        assert_eq!(
            (&dummy.dlopen_addr as *const _ as usize) - base,
            INJECT_OFF_DLOPEN_ADDR
        );
        assert_eq!(
            (&dummy.pthread_set_self_addr as *const _ as usize) - base,
            INJECT_OFF_PTHREAD_SET_SELF_ADDR
        );
        assert_eq!(
            (&dummy.pthread_exit_addr as *const _ as usize) - base,
            INJECT_OFF_PTHREAD_EXIT_ADDR
        );
        assert_eq!(
            (&dummy.dlopen_result as *const _ as usize) - base,
            INJECT_OFF_DLOPEN_RESULT
        );
        assert_eq!(mem::size_of::<InjectParams>(), INJECT_DYLIB_PATH_CAP + 40);
    }
}
