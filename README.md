# 🦀 Rux — Advanced Darwin Mach-O Dynamic Library Injection Toolchain & IDE

[![macOS](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Architecture](https://img.shields.io/badge/arch-ARM64%20%7C%20x86__64-blue.svg?style=flat)](https://en.wikipedia.org/wiki/Apple_silicon)
[![Rust](https://img.shields.io/badge/rust-1.80%2B-orange.svg?style=flat&logo=rust)](https://www.rust-lang.org)
[![Swift](https://img.shields.io/badge/swift-5.10%2B-red.svg?style=flat&logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-green.svg?style=flat)](LICENSE)

**Rux** is a high-performance, memory-safe Darwin Mach-O dynamic library injection framework, runtime process introspection engine, and native macOS desktop IDE. Written in **modern Rust** with an **AppKit/Swift GUI**, it supports both Apple Silicon (**ARM64**) and Intel (**x86_64**).

---

## 📑 Table of Contents

- [What This App Does](#what-this-app-does)
- [Architecture & Workspace](#architecture--workspace)
- [Native macOS Desktop IDE](#native-macos-desktop-ide-ruxapp)
- [Injected Payload Runtime](#injected-payload-runtime-rux-payload)
- [How It Works](#how-it-works)
- [Known Problems & Roadblocks](#known-problems--roadblocks)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License & Disclaimer](#license--disclaimer)

---

## What This App Does

Rux is a complete Darwin binary engineering toolchain that lets you **inspect**, **attach to**, **inject dynamic libraries into**, and **interact with** running macOS processes — all from either a native desktop app or the command line.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        RUX APPLICATION SUITE                           │
├───────────────────────────────┬────────────────────────────────────────┤
│     Native macOS AppKit IDE   │               CLI Utilities            │
│  • Multi-Tab Code Editor      │  • rux   (Unified CLI)                 │
│  • Real-Time Process Scanner  │  • inject   (Legacy CLI)               │
│  • One-Click Injector Panel   │  • injectarm (Arch Compat CLI)         │
│  • TCP IPC Script Console     │  • libmachinject.a / .dylib (C ABI)    │
│  • Diagnostics & System Audit │                                        │
└───────────────┬───────────────┴────────────────────┬───────────────────┘
                │                                    │
                ▼                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          RUX CORE TOOLCHAIN                            │
│  rux-proc  ─ Process Discovery & Architecture Detection (libproc)      │
│  rux-vm    ─ RAII Mach Task Ports & Virtual Memory Writer              │
│  rux-inject─ Injection Engine, Stubs, Thread State & Synchronization   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Mach Injection
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                             TARGET PROCESS                             │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ Injected Payload (rux-payload)                                    │  │
│  │  • Local TCP IPC Server        • Inline Trampoline Hooks          │  │
│  │  • Luau Script Dispatcher      • 2D Drawing API Overlay           │  │
│  │  • Pure-Rust Crypto Engine     • Safe HTTP Client                 │  │
│  │  • Offline-First Device Identity & Whitelist                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture & Workspace

The codebase is a modular Rust Cargo workspace plus a native Swift/AppKit application:

| Crate | Description |
| :--- | :--- |
| **rux-core** | Core primitives — CPU architecture enum, dlopen mode flags, strongly typed errors, centralized configuration constants, and injection option builder. |
| **rux-proc** | Safe Darwin process inspection — PID enumeration, architecture detection, name/path resolution, and liveness probing via `libproc` and `sysctl`. |
| **rux-vm** | RAII Mach Virtual Memory — task port guards (auto-deallocate on drop), remote memory allocation/deallocation guards, and typed memory read/write/protect operations. |
| **rux-inject** | Mach-O injection engine — position-independent assembly stubs for ARM64 & x86_64, shared cache symbol resolution, remote thread creation, and completion polling. |
| **rux-ffi** | C ABI compatibility layer — produces `libmachinject.a` (static) and `libmachinject.dylib` (dynamic), matching the provided `mach_inject.h` and `proc_utils.h` headers. |
| **rux-payload** | Injected dynamic library — TCP IPC server, Luau script dispatcher, inline trampoline hooks, 2D drawing overlays, pure-Rust crypto, HTTP client, and offline device identity. |
| **rux-cli** | CLI binaries — `rux` (unified CLI with `inject`, `scan`, `test` subcommands), `inject` (legacy compatible), and `injectarm` (architecture-specific entry point). |
| **Rux.app** | Native macOS GUI — Swift/AppKit desktop IDE compiled via `swiftc`, bundled with all CLI tools and payload libraries. |

---

## Native macOS Desktop IDE (`Rux.app`)

| Tab | What It Does |
| :--- | :--- |
| **⚡ Injector** | Select target processes by PID or name, pick payload `.dylib` files, configure dlopen modes and timeouts, and execute injection with administrator privilege handling. |
| **🔍 Process Scanner** | Real-time process monitor showing CPU architecture, resident/virtual memory, parent PID, user identity, code signing flags, CDHash, and Team ID. |
| **💻 Script Console** | Multi-tab code editor with line numbers, soft-wrap, preset scripts, and direct Luau script execution over TCP IPC. Includes payload ping and telemetry display. |
| **🩺 Diagnostics** | Interactive 5-point Darwin diagnostic runner — verifies host architecture, process enumeration, path resolution, Mach VM allocation, and shared cache symbol lookup. |
| **📜 Activity Logs** | Timestamped log stream with level filtering (INFO, SUCCESS, WARNING, ERROR) and clipboard export. |

---

## Injected Payload Runtime (`rux-payload`)

When loaded via `dlopen()`, the payload automatically initializes through its Mach-O constructor and starts these subsystems inside the target process:

| Subsystem | Description |
| :--- | :--- |
| **TCP IPC Server** | Binds to localhost on a configurable port range (default 5553–5563). Accepts script execution, settings updates, ping health checks, and telemetry queries. |
| **Script Dispatcher** | Background thread polling a thread-safe queue, forwarding received scripts to the Lua state manager for execution. |
| **Inline Trampoline Hooks** | Architecture-aware 64-bit jump hooks for ARM64 and x86_64 with instruction cache invalidation and automatic RAII restoration on drop. |
| **2D Drawing API** | Thread-safe overlay render queue supporting lines, text, rectangles, circles, and triangles. |
| **Crypto Engine** | Zero-dependency pure-Rust implementations of SHA-256, SHA-1, MD5, Base64, and Hex. |
| **HTTP Client** | Safe HTTP engine supporting custom headers, cookies, redirect policies, and configurable timeouts. |
| **Device Identity** | Offline-first hardware fingerprinting that defaults to an anonymous zero-hash, preventing hardware UUID leakage and external telemetry. |

---

## How It Works

### Injection Lifecycle (Step-by-Step)

1. **Discover Target** — Enumerate running processes via `libproc`, find the target by PID or name, and verify its CPU architecture matches the host.
2. **Acquire Task Port** — Call `task_for_pid()` to obtain the target's Mach task port (requires root privileges).
3. **Resolve Shared Cache Symbols** — Look up `dlopen`, `_pthread_set_self`, and `pthread_exit` from the dyld shared cache. These addresses are identical across all processes in the same boot session.
4. **Allocate Remote Memory** — Reserve three memory regions inside the target process: a 64 KB stack, a parameter block (`InjectParams`), and a 4 KB code block.
5. **Stage Parameters & Code** — Write the target library path, dlopen flags, resolved symbol addresses, and the position-independent machine code stub into the allocated remote memory.
6. **Enforce W^X Protection** — Transition the code block from writable to read+execute to comply with Darwin's Write XOR Execute policy.
7. **Launch Remote Thread** — Spawn a Mach thread via `thread_create_running` with registers configured to execute the injected stub.
8. **Stub Execution (Inside Target)** — The stub initializes POSIX thread-local storage (`_pthread_set_self`), calls `dlopen()` to load the payload library (triggering its constructor), writes the result back into the parameter block, and calls `pthread_exit()` to cleanly terminate.
9. **Synchronization** — The injector polls the remote parameter block's status field. On success, it cleans up all remote allocations.
10. **IPC Handshake** — The payload's constructor starts a local TCP server. The IDE or CLI connects and begins sending scripts and commands.

### IPC Wire Protocol

Communication between Rux.app (or CLI tools) and the injected payload uses a simple framed TCP protocol over localhost:

| Message Type | Purpose | Response |
| :---: | :--- | :--- |
| Execute | Send a Luau/Lua script for execution | Script queued |
| Setting | Update a key-value configuration pair | Acknowledged |
| Ping | Health check | Single-byte PONG |
| Telemetry | Query runtime stats | JSON with PID, memory, and uptime |

Each message begins with a fixed-size header containing the message type and body length, followed by the variable-length payload body.

---

## Known Problems & Roadblocks

### 1. SIP & `task_for_pid` Denial

**Problem**: `task_for_pid()` fails even with root privileges.

**Cause**: Apple's kernel blocks task port access to processes protected by System Integrity Protection or Hardened Runtime.

**Fix**: For self-authored targets, sign with the `get-task-allow` entitlement. For protected targets, reboot into Recovery Mode and run `csrutil enable --without debug`, then reboot and retry with `sudo`.

---

### 2. Hardened Runtime & Library Validation

**Problem**: The remote thread runs, but `dlopen()` returns NULL.

**Cause**: Targets with Library Validation reject any `.dylib` not signed with the same Apple Developer Team ID.

**Fix**: The target must have `disable-library-validation` in its entitlements, or be re-signed locally with ad-hoc signature.

---

### 3. Raw Mach Thread TLS Crash

**Problem**: Calling `dlopen()` from a freshly created Mach thread crashes the target with `EXC_BAD_ACCESS`.

**Cause**: Mach threads created via `thread_create_running` lack POSIX pthread metadata and Thread-Local Storage. `dlopen()` internally calls `pthread_self()`, which dereferences a NULL TLS pointer.

**How Rux Handles This**: The assembly stub calls `_pthread_set_self(NULL)` before calling `dlopen()`, bootstrapping a valid pthread environment for the raw Mach thread.

---

### 4. ARM64 Stack Alignment & Pointer Authentication

**Problem**: Injection on Apple Silicon can trigger `EXC_ARM_DA_ALIGN` or `EXC_BAD_ACCESS` on function returns.

**Cause**: The ARM64 calling convention requires 16-byte stack alignment. Apple Silicon also enforces Pointer Authentication Codes (PAC) on function pointers in `arm64e` binaries.

**How Rux Handles This**: The stack top is explicitly aligned to a 16-byte boundary. Rux targets the standard `arm64` ABI to avoid PAC signing traps.

---

### 5. GUI Privilege Escalation Overhead

**Problem**: `Rux.app` runs as a normal user but injection requires root.

**Current Behavior**: The GUI elevates privileges by invoking the bundled CLI via AppleScript `with administrator privileges`, which triggers a macOS password/Touch ID prompt each time.

**Future**: Replace with a persistent privileged helper daemon via `SMAppService` / `SMJobBless` using Mach XPC.

---

### 6. Luau Engine State & Dynamic Offsets

**Problem**: The embedded Luau executor currently performs syntax validation rather than full bytecode compilation.

**Cause**: Target process memory layouts (e.g. game engine VM offsets) change frequently, making hardcoded pointer addresses unreliable.

**Future**: Integrate a full Luau compiler VM and implement dynamic Array-of-Bytes (AOB) pattern scanning to locate engine state at runtime.

---

### 7. Gatekeeper Quarantine After Rebuilds

**Problem**: Rebuilding `Rux.app` causes macOS to report "App is damaged and can't be opened."

**Cause**: Recompilation invalidates the existing ad-hoc code signature, and macOS quarantine attributes block unsigned bundles.

**Fix**:
```bash
xattr -cr Rux.app
codesign --force --deep --sign - Rux.app
```

---

## Getting Started

### Prerequisites

- **macOS 14.0+** (Sonoma or later recommended)
- **Apple Silicon (ARM64)** or **Intel (x86_64)**
- **Rust 1.80+** — install via [rustup.rs](https://rustup.rs/)
- **Xcode Command Line Tools** — `xcode-select --install`
- **Python 3** — for app icon generation

### Build

```bash
# Build everything (Rust workspace + native macOS app)
make

# Or build components individually
make build    # Rust workspace only (release mode)
make app      # Compile Swift GUI + assemble Rux.app bundle
make clean    # Remove all build artifacts
```

### Run Tests

```bash
# Rust unit & integration tests
cargo test --workspace

# Darwin system diagnostics
./rux test --verbose
```

Expected diagnostic output:
```
=== Rux Darwin Mach-O Test Suite ===
[TEST 1/5] Host Architecture Detection............... PASS
[TEST 2/5] Darwin Process Enumeration (libproc)...... PASS
[TEST 3/5] Process Inspection & Path Resolution...... PASS
[TEST 4/5] Mach Virtual Memory Writer & Allocation... PASS
[TEST 5/5] Darwin Shared Cache Symbol Resolution..... PASS
Diagnostic Results: 5 passed, 0 failed.
```

---

## Usage

### GUI

```bash
open Rux.app
```

1. Use the **Process Scanner** to find your target.
2. Switch to the **Injector** tab, select the target and payload `.dylib`.
3. Enable **Run with Administrator Privileges** and click **Execute Injection**.
4. After injection, open the **Script Console**, click **Ping Payload** to verify the IPC connection, then write and execute scripts.

### CLI

```bash
# Inject by process name
sudo ./rux inject ./payload.dylib -n TargetApp

# Inject by PID
sudo ./rux inject ./payload.dylib -p 1234

# Inject with verbose output and lazy loading
sudo ./rux inject ./payload.dylib -p 1234 --verbose --mode lazy

# Scan running processes
./rux scan Safari

# Run diagnostics
./rux test --verbose
```

### Legacy CLI Compatibility

```bash
sudo ./inject ./payload.dylib
sudo ./inject -p 1234 ./payload.dylib
sudo ./injectarm ./payload.dylib
```

### CLI Options Reference

| Option | Description | Default |
| :--- | :--- | :--- |
| `-p, --pid <PID>` | Target process PID | — |
| `-n, --name <NAME>` | Target process name | Configurable via `RUX_DEFAULT_TARGET_NAME` env var |
| `-m, --mode <MODE>` | dlopen mode: `now` or `lazy` | `now` |
| `-t, --timeout <MS>` | Wait timeout in milliseconds | `3000` |
| `-w, --no-wait` | Don't wait for dlopen confirmation | `false` |
| `-v, --verbose` | Enable verbose diagnostic output | `false` |
| `-L, --list` | List processes matching target name | — |
| `-T, --test` | Run diagnostic test suite | — |

### Environment Variables

| Variable | Purpose |
| :--- | :--- |
| `RUX_DEFAULT_TARGET_NAME` | Override default target process name |
| `RUX_DEFAULT_TIMEOUT_MS` | Override default injection timeout |
| `RUX_IPC_HOST` | Override IPC bind host (default: `127.0.0.1`) |
| `RUX_IPC_PORT` | Override IPC start port (default: `5553`) |
| `RUX_USER_AGENT` | Override HTTP client user agent |

---

## Troubleshooting

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| `TaskForPidFailed` (kern_return: 5) | Missing root or SIP blocks Hardened Runtime target | Run with `sudo`. If target is hardened, disable SIP debug restrictions from Recovery OS. |
| `DlopenFailed` / dlopen returned NULL | Library Validation rejects unsigned `.dylib` | Sign the `.dylib` with ad-hoc signature, or ensure target has `disable-library-validation`. |
| `ArchitectureMismatch` | ARM64 dylib injected into x86_64 process (or vice versa) | Verify architectures match with `rux scan <name>`. |
| `Timeout` | Remote thread stalled or deadlocked in constructor | Check target logs in Console.app. Ensure `.dylib` constructor returns promptly. |
| IPC Payload OFFLINE | Payload constructor failed or port blocked | Verify target didn't crash. Check if port is blocked by firewall. |
| "App is damaged" | Gatekeeper quarantine after rebuild | Run `xattr -cr Rux.app && codesign --force --deep --sign - Rux.app` |

---

## Roadmap

- [ ] **Privileged Helper Daemon** — Replace AppleScript escalation with an authenticated Launchd helper via `SMAppService` / Mach XPC for seamless root access.
- [ ] **Full Luau VM Integration** — Embed a complete Luau compiler and bytecode VM for native script execution inside the target process.
- [ ] **Dynamic AOB Scanner** — Implement runtime pattern scanning inside the payload to locate engine state pointers across target software updates.
- [ ] **Mach Exception Port Monitor** — Intercept target process exceptions and stream symbolized crash reports to the Activity Logs tab.
- [ ] **Unix Domain Socket IPC** — Add a domain socket transport alongside TCP to avoid macOS firewall popup dialogs.
- [ ] **Automated Code Signing** — Integrate on-the-fly ad-hoc signing of third-party `.dylib` files before injection.

---

## License & Disclaimer

Dual-licensed under **MIT** or **Apache-2.0** — at your option.

> ⚠️ **Disclaimer**: This software is intended solely for educational purposes, security research, reverse engineering, and debugging on systems you own or have explicit authorization to test. Modifying third-party application memory may violate terms of service. The authors assume no liability for misuse.
