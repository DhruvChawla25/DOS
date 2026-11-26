//! Splitting a typed line into words.
//!
//! The rules are a small, predictable subset of POSIX shell quoting:
//!
//! - Words are separated by unquoted spaces and tabs.
//! - `'single quotes'` keep everything inside literally.
//! - `"double quotes"` keep everything literally except `\"`, `\\`, `\$` and
//!   `` \` ``, which drop the backslash.
//! - A backslash outside quotes makes the next character literal.
//! - An unquoted `~` or `~/...` at the start of a word becomes `$HOME`.
//!
//! Anything that needs a real shell (pipes, redirects, globs, variables,
//! `;`, `&&` and so on, outside quotes) is reported as [`Parsed::Shell`], and
//! the caller hands the whole line to bash.

use std::fmt;

/// The result of parsing one line.
#[derive(Debug, PartialEq, Eq)]
pub enum Parsed {
    /// Nothing but whitespace.
    Empty,
    /// Plain words: the command name, then its arguments.
    Words(Vec<String>),
    /// The line uses shell syntax. `words` is the plain split, so the caller
    /// can still look at the command name.
    Shell { words: Vec<String> },
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseError {
    UnclosedQuote(char),
    TrailingBackslash,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::UnclosedQuote(q) => write!(f, "missing closing {q}"),
            ParseError::TrailingBackslash => write!(f, "line ends with a backslash"),
        }
    }
}

/// Characters that mean "this line needs a real shell" when unquoted.
const SHELL_CHARS: &[char] = &[
    '|', '&', ';', '<', '>', '(', ')', '$', '`', '*', '?', '[', '{',
];

