# Rux — Advanced Darwin Mach-O Dynamic Library Injection Toolchain

A production-grade, memory-safe Darwin Mach-O dynamic library injection framework and process introspection toolchain written in **modern, idiomatic Rust**. Supports Apple Silicon (**ARM64**) and Intel (**x86_64**) on macOS.

---

## Architecture & Library Workspace

The codebase is organized as a modular Rust workspace separating concerns into reusable, memory-safe libraries and CLI tools:

```
Rux/
├── crates/
│   ├── rux-core/       # Core primitives, CPU architecture enums, strongly-typed errors
│   ├── rux-proc/       # Darwin process inspection, PID resolution, architecture detection
│   ├── rux-vm/         # Safe Mach Virtual Memory (mach_vm_*) & RAII Remote Memory Writer
│   ├── rux-inject/     # Mach-O injection engine with ARM64 & x86_64 position-independent stubs
│   ├── rux-ffi/        # C ABI compatibility library (libmachinject.a & libmachinject.dylib)
│   ├── rux-payload/    # Injected dynamic library payload (IPC, Crypto, Drawing, Hooks, HTTP)
│   └── rux-cli/        # Modern CLI binaries: `rux`, `inject`, and `injectarm`
├── app/                # Native macOS GUI application (Rux.app) written in Swift/AppKit
├── Rux.app             # Standalone signed macOS Application Bundle
├── mach_inject.h       # C header for mach_inject API
├── proc_utils.h        # C header for process inspection API
├── Makefile            # Unified build system for Rust workspace, CLI tools, and Mac App
└── Cargo.toml          # Workspace root manifest

### 1. `rux-core`
- **`CpuArchitecture`**: Strongly-typed architecture representation (`Arm64`, `X86_64`, `Arm32`, `X86_32`, `Unknown`). Converts to/from Mach `cpu_type_t`.
- **`DlopenMode`**: Typed representation of `dlopen()` flags (`Now`, `Lazy`, `Global`, `Local`).
- **`InjectError`**: Exhaustive, structured error type built with `thiserror` (e.g. `TaskForPidFailed`, `ArchitectureMismatch`, `VmAllocateFailed`, `DlopenFailed`, `Timeout`).
- **`InjectionOptions` & Builder**: Configurable execution parameters (timeout, verbosity, wait completion, dlopen flags).

### 2. `rux-proc`
- Safe Darwin process inspection wrapping `libproc` and `sysctl`:
  - `list_pids()`: Enumerate all running PIDs with auto-expanding buffers.
  - `list_all()`: Retrieve structured `ProcessInfo` for all processes.
  - `find_by_name()` & `find_all_by_name()`: Case-insensitive search across process names and canonical executable paths.
  - `get_process_cputype()`: Query CPU architecture of running processes via `sysctl.proc_cputype`.
  - `is_process_alive()`: Safe liveness checking via `kill(pid, 0)`.

### 3. `rux-vm` (Remote Memory Writer)
Replaces manual, unmanaged C memory manipulation with safe, RAII-governed Mach Virtual Memory abstractions:
- **`MachTask`**: RAII wrapper around Mach task ports (`task_for_pid`). Automatically deallocates ports on drop, preventing Mach port leaks.
- **`RemoteAllocation`**: RAII-guarded remote memory block. Automatically frees memory in the target process via `mach_vm_deallocate` if not explicitly leaked/forgotten.
- **`MemoryWriter`**: High-level typed memory writer:
  - `allocate(size, prot) -> Result<RemoteAllocation>`
  - `write_bytes(address, &[u8]) -> Result<()>`
  - `write_val<T: Copy>(address, &T) -> Result<()>`
  - `read_bytes(address, len) -> Result<Vec<u8>>`
  - `read_val<T: Copy + Default>(address) -> Result<T>`
  - `protect(address, size, prot) -> Result<()>`

### 4. `rux-inject`
High-performance dynamic library injection engine:
- Position-independent assembly stubs for **ARM64** and **x86_64**.
- Remote thread creation via `thread_create_running` with proper 16-byte stack alignment.
- Shared cache symbol resolution for `dlopen`, `_pthread_set_self`, and `pthread_exit`.
- W^X memory protection enforcement (`PAGE_READ | PAGE_EXECUTE`).
- Active synchronization and status confirmation via remote memory polling.

### 5. `rux-ffi`
- Exports static (`libmachinject.a`) and dynamic (`libmachinject.dylib`) libraries.
- Exposes standard C ABI declarations matching `mach_inject.h` and `proc_utils.h` for seamless drop-in replacement in existing C/C++ projects.

### 6. `rux-cli`
- Modern CLI interface built with `clap` (derive API).
- Binaries generated:
  - `rux`: Main CLI with `inject`, `scan`, and `test` subcommands.
  - `inject`: Drop-in CLI compatible with existing automation scripts.
  - `injectarm`: Architecture-specific compatibility entry point.

### 7. `rux-payload` (Injected Dynamic Library)
Fully replaces the legacy C++ client payload with a memory-safe, modular Rust dynamic library:
- **`ipc`**: Local TCP IPC command receiver on ports 5553–5563 (Ping/Pong, Settings, Script Execution Queue).
- **`settings`**: Thread-safe configuration store backed by `parking_lot::RwLock` and `LazyLock`.
- **`crypto`**: Pure-Rust cryptographic engine with Base64, Hex, SHA-1, SHA-256, and MD5 (zero third-party dependencies).
- **`drawing`**: Complete 2D Drawing API primitives (`Line`, `Text`, `Square`, `Circle`, `Triangle`) with thread-safe `DrawingRegistry`.
- **`hook`**: Architecture-aware 64-bit jump trampolines for ARM64 and x86_64 with instruction cache flushing and automatic RAII unhooking.
- **`http`**: Safe HTTP client engine supporting custom headers, cookies, redirects, and timeouts.
- **`fingerprint` & `whitelist`**: Privacy-first device identification with **Offline Mode by default** (prevents hardware UUID leakage and external telemetry).

---

##  Building & Testing

### Prerequisites
- macOS (Apple Silicon or Intel)
- Rust 1.80+ (`rustup default stable`)
- Clang / Xcode Command Line Tools (`xcode-select --install`)

### Build Everything (CLI + Mac App)
```bash
make
# or build the native macOS Application Bundle specifically:
make app
```

### Run Tests
```bash
# Run Rust workspace unit and integration tests
cargo test --workspace

