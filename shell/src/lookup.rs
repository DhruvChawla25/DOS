//! Finding what a command name refers to.
//!
//! Lookup order:
//! 1. a built-in,
//! 2. an executable in the user commands dir (`~/.local/share/dos/commands`),
//! 3. an executable in the system commands dir (`/usr/local/share/dos/commands`),
//! 4. any executable on `PATH`,
//! 5. otherwise unknown.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use crate::builtins::Builtin;

pub const DEFAULT_SYSTEM_DIR: &str = "/usr/local/share/dos/commands";

/// Where DOS commands live.
#[derive(Debug, Clone)]
pub struct Dirs {
    pub user: Option<PathBuf>,
    pub system: PathBuf,
    pub path: Option<OsString>,
}

impl Dirs {
    /// Reads the dirs from the environment: `DOS_USER_COMMANDS_DIR`,
    /// `DOS_COMMANDS_DIR`, `HOME` and `PATH`.
    pub fn from_env() -> Self {
        Self::from_vars(|k| std::env::var_os(k))
    }

    /// Like [`Dirs::from_env`], with the variables supplied by `var`.
    pub fn from_vars(var: impl Fn(&str) -> Option<OsString>) -> Self {
        let non_empty = |k: &str| var(k).filter(|v| !v.is_empty());
        let user = non_empty("DOS_USER_COMMANDS_DIR")
            .map(PathBuf::from)
            .or_else(|| {
                non_empty("HOME").map(|h| PathBuf::from(h).join(".local/share/dos/commands"))
            });
        let system = non_empty("DOS_COMMANDS_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_SYSTEM_DIR));
        Dirs {
            user,
            system,
            path: var("PATH"),
        }
    }

    /// The DOS command dirs, highest priority first.
    pub fn command_dirs(&self) -> impl Iterator<Item = &Path> {
        self.user
            .as_deref()
            .into_iter()
            .chain([self.system.as_path()])
    }

    /// `PATH` with the DOS command dirs at the END, for children that run
    /// through bash (so `apps | grep x` still finds DOS commands). They must not
    /// come first: DOS has commands like `install` that would shadow system
    /// tools (`/usr/bin/install`) for every program the child starts, such as
    /// makepkg during an AUR build.
    pub fn child_path(&self) -> OsString {
        let mut parts: Vec<PathBuf> = Vec::new();
        if let Some(p) = &self.path {
            parts.extend(std::env::split_paths(p));
        }
        parts.extend(self.command_dirs().map(Path::to_path_buf));
        std::env::join_paths(parts).unwrap_or_else(|_| self.path.clone().unwrap_or_default())
    }
}

/// What a name resolved to.
#[derive(Debug, PartialEq, Eq)]
pub enum Resolved {
    Builtin(Builtin),
    /// A DOS command script from one of the command dirs.
    Command(PathBuf),
    /// A normal program from `PATH`, or a path the user typed.
    External(PathBuf),
    Unknown,
}

/// True for a regular file (or a symlink to one) with an execute bit set.
pub fn is_executable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// A name that is safe to look up inside a commands dir.
fn is_plain_name(name: &str) -> bool {
    !name.is_empty() && name != "." && name != ".." && !name.contains('/')
}

pub fn find_in_path(name: &str, path: Option<&OsStr>) -> Option<PathBuf> {
    if !is_plain_name(name) {
        return None;
    }
    std::env::split_paths(path?)
        .filter(|d| !d.as_os_str().is_empty())
        .map(|d| d.join(name))
        .find(|p| is_executable(p))
}

pub fn resolve(name: &str, dirs: &Dirs) -> Resolved {
    if let Some(b) = Builtin::from_name(name) {
        return Resolved::Builtin(b);
    }
    if name.contains('/') {
        // `./script` or `/usr/bin/foo`: run that file directly.
        let p = PathBuf::from(name);
        return if is_executable(&p) {
            Resolved::External(p)
        } else {
            Resolved::Unknown
        };
    }
    if !is_plain_name(name) {
        return Resolved::Unknown;
    }
    for dir in dirs.command_dirs() {
        let p = dir.join(name);
        if is_executable(&p) {
            return Resolved::Command(p);
        }
    }
    match find_in_path(name, dirs.path.as_deref()) {
        Some(p) => Resolved::External(p),
        None => Resolved::Unknown,
    }
}

/// Names of every executable in the DOS command dirs (unsorted, may repeat).
pub fn command_names(dirs: &Dirs) -> Vec<String> {
    let mut out = Vec::new();
    for dir in dirs.command_dirs() {
        out.extend(executables_in(dir).into_iter().map(|(n, _)| n));
    }
    out
}

/// `(name, path)` for each executable file directly inside `dir`.
pub fn executables_in(dir: &Path) -> Vec<(String, PathBuf)> {
    let Ok(rd) = fs::read_dir(dir) else {
        return Vec::new();
    };
    rd.filter_map(Result::ok)
        .filter_map(|e| {
            let name = e.file_name().into_string().ok()?;
            if name.starts_with('.') {
                return None;
            }
            let p = e.path();
            is_executable(&p).then_some((name, p))
        })
        .collect()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::TempDir;

    /// Writes an executable command script with an optional help line.
    pub fn make_cmd(dir: &Path, name: &str, help: Option<&str>) -> PathBuf {
        fs::create_dir_all(dir).unwrap();
        let p = dir.join(name);
        let mut f = fs::File::create(&p).unwrap();
        writeln!(f, "#!/usr/bin/env bash").unwrap();
        if let Some(h) = help {
            writeln!(f, "# help: {h}").unwrap();
        }
        writeln!(f, "echo {name}").unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        p
    }

    pub struct Fixture {
        _tmp: TempDir,
        pub user: PathBuf,
        pub system: PathBuf,
        pub bin: PathBuf,
        pub dirs: Dirs,
    }

    pub fn fixture() -> Fixture {
        let tmp = TempDir::new().unwrap();
        let user = tmp.path().join("user");
        let system = tmp.path().join("system");
        let bin = tmp.path().join("bin");
        for d in [&user, &system, &bin] {
            fs::create_dir_all(d).unwrap();
        }
        let dirs = Dirs {
            user: Some(user.clone()),
            system: system.clone(),
            path: Some(std::env::join_paths([&bin]).unwrap()),
        };
        Fixture {
            _tmp: tmp,
            user,
            system,
            bin,
            dirs,
        }
    }

    #[test]
    fn builtins_win_over_everything() {
        let f = fixture();
        make_cmd(&f.user, "help", None);
        make_cmd(&f.system, "help", None);
        make_cmd(&f.bin, "help", None);
        assert_eq!(resolve("help", &f.dirs), Resolved::Builtin(Builtin::Help));
    }

    #[test]
    fn user_dir_beats_system_dir_beats_path() {
        let f = fixture();
        let sys = make_cmd(&f.system, "chrome", None);
        let bin = make_cmd(&f.bin, "chrome", None);
        assert_eq!(resolve("chrome", &f.dirs), Resolved::Command(sys));
        let user = make_cmd(&f.user, "chrome", None);
        assert_eq!(resolve("chrome", &f.dirs), Resolved::Command(user));
        fs::remove_file(f.user.join("chrome")).unwrap();
        fs::remove_file(f.system.join("chrome")).unwrap();
        assert_eq!(resolve("chrome", &f.dirs), Resolved::External(bin));
    }

    #[test]
    fn falls_back_to_path_then_unknown() {
        let f = fixture();
        let ls = make_cmd(&f.bin, "ls", None);
        assert_eq!(resolve("ls", &f.dirs), Resolved::External(ls));
        assert_eq!(resolve("nope", &f.dirs), Resolved::Unknown);
    }

    #[test]
    fn non_executable_files_are_skipped() {
        let f = fixture();
        let p = make_cmd(&f.user, "spotify", None);
        fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
        let sys = make_cmd(&f.system, "spotify", None);
        assert_eq!(resolve("spotify", &f.dirs), Resolved::Command(sys));
    }

    #[test]
    fn directories_are_not_commands() {
        let f = fixture();
        fs::create_dir_all(f.user.join("epic")).unwrap();
        assert_eq!(resolve("epic", &f.dirs), Resolved::Unknown);
    }

    #[test]
    fn missing_dirs_are_fine() {
        let f = fixture();
        let dirs = Dirs {
            user: None,
            system: f.system.join("does-not-exist"),
            path: None,
        };
        assert_eq!(resolve("chrome", &dirs), Resolved::Unknown);
        assert!(command_names(&dirs).is_empty());
    }

    #[test]
    fn paths_and_odd_names() {
        let f = fixture();
        let p = make_cmd(&f.bin, "tool", None);
        assert_eq!(
            resolve(p.to_str().unwrap(), &f.dirs),
            Resolved::External(p.clone())
        );
        assert_eq!(resolve("..", &f.dirs), Resolved::Unknown);
        assert_eq!(resolve("", &f.dirs), Resolved::Unknown);
        assert_eq!(resolve("/no/such/file", &f.dirs), Resolved::Unknown);
    }

    #[test]
    fn dirs_from_vars() {
        let vars = |pairs: &'static [(&'static str, &'static str)]| {
            move |k: &str| {
                pairs
                    .iter()
                    .find(|(n, _)| *n == k)
                    .map(|(_, v)| OsString::from(v))
            }
        };
        let d = Dirs::from_vars(vars(&[("HOME", "/home/dhruv"), ("PATH", "/usr/bin")]));
        assert_eq!(
            d.user.as_deref(),
            Some(Path::new("/home/dhruv/.local/share/dos/commands"))
        );
        assert_eq!(d.system, Path::new(DEFAULT_SYSTEM_DIR));
        assert_eq!(d.path.as_deref(), Some(OsStr::new("/usr/bin")));

        let d = Dirs::from_vars(vars(&[
            ("HOME", "/home/dhruv"),
            ("DOS_USER_COMMANDS_DIR", "/tmp/u"),
            ("DOS_COMMANDS_DIR", "/tmp/s"),
        ]));
        assert_eq!(d.user.as_deref(), Some(Path::new("/tmp/u")));
        assert_eq!(d.system, Path::new("/tmp/s"));
        assert_eq!(d.path, None);

        let d = Dirs::from_vars(vars(&[("DOS_COMMANDS_DIR", "")]));
        assert_eq!(d.user, None);
        assert_eq!(d.system, Path::new(DEFAULT_SYSTEM_DIR));
    }

    #[test]
    fn child_path_puts_command_dirs_last() {
        let f = fixture();
        let joined = f.dirs.child_path();
        let parts: Vec<PathBuf> = std::env::split_paths(&joined).collect();
        assert_eq!(parts, [f.bin.clone(), f.user.clone(), f.system.clone()]);
    }
}
