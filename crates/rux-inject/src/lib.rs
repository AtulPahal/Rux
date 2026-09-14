//! Rux Mach-O Dynamic Library Injection Engine
//!
//! Production-grade Darwin Mach-O injection engine with position-independent
//! machine code stubs for ARM64 and x86_64, safe remote thread creation,
//! parameter serialization, and synchronization.

pub mod engine;
pub mod stubs;
pub mod thread;

pub use engine::{inject_name, inject_pid};
pub use stubs::{InjectParams, ARM64_STUB, CODE_ALLOC_SIZE, STACK_SIZE, X86_64_STUB};
pub use thread::{create_remote_thread, resolve_system_symbols, SystemSymbols};