# Run full CLI and C ABI compatibility tests
make test
```

---

##  Native macOS App (`Rux.app`)

Rux includes a fully native macOS GUI application (`Rux.app`) designed for macOS Apple Silicon and Intel:

- **⚡ Injector Tab**: Select target processes by name or PID, browse for `.dylib` payloads (or use the bundled payload), configure `dlopen` modes (`RTLD_NOW` / `RTLD_LAZY`), timeouts, and authenticate with Touch ID / administrator privileges.
- **🔍 Process Scanner Tab**: High-speed real-time process scanner using Darwin `libproc` with live search, architecture filtering (`ARM64` / `x86_64`), and one-click process targeting.
- **💻 Script Console & IPC Tab**: Real-time Luau script executor and TCP IPC client connecting to the injected payload on port `5553`. Includes script presets, syntax fonts, and payload ping testing.
- **🩺 Diagnostics Tab**: Interactive runner for the Darwin system diagnostics suite verifying host architecture, process inspection, Mach VM allocation, and shared cache symbol resolution.
- ** Activity Logs Tab**: Live log streaming with timestamped entries, level filtering, and clipboard export.

### Launching Rux.app
```bash
open Rux.app
```

---

##  CLI Usage

### Inject into a Process by Name
```bash
sudo ./rux inject ./exploit.dylib -n RobloxPlayer
# or shorthand:
sudo ./rux ./exploit.dylib -n RobloxPlayer
```

### Inject into a Process by PID
```bash
sudo ./rux inject ./exploit.dylib -p 1234
# or shorthand:
sudo ./rux ./exploit.dylib -p 1234
```

### Search and Inspect Processes
```bash
./rux scan Roblox
./rux scan Finder
```

### Run System Diagnostics
```bash
./rux test --verbose
```

### Legacy CLI Compatibility
```bash
sudo ./inject ./exploit.dylib
sudo ./inject -p 1234 ./exploit.dylib
sudo ./injectarm ./exploit.dylib
```

---

##  Security & Permissions Notice
On macOS, accessing another process's Mach task port via `task_for_pid()` requires root privileges. Run injection commands with `sudo`:

```bash
sudo rux inject <dylib_path> -p <pid>
```

Hardened Runtime targets (e.g. `RobloxPlayer`: `flags=0x10000(runtime)`, no `get-task-allow` entitlement) cannot be attached to while SIP debugging restrictions are enabled — `task_for_pid()` fails even as root. Either inject a non-hardened test process, or reboot into Recovery OS and run `csrutil enable --without debug`, then retry with sudo.
