//! Running child programs so that Ctrl-C reaches the child, not the shell.
//!
//! The shell ignores SIGINT and SIGQUIT for its whole life (see
//! [`ignore_job_signals`]). Ignored signals stay ignored across `exec`, so
//! every child resets them to the default just before it execs. The terminal
//! sends Ctrl-C to the whole foreground process group, so the child dies and
//! the shell carries on.
//!
//! SIGTSTP (Ctrl-Z) stays ignored in children too: the shell has no job
//! control, and a stopped child would leave the prompt hanging.

use std::ffi::OsStr;
use std::io;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::Path;
use std::process::{Command, ExitStatus};

/// Called once at startup.
pub fn ignore_job_signals() {
    // SAFETY: setting a signal disposition to SIG_IGN is always sound.
    unsafe {
        libc::signal(libc::SIGINT, libc::SIG_IGN);
        libc::signal(libc::SIGQUIT, libc::SIG_IGN);
        libc::signal(libc::SIGTSTP, libc::SIG_IGN);
    }
}

/// Builds a command whose child gets default SIGINT/SIGQUIT handling back.
pub fn command(program: impl AsRef<OsStr>) -> Command {
    let mut cmd = Command::new(program);
    // SAFETY: the closure only calls `signal`, which is async-signal-safe.
    unsafe {
        cmd.pre_exec(|| {
            libc::signal(libc::SIGINT, libc::SIG_DFL);
            libc::signal(libc::SIGQUIT, libc::SIG_DFL);
            Ok(())
        });
    }
    cmd
}

/// Runs `program args...` in the foreground and waits for it.
pub fn run<S: AsRef<OsStr>>(
    program: &Path,
    args: &[S],
    path_env: Option<&OsStr>,
) -> io::Result<ExitStatus> {
    let mut cmd = command(program);
    cmd.args(args);
    if let Some(p) = path_env {
        cmd.env("PATH", p);
    }
    cmd.status()
}

/// Prints a newline when a child was killed by Ctrl-C, so the prompt starts
/// on a fresh line.
pub fn tidy_after(status: &ExitStatus) {
    if status.signal() == Some(libc::SIGINT) {
        println!();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes_arguments_through() {
        let out = command("/bin/sh")
            .args(["-c", "printf '%s|' \"$@\"", "sh", "a b", "", "c'd"])
            .output()
            .unwrap();
        assert_eq!(String::from_utf8(out.stdout).unwrap(), "a b||c'd|");
    }

    #[test]
    fn child_gets_default_sigint() {
        // The child kills itself with SIGINT; with the default action it dies
        // from the signal instead of carrying on to `exit 0`, even though this
        // process ignores SIGINT the way the shell does.
        ignore_job_signals();
        let status = command("/bin/sh")
            .args(["-c", "kill -INT $$; exit 0"])
            .status()
            .unwrap();
        assert_eq!(status.signal(), Some(libc::SIGINT));
    }

    #[test]
    fn reports_exit_codes() {
        let status = run(Path::new("/bin/sh"), &["-c", "exit 3"], None).unwrap();
        assert_eq!(status.code(), Some(3));
    }
}
