use std::process::ExitCode;

fn main() -> ExitCode {
    if let Some(arg) = std::env::args().nth(1) {
        match arg.as_str() {
            "--version" | "-V" => {
                println!("dos-shell {}", dos_shell::VERSION);
                return ExitCode::SUCCESS;
            }
            _ => {
                eprintln!("usage: dos-shell [--version]");
                return ExitCode::from(2);
            }
        }
    }
    dos_shell::run::ignore_job_signals();
    match dos_shell::repl::Shell::new() {
        Ok(mut shell) => {
            shell.run();
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("dos-shell: can't start the line editor: {e}");
            ExitCode::FAILURE
        }
    }
}
