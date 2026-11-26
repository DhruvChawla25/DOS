//! `help`: the built-ins plus every DOS command, with the `# help:` text from
//! the second line of each command file.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::{BufRead, BufReader, Read};
use std::path::Path;

use crate::builtins::Builtin;
use crate::lookup::{Dirs, executables_in};

pub const NO_DESCRIPTION: &str = "(no description)";

/// One line of `help`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub name: String,
    pub help: String,
}

/// Reads the `# help:` text from the second line of a command file.
/// Returns `None` if the file can't be read or has no help line there.
pub fn read_help_line(path: &Path) -> Option<String> {
    let file = File::open(path).ok()?;
    // Read raw bytes so a binary command doesn't break help.
    let mut reader = BufReader::new(file).take(4096);
    let mut buf = Vec::new();
    for _ in 0..2 {
        buf.clear();
        if reader.read_until(b'\n', &mut buf).ok()? == 0 {
            return None;
        }
    }
    let line = String::from_utf8_lossy(&buf);
    let text = line
        .trim()
        .strip_prefix('#')?
        .trim_start()
        .strip_prefix("help:")?;
    let text = text.trim();
    (!text.is_empty()).then(|| text.to_string())
}

/// Every command `help` lists, sorted by name. A user command hides a system
/// command with the same name, and built-ins hide both (the same order as
/// command lookup).
pub fn discover(dirs: &Dirs) -> Vec<Entry> {
    let mut map: BTreeMap<String, String> = BTreeMap::new();
    for b in Builtin::ALL {
        map.insert(b.name().to_string(), b.help().to_string());
    }
    for dir in dirs.command_dirs() {
        for (name, path) in executables_in(dir) {
            map.entry(name).or_insert_with(|| {
                read_help_line(&path).unwrap_or_else(|| NO_DESCRIPTION.to_string())
            });
        }
    }
    map.into_iter()
        .map(|(name, help)| Entry { name, help })
        .collect()
}

/// Formats entries as an aligned two-column list.
pub fn format(entries: &[Entry]) -> String {
    let width = entries
        .iter()
        .map(|e| e.name.chars().count())
        .max()
        .unwrap_or(0);
    let mut out = String::new();
    for e in entries {
        out.push_str(&format!("  {:<width$}  {}\n", e.name, e.help));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lookup::tests::{fixture, make_cmd};
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    fn find<'a>(entries: &'a [Entry], name: &str) -> Option<&'a Entry> {
        entries.iter().find(|e| e.name == name)
    }

    #[test]
    fn reads_the_second_line() {
        let f = fixture();
        let p = make_cmd(&f.system, "chrome", Some("Google Chrome"));
        assert_eq!(read_help_line(&p).as_deref(), Some("Google Chrome"));
    }

    #[test]
    fn help_line_variants() {
        let f = fixture();
        let p = f.system.join("x");
        for (body, want) in [
            ("#!/bin/sh\n#help:  tight  \n", Some("tight")),
            ("#!/bin/sh\n  # help: indented\r\n", Some("indented")),
            ("#!/bin/sh\n# help:\n", None),
            ("#!/bin/sh\necho hi\n# help: too late\n", None),
            ("# help: first line only\n", None),
            ("", None),
        ] {
            fs::write(&p, body).unwrap();
            assert_eq!(read_help_line(&p).as_deref(), want, "body {body:?}");
        }
        fs::write(&p, b"\x7fELF\x00\x01\xff\n\xfe\xfd\n").unwrap();
        assert_eq!(read_help_line(&p), None);
    }

    #[test]
    fn discovers_both_dirs_sorted_with_builtins() {
        let f = fixture();
        make_cmd(&f.system, "spotify", Some("Spotify"));
        make_cmd(&f.system, "chrome", Some("Google Chrome"));
        make_cmd(&f.user, "mytool", None);
        let entries = discover(&f.dirs);

        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        let mut sorted = names.clone();
        sorted.sort();
        assert_eq!(names, sorted);

        assert_eq!(find(&entries, "chrome").unwrap().help, "Google Chrome");
        assert_eq!(find(&entries, "spotify").unwrap().help, "Spotify");
        assert_eq!(find(&entries, "mytool").unwrap().help, NO_DESCRIPTION);
        for b in Builtin::ALL {
            assert_eq!(find(&entries, b.name()).unwrap().help, b.help());
        }
        assert_eq!(entries.len(), Builtin::ALL.len() + 3);
    }

    #[test]
    fn precedence_matches_lookup() {
        let f = fixture();
        make_cmd(&f.system, "chrome", Some("system chrome"));
        make_cmd(&f.user, "chrome", Some("user chrome"));
        make_cmd(&f.user, "help", Some("fake help"));
        let entries = discover(&f.dirs);
        assert_eq!(find(&entries, "chrome").unwrap().help, "user chrome");
        assert_eq!(find(&entries, "help").unwrap().help, Builtin::Help.help());
        assert_eq!(entries.iter().filter(|e| e.name == "chrome").count(), 1);
    }

    #[test]
    fn skips_non_executables_and_hidden_files() {
        let f = fixture();
        let p = make_cmd(&f.system, "readme", Some("not a command"));
        fs::set_permissions(&p, fs::Permissions::from_mode(0o644)).unwrap();
        make_cmd(&f.system, ".hidden", Some("hidden"));
        let entries = discover(&f.dirs);
        assert!(find(&entries, "readme").is_none());
        assert!(find(&entries, ".hidden").is_none());
    }

    #[test]
    fn format_aligns_columns() {
        let entries = vec![
            Entry {
                name: "cd".into(),
                help: "Change folder".into(),
            },
            Entry {
                name: "tlauncher".into(),
                help: "Minecraft".into(),
            },
        ];
        assert_eq!(
            format(&entries),
            "  cd         Change folder\n  tlauncher  Minecraft\n"
        );
    }
}
