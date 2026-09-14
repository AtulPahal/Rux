//! Rux Core
//!
//! Core types, errors, architecture enums, and options for the Rux Darwin Mach-O
//! dynamic library injection framework.

pub mod arch;
pub mod config;
pub mod error;
pub mod options;

pub use arch::{CpuArchitecture, CPU_TYPE_ARM64, CPU_TYPE_X86_64};
pub use error::{mach_error_string, InjectError, Result};
pub use options::{DlopenMode, InjectionOptions, InjectionOptionsBuilder, InjectionResult};
