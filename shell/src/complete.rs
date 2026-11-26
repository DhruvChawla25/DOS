//! Tab completion: command names for the first word, file names after that.

use std::collections::BTreeSet;

use rustyline::completion::{Completer, FilenameCompleter, Pair};
use rustyline::highlight::Highlighter;
use rustyline::hint::Hinter;
use rustyline::validate::Validator;
use rustyline::{Context, Helper};

use crate::builtins::Builtin;
use crate::lookup::{self, Dirs};

pub struct DosHelper {
    pub dirs: Dirs,
    files: FilenameCompleter,
}

impl DosHelper {
    pub fn new(dirs: Dirs) -> Self {
        DosHelper {
            dirs,
            files: FilenameCompleter::new(),
        }
    }
}

/// Command names starting with `prefix`: built-ins and DOS commands first;
/// only if none match, programs on `PATH`.
pub fn command_candidates(prefix: &str, dirs: &Dirs) -> Vec<String> {
    let mut set: BTreeSet<String> = Builtin::ALL
        .iter()
        .map(|b| b.name().to_string())
        .chain(lookup::command_names(dirs))
        .filter(|n| n.starts_with(prefix))
        .collect();
    if set.is_empty()
        && !prefix.is_empty()
        && let Some(path) = &dirs.path
    {
        for dir in std::env::split_paths(path) {
            set.extend(
                lookup::executables_in(&dir)
                    .into_iter()
                    .map(|(n, _)| n)
                    .filter(|n| n.starts_with(prefix)),
            );
        }
    }
    set.into_iter().collect()
}

impl Completer for DosHelper {
    type Candidate = Pair;

    fn complete(
        &self,
        line: &str,
        pos: usize,
        ctx: &Context<'_>,
    ) -> rustyline::Result<(usize, Vec<Pair>)> {
        let before = &line[..pos];
        let start = before.len() - before.trim_start().len();
        let first_word = &before[start..];
        if first_word.contains(char::is_whitespace) || first_word.contains('/') {
            return self.files.complete(line, pos, ctx);
        }
        let pairs = command_candidates(first_word, &self.dirs)
            .into_iter()
            .map(|n| Pair {
                display: n.clone(),
                replacement: format!("{n} "),
            })
            .collect();
        Ok((start, pairs))
    }
}

impl Hinter for DosHelper {
    type Hint = String;
}
impl Highlighter for DosHelper {}
impl Validator for DosHelper {}
impl Helper for DosHelper {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lookup::tests::{fixture, make_cmd};

    #[test]
    fn completes_builtins_and_commands() {
        let f = fixture();
        make_cmd(&f.system, "chrome", None);
        make_cmd(&f.user, "chrome", None);
        make_cmd(&f.user, "clock", None);
        make_cmd(&f.bin, "cheese", None);
        assert_eq!(
            command_candidates("c", &f.dirs),
            ["cd", "chrome", "clear", "clock"]
        );
        assert_eq!(command_candidates("ver", &f.dirs), ["version"]);
    }

    #[test]
    fn falls_back_to_path() {
        let f = fixture();
        make_cmd(&f.bin, "htop", None);
        assert_eq!(command_candidates("ht", &f.dirs), ["htop"]);
        assert!(command_candidates("zzz", &f.dirs).is_empty());
    }
}