/// Splits `line` into words. `home` is used for `~` expansion.
pub fn parse(line: &str, home: Option<&str>) -> Result<Parsed, ParseError> {
    let mut words = Vec::new();
    let mut cur = String::new();
    // True once the current word has started, so `''` gives an empty word.
    let mut in_word = false;
    let mut needs_shell = false;
    let mut chars = line.chars().peekable();

    while let Some(c) = chars.next() {
        match c {
            ' ' | '\t' | '\n' | '\r' => {
                if in_word {
                    words.push(std::mem::take(&mut cur));
                    in_word = false;
                }
            }
            '\'' => {
                in_word = true;
                loop {
                    match chars.next() {
                        Some('\'') => break,
                        Some(ch) => cur.push(ch),
                        None => return Err(ParseError::UnclosedQuote('\'')),
                    }
                }
            }
            '"' => {
                in_word = true;
                loop {
                    match chars.next() {
                        Some('"') => break,
                        Some('\\') => match chars.next() {
                            Some(ch @ ('"' | '\\' | '$' | '`')) => cur.push(ch),
                            Some(ch) => {
                                cur.push('\\');
                                cur.push(ch);
                            }
                            None => return Err(ParseError::UnclosedQuote('"')),
                        },
                        Some(ch) => {
                            if ch == '$' || ch == '`' {
                                needs_shell = true;
                            }
                            cur.push(ch);
                        }
                        None => return Err(ParseError::UnclosedQuote('"')),
                    }
                }
            }
            '\\' => match chars.next() {
                Some(ch) => {
                    in_word = true;
                    cur.push(ch);
                }
                None => return Err(ParseError::TrailingBackslash),
            },
            '~' if !in_word => {
                in_word = true;
                let at_end = matches!(chars.peek(), None | Some(' ' | '\t' | '/'));
                match home {
                    Some(h) if at_end => cur.push_str(h),
                    _ => cur.push('~'),
                }
            }
            '#' if !in_word => {
                // A comment, as in any shell.
                break;
            }
            _ => {
                if SHELL_CHARS.contains(&c) {
                    needs_shell = true;
                }
                in_word = true;
                cur.push(c);
            }
        }
    }
    if in_word {
        words.push(cur);
    }

    Ok(if words.is_empty() && !needs_shell {
        Parsed::Empty
    } else if needs_shell {
        Parsed::Shell { words }
    } else {
        Parsed::Words(words)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(line: &str) -> Vec<String> {
        match parse(line, Some("/home/dhruv")).unwrap() {
            Parsed::Words(w) => w,
            other => panic!("expected words for {line:?}, got {other:?}"),
        }
    }

    fn needs_shell(line: &str) -> bool {
        matches!(parse(line, None).unwrap(), Parsed::Shell { .. })
    }

    #[test]
    fn empty_and_blank_lines() {
        assert_eq!(parse("", None).unwrap(), Parsed::Empty);
        assert_eq!(parse("   \t ", None).unwrap(), Parsed::Empty);
        assert_eq!(parse("  # just a comment", None).unwrap(), Parsed::Empty);
    }

    #[test]
    fn splits_on_whitespace() {
        assert_eq!(words("chrome"), ["chrome"]);
        assert_eq!(
            words("  install   --flatpak\tvlc  "),
            ["install", "--flatpak", "vlc"]
        );
    }

    #[test]
    fn single_quotes_are_literal() {
        assert_eq!(words("echo 'a  b' 'c\\d'"), ["echo", "a  b", "c\\d"]);
        assert_eq!(words("echo 'it''s'"), ["echo", "its"]);
    }

    #[test]
    fn double_quotes_and_escapes() {
        assert_eq!(
            words(r#"win install "My Setup.exe""#),
            ["win", "install", "My Setup.exe"]
        );
        assert_eq!(
            words(r#"echo "say \"hi\" \\ \n""#),
            ["echo", r#"say "hi" \ \n"#]
        );
    }

    #[test]
    fn backslash_outside_quotes() {
        assert_eq!(words(r"ls My\ Music"), ["ls", "My Music"]);
        assert_eq!(words(r"echo \#not-a-comment"), ["echo", "#not-a-comment"]);
    }

    #[test]
    fn empty_quoted_argument_is_kept() {
        assert_eq!(words("cmd '' \"\""), ["cmd", "", ""]);
    }

    #[test]
    fn quotes_join_with_neighbours() {
        assert_eq!(words(r#"a"b c"d'e f'"#), ["ab cde f"]);
    }

    #[test]
    fn tilde_expansion() {
        assert_eq!(
            words("ls ~ ~/Music"),
            ["ls", "/home/dhruv", "/home/dhruv/Music"]
        );
        assert_eq!(words("echo a~ '~' ~user"), ["echo", "a~", "~", "~user"]);
        assert_eq!(
            parse("ls ~", None).unwrap(),
            Parsed::Words(vec!["ls".into(), "~".into()])
        );
    }

    #[test]
    fn comments() {
        assert_eq!(words("help # show commands"), ["help"]);
        assert_eq!(words("echo a#b"), ["echo", "a#b"]);
    }

    #[test]
    fn unclosed_quotes_are_errors() {
        assert_eq!(
            parse("echo 'abc", None),
            Err(ParseError::UnclosedQuote('\''))
        );
        assert_eq!(
            parse("echo \"abc", None),
            Err(ParseError::UnclosedQuote('"'))
        );
        assert_eq!(
            parse("echo abc\\", None),
            Err(ParseError::TrailingBackslash)
        );
    }

    #[test]
    fn shell_syntax_is_detected() {
        assert!(needs_shell("ls | less"));
        assert!(needs_shell("ls *.txt"));
        assert!(needs_shell("echo $HOME"));
        assert!(needs_shell("echo \"$HOME\""));
        assert!(needs_shell("make && make install"));
        assert!(needs_shell("echo hi > out.txt"));
        assert!(!needs_shell("echo '$HOME | *'"));
        assert!(!needs_shell("echo \\*"));
        assert!(!needs_shell("echo \"a | b\""));
    }

    #[test]
    fn shell_lines_keep_the_command_name() {
        match parse("ls -l | wc", None).unwrap() {
            Parsed::Shell { words } => assert_eq!(words[0], "ls"),
            other => panic!("{other:?}"),
        }
    }
}
