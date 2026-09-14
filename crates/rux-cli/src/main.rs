mod common;

use clap::{Args, Parser, Subcommand};
use common::{execute_injection, list_matching_processes, run_diagnostic_tests, CliOptions};
use rux_core::DlopenMode;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "rux",
    author = "Nexus42 & Rux Contributors",
    version,
    about = "Production-grade Darwin Mach-O Dynamic Library Injection Toolchain",
    long_about = "Rux is an advanced, memory-safe Darwin Mach-O injection engine and process introspection toolchain.\nSupports Apple Silicon (ARM64) and Intel (x86_64) on macOS."
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Path to dynamic library (.dylib) to inject (shorthand mode)
    #[arg(value_name = "DYLIB")]
    dylib: Option<PathBuf>,

    /// Target process PID to inject into
    #[arg(short, long, value_name = "PID")]
    pid: Option<i32>,

    /// Target process name (default: RobloxPlayer)
    #[arg(short, long, value_name = "NAME")]
    name: Option<String>,

    /// dlopen loading mode: 'now' (default) or 'lazy'
    #[arg(short, long, default_value = "now")]
    mode: String,

    /// Wait timeout in milliseconds
    #[arg(short, long, default_value_t = common::get_default_timeout_ms())]
    timeout: u64,
    /// Do not wait for remote dlopen confirmation
    #[arg(short = 'w', long)]
    no_wait: bool,

    /// List running processes matching target name
    #[arg(short = 'L', long)]
    list: bool,

    /// Run automated diagnostic and regression test suite
    #[arg(short = 'T', long)]
    test: bool,

    /// Enable verbose diagnostic output
    #[arg(short, long)]
    verbose: bool,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Inject dynamic library into a target process
    Inject(InjectArgs),
    /// Search and list running processes by name or path
    #[command(alias = "list")]
    Scan(ScanArgs),
    /// Run automated diagnostic test suite
    Test(TestArgs),
}

#[derive(Args, Debug)]
struct InjectArgs {
    /// Path to dynamic library (.dylib) to inject
    #[arg(value_name = "DYLIB")]
    dylib: PathBuf,

    /// Target process PID
    #[arg(short, long)]
    pid: Option<i32>,

    /// Target process name (default: RobloxPlayer)
    #[arg(short, long)]
    name: Option<String>,

    /// dlopen loading mode: 'now' (default) or 'lazy'
    #[arg(short, long, default_value = "now")]
    mode: String,

    /// Wait timeout in milliseconds
    #[arg(short, long, default_value_t = common::get_default_timeout_ms())]
    timeout: u64,
    /// Do not wait for remote dlopen confirmation
    #[arg(short = 'w', long)]
    no_wait: bool,

    /// Enable verbose diagnostic output
    #[arg(short, long)]
    verbose: bool,
}

#[derive(Args, Debug)]
struct ScanArgs {
    /// Process name or substring to search for
    #[arg(default_value_t = common::get_default_process_name())]
    query: String,
}

#[derive(Args, Debug)]
struct TestArgs {
    /// Enable verbose test output
    #[arg(short, long)]
    verbose: bool,
}

fn main() {
    let cli = Cli::parse();

    // 1. Check if a subcommand was given
    if let Some(cmd) = cli.command {
        let code = match cmd {
            Commands::Inject(args) => {
                let mode = DlopenMode::from_str_lenient(&args.mode).unwrap_or(DlopenMode::Now);
                let opts = CliOptions {
                    pid: args.pid,
                    name: args.name,
                    dylib_path: Some(args.dylib),
                    mode,
                    timeout_ms: args.timeout,
                    no_wait: args.no_wait,
                    list: false,
                    verbose: args.verbose,
                    test: false,
                };
                execute_injection(opts)
            }
            Commands::Scan(args) => {
                list_matching_processes(&args.query);
                0
            }
            Commands::Test(args) => run_diagnostic_tests(args.verbose),
        };
        std::process::exit(code);
    }

    // 2. Flags from top-level shorthand:
    if cli.test {
        std::process::exit(run_diagnostic_tests(cli.verbose));
    }

    if cli.list {
        let default_name = common::get_default_process_name();
        let name = cli.name.as_deref().unwrap_or(&default_name);
        list_matching_processes(name);
        std::process::exit(0);
    }

    if let Some(dylib_path) = cli.dylib {
        let mode = DlopenMode::from_str_lenient(&cli.mode).unwrap_or(DlopenMode::Now);
        let opts = CliOptions {
            pid: cli.pid,
            name: cli.name,
            dylib_path: Some(dylib_path),
            mode,
            timeout_ms: cli.timeout,
            no_wait: cli.no_wait,
            list: false,
            verbose: cli.verbose,
            test: false,
        };
        std::process::exit(execute_injection(opts));
    }

    // If no command and no dylib passed, print help
    use clap::CommandFactory;
    let mut cmd = Cli::command();
    let _ = cmd.print_help();
    println!();
}
