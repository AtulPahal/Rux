#[path = "../common.rs"]
mod common;

use clap::Parser;
use common::{execute_injection, list_matching_processes, CliOptions};
use rux_core::DlopenMode;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "injectarm",
    author = "Nexus42 & Rux Contributors",
    version,
    about = "MacSploit ARM64 Dynamic Library Injector (Darwin Mach-O)",
    override_usage = "injectarm [options] <dylib_path>\n       injectarm <pid> <dylib_path>\n       injectarm <dylib_path>"
)]
struct InjectArmCli {
    #[arg(value_name = "ARG1")]
    arg1: Option<String>,

    #[arg(value_name = "DYLIB")]
    arg2: Option<PathBuf>,

    #[arg(short, long, value_name = "PID")]
    pid: Option<i32>,

    #[arg(short, long, default_value_t = common::get_default_process_name())]
    name: String,

    #[arg(short, long, value_name = "PATH")]
    lib: Option<PathBuf>,

    #[arg(short, long, default_value = "now")]
    mode: String,

    #[arg(short, long, default_value_t = common::get_default_timeout_ms())]
    timeout: u64,

    #[arg(short = 'w', long)]
    no_wait: bool,

    #[arg(short = 'L', long)]
    list: bool,

    #[arg(short, long)]
    verbose: bool,
}

fn main() {
    let args = InjectArmCli::parse();

    if args.list {
        list_matching_processes(&args.name);
        std::process::exit(0);
    }

    let mut target_pid = args.pid;
    let mut dylib_path = args.lib;

    if let Some(a1) = args.arg1 {
        if let Ok(pid) = a1.parse::<i32>() {
            target_pid = Some(pid);
            if let Some(a2) = args.arg2 {
                dylib_path = Some(a2);
            }
        } else {
            dylib_path = Some(PathBuf::from(a1));
        }
    }

    if dylib_path.is_none() {
        use clap::CommandFactory;
        let mut cmd = InjectArmCli::command();
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
