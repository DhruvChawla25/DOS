//! The prompt loop and the built-in commands.

use std::ffi::OsStr;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};

use rustyline::Editor;
use rustyline::config::{CompletionType, Config};
use rustyline::error::ReadlineError;
use rustyline::history::{FileHistory, History};

use crate::builtins::Builtin;
use crate::complete::DosHelper;
use crate::help;
use crate::lookup::{self, Dirs, Resolved};
use crate::parse::{self, Parsed};
use crate::run;

const HISTORY_SIZE: usize = 2000;

const BANNER: &str = r"
  ____   ___  ____
 |  _ \ / _ \/ ___|
 | | | | | | \___ \
 | |_| | |_| |___) |
 |____/ \___/|____/
";

/// What the loop should do after a line.
#[derive(Debug, PartialEq, Eq)]
enum Flow {
    Continue,
    Quit,
}

pub struct Shell {
    editor: Editor<DosHelper, FileHistory>,
    history_file: Option<PathBuf>,
    interactive: bool,
    color: bool,
    home: Option<String>,
    prev_dir: Option<PathBuf>,
}

/// `$DOS_STATE/history`, defaulting to `~/.local/state/dos/history`.
fn history_path() -> Option<PathBuf> {
    let state = std::env::var_os("DOS_STATE")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state/dos")))?;
    Some(state.join("history"))
}

impl Shell {
    pub fn new() -> rustyline::Result<Self> {
        let config = Config::builder()
            .max_history_size(HISTORY_SIZE)?
            .history_ignore_dups(true)?
            .history_ignore_space(true)
            .auto_add_history(false)
            .completion_type(CompletionType::List)
            .build();
        let mut editor = Editor::with_config(config)?;
        editor.set_helper(Some(DosHelper::new(Dirs::from_env())));

        let history_file = history_path();
        if let Some(p) = &history_file {
            if let Some(dir) = p.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            if p.exists() {
                let _ = editor.load_history(p);
            }
        }

        let color = std::env::var_os("NO_COLOR").is_none()
            && std::env::var("TERM").map(|t| t != "dumb").unwrap_or(true)
            && io::stdout().is_terminal();

        Ok(Shell {
            editor,
            history_file,
            interactive: io::stdin().is_terminal(),
            color,
            home: std::env::var("HOME").ok().filter(|h| !h.is_empty()),
            prev_dir: None,
        })
    }

    fn dirs(&self) -> &Dirs {
        &self.editor.helper().expect("helper is always set").dirs
    }

    fn paint(&self, code: &str, text: &str) -> String {
        if self.color {
            format!("\x1b[{code}m{text}\x1b[0m")
        } else {
            text.to_string()
        }
    }

    pub fn run(&mut self) {
        if self.interactive {
            self.banner();
        }
        let prompt = ("DOS> ".to_string(), self.paint("1;36", "DOS>") + " ");
        loop {
            match self.editor.readline(&prompt) {
                Ok(line) => {
                    self.remember(&line);
                    if self.execute(&line) == Flow::Quit {
                        break;
                    }
                }
                // Ctrl-C at the prompt just gives a fresh prompt.
                Err(ReadlineError::Interrupted) => continue,
                // Ctrl-D is the same as `exit`. With piped input it just ends.
                Err(ReadlineError::Eof) => {
                    if !self.interactive || self.builtin_exit() == Flow::Quit {
                        break;
                    }
                }
                Err(e) => {
                    eprintln!("dos-shell: {e}");
                    break;
                }
            }
        }
    }

    fn banner(&self) {
        print!("{}", self.paint("1;36", BANNER));
        println!(
            "\n  Dhruv's Operating System · DOS Shell {}\n  Type {} to see the commands.\n",
            crate::VERSION,
            self.paint("1", "help")
        );
        // Login notices from profile.d aren't visible inside sway, so the shell
        // shows the daily "updates available" line itself. Quiet if absent.
        let _ = std::process::Command::new("dos-update")
            .arg("--notice")
            .stdin(std::process::Stdio::null())
            .status();
    }

    fn remember(&mut self, line: &str) {
        if line.trim().is_empty() {
            return;
        }
        if matches!(self.editor.add_history_entry(line), Ok(true))
            && let Some(p) = &self.history_file
        {
            // Saved after every line, so a power-off never loses history.
            let _ = self.editor.append_history(p);
        }
    }

