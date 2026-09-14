#[path = "../common.rs"]
mod common;

use clap::Parser;
use common::{execute_injection, list_matching_processes, CliOptions};
use rux_core::DlopenMode;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "inject",
    author = "Nexus42 & Rux Contributors",
    version,
    about = "MacSploit Dynamic Library Injector (Darwin Mach-O)",
    override_usage = "inject [options] <dylib_path>\n       inject <pid> <dylib_path>\n       inject <dylib_path>"
)]
struct InjectCli {
    /// Positional argument 1: either PID or dylib path
    #[arg(value_name = "ARG1")]
    arg1: Option<String>,

    /// Positional argument 2: dylib path when arg1 is a PID
    #[arg(value_name = "DYLIB")]
    arg2: Option<PathBuf>,

    /// Target process PID to inject into
    #[arg(short, long, value_name = "PID")]
    pid: Option<i32>,

    /// Target process name
    #[arg(short, long, default_value_t = common::get_default_process_name())]
    name: String,
    /// Path to dynamic library (.dylib)
    #[arg(short, long, value_name = "PATH")]
    lib: Option<PathBuf>,

    /// dlopen mode: 'now' (default) or 'lazy'
    #[arg(short, long, default_value = "now")]
    mode: String,

    /// Wait timeout in milliseconds
    #[arg(short, long, default_value_t = common::get_default_timeout_ms())]
    timeout: u64,
    /// Do not wait for remote dlopen confirmation
    #[arg(short = 'w', long)]
    no_wait: bool,

    /// List running processes matching name
    #[arg(short = 'L', long)]
    list: bool,

    /// Enable detailed diagnostic output
    #[arg(short, long)]
    verbose: bool,
}

fn main() {
    let args = InjectCli::parse();

    if args.list {
        list_matching_processes(&args.name);
        std::process::exit(0);
    }

    // Resolve PID and dylib path from flags and positional arguments
    let mut target_pid = args.pid;
    let mut dylib_path = args.lib;

    if let Some(a1) = args.arg1 {
        if let Ok(pid) = a1.parse::<i32>() {
            // "inject <pid> <dylib>"
            target_pid = Some(pid);
            if let Some(a2) = args.arg2 {
                dylib_path = Some(a2);
            }
        } else {
            // "inject <dylib>"
            dylib_path = Some(PathBuf::from(a1));
        }
    }

    if dylib_path.is_none() {
        use clap::CommandFactory;
        let mut cmd = InjectCli::command();
        let _ = cmd.print_help();
        println!();
        std::process::exit(1);
    }

    let mode = DlopenMode::from_str_lenient(&args.mode).unwrap_or(DlopenMode::Now);
    let opts = CliOptions {
        pid: target_pid,
        name: Some(args.name),
        dylib_path,
        mode,
        timeout_ms: args.timeout,
        no_wait: args.no_wait,
        list: false,
        verbose: args.verbose,
        test: false,
    };

    std::process::exit(execute_injection(opts));
}