    /// Runs one typed line.
    fn execute(&mut self, line: &str) -> Flow {
        let parsed = match parse::parse(line, self.home.as_deref()) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("dos: {e}");
                return Flow::Continue;
            }
        };
        match parsed {
            Parsed::Empty => Flow::Continue,
            Parsed::Words(words) => self.dispatch(&words),
            Parsed::Shell { words } => {
                let first = words.first().map(String::as_str).unwrap_or("");
                if let Some(b) = Builtin::from_name(first) {
                    eprintln!(
                        "{}: pipes, redirects, wildcards and $variables only work with \
                         normal commands (or inside sh)",
                        b.name()
                    );
                    return Flow::Continue;
                }
                let path = self.dirs().child_path();
                self.spawn(Path::new("bash"), &["-c", line], &path, "bash");
                Flow::Continue
            }
        }
    }

    fn dispatch(&mut self, words: &[String]) -> Flow {
        let (name, args) = words.split_first().expect("at least one word");
        match lookup::resolve(name, self.dirs()) {
            Resolved::Builtin(b) => self.builtin(b, args),
            Resolved::Command(p) | Resolved::External(p) => {
                let path = self.dirs().child_path();
                self.spawn(&p, args, &path, name);
                Flow::Continue
            }
            Resolved::Unknown => {
                eprintln!("unknown command: {name} (type help)");
                Flow::Continue
            }
        }
    }

    fn spawn<S: AsRef<OsStr>>(&self, program: &Path, args: &[S], path: &OsStr, name: &str) {
        let _ = io::stdout().flush();
        match run::run(program, args, Some(path)) {
            Ok(status) => run::tidy_after(&status),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                eprintln!("{name}: not installed");
            }
            Err(e) => eprintln!("{name}: can't run it: {e}"),
        }
    }

    /// Runs a program from PATH by name, for built-ins like `wifi`.
    fn run_tool<S: AsRef<OsStr>>(&self, builtin: &str, tool: &str, args: &[S]) {
        match lookup::find_in_path(tool, self.dirs().path.as_deref()) {
            Some(p) => self.spawn(&p, args, &self.dirs().child_path(), tool),
            None => eprintln!("{builtin}: {tool} is not installed"),
        }
    }

    /// Asks a y/N question. Anything but y/yes (including Ctrl-C and
    /// Ctrl-D) means no.
    fn confirm(&mut self, question: &str) -> bool {
        if !self.interactive {
            return false;
        }
        match self.editor.readline(&format!("{question} [y/N] ")) {
            Ok(answer) => matches!(answer.trim().to_lowercase().as_str(), "y" | "yes"),
            Err(_) => {
                println!();
                false
            }
        }
    }

    fn builtin(&mut self, b: Builtin, args: &[String]) -> Flow {
        match b {
            Builtin::Help => self.builtin_help(args),
            Builtin::Clear => {
                print!("\x1b[H\x1b[2J\x1b[3J");
                let _ = io::stdout().flush();
            }
            Builtin::History => self.builtin_history(args),
            Builtin::Version => println!("DOS Shell {}", crate::VERSION),
            Builtin::Wifi => self.run_tool("wifi", "nmtui", args),
            Builtin::Update => self.run_tool("update", "dos-update", args),
            Builtin::Sh => {
                if args.is_empty() {
                    println!("bash shell. Type exit to return to DOS.");
                }
                self.run_tool("sh", "bash", args);
            }
            Builtin::Cd => self.builtin_cd(args),
            Builtin::Shutdown => {
                if self.confirm("Power off now?") {
                    self.run_tool("shutdown", "systemctl", &["poweroff"]);
                }
            }
            Builtin::Reboot => {
                if self.confirm("Restart now?") {
                    self.run_tool("reboot", "systemctl", &["reboot"]);
                }
            }
            Builtin::Exit => return self.builtin_exit(),
        }
        Flow::Continue
    }

    fn builtin_help(&self, args: &[String]) {
        let entries = help::discover(self.dirs());
        if args.is_empty() {
            println!("DOS commands:\n");
            print!("{}", help::format(&entries));
            println!("\nAny Linux command works too, pipes and wildcards included.");
            return;
        }
        for name in args {
            match entries.iter().find(|e| &e.name == name) {
                Some(e) => print!("{}", help::format(std::slice::from_ref(e))),
                None => match lookup::resolve(name, self.dirs()) {
                    Resolved::External(p) => {
                        println!(
                            "  {name}  Linux program ({}); try {name} --help",
                            p.display()
                        )
                    }
                    _ => eprintln!("unknown command: {name} (type help)"),
                },
            }
        }
    }

    fn builtin_history(&mut self, args: &[String]) {
        if args.first().map(String::as_str) == Some("clear") {
            let _ = self.editor.clear_history();
            if let Some(p) = &self.history_file {
                let _ = std::fs::write(p, "");
            }
            return;
        }
        let history = self.editor.history();
        let width = history.len().to_string().len();
        for (i, entry) in history.iter().enumerate() {
            println!("{:>width$}  {entry}", i + 1);
        }
    }

    fn builtin_cd(&mut self, args: &[String]) {
        let target = match args.first().map(String::as_str) {
            None => match &self.home {
                Some(h) => PathBuf::from(h),
                None => {
                    eprintln!("cd: HOME is not set");
                    return;
                }
            },
            Some("-") => match &self.prev_dir {
                Some(p) => p.clone(),
                None => {
                    eprintln!("cd: no previous folder");
                    return;
                }
            },
            Some(dir) => PathBuf::from(dir),
        };
        let before = std::env::current_dir().ok();
        match std::env::set_current_dir(&target) {
            Ok(()) => self.prev_dir = before,
            Err(e) => eprintln!("cd: {}: {}", target.display(), plain_error(&e)),
        }
    }

    fn builtin_exit(&mut self) -> Flow {
        if self.interactive && !self.confirm("Leave DOS?") {
            return Flow::Continue;
        }
        if std::env::var_os("SWAYSOCK").is_some_and(|s| !s.is_empty()) {
            self.run_tool("exit", "swaymsg", &["exit"]);
        }
        Flow::Quit
    }
}

/// An io::Error without the "(os error 2)" suffix.
fn plain_error(e: &io::Error) -> String {
    match e.kind() {
        io::ErrorKind::NotFound => "no such folder".into(),
        io::ErrorKind::PermissionDenied => "permission denied".into(),
        io::ErrorKind::NotADirectory => "not a folder".into(),
        _ => e.to_string(),
    }
}
