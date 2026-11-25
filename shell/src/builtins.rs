//! The built-in commands: their names and help text.
//! What they do lives in `main.rs`, next to the prompt they talk to.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Builtin {
    Help,
    Clear,
    History,
    Version,
    Wifi,
    Update,
    Sh,
    Cd,
    Shutdown,
    Reboot,
    Exit,
}

impl Builtin {
    pub const ALL: &[Builtin] = &[
        Builtin::Help,
        Builtin::Clear,
        Builtin::History,
        Builtin::Version,
        Builtin::Wifi,
        Builtin::Update,
        Builtin::Sh,
        Builtin::Cd,
        Builtin::Shutdown,
        Builtin::Reboot,
        Builtin::Exit,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Builtin::Help => "help",
            Builtin::Clear => "clear",
            Builtin::History => "history",
            Builtin::Version => "version",
            Builtin::Wifi => "wifi",
            Builtin::Update => "update",
            Builtin::Sh => "sh",
            Builtin::Cd => "cd",
            Builtin::Shutdown => "shutdown",
            Builtin::Reboot => "reboot",
            Builtin::Exit => "exit",
        }
    }

    pub fn help(self) -> &'static str {
        match self {
            Builtin::Help => "List DOS commands (help <command> for one)",
            Builtin::Clear => "Clear the screen",
            Builtin::History => "Show the commands you typed (history clear wipes it)",
            Builtin::Version => "Show the DOS Shell version",
            Builtin::Wifi => "Connect to Wi-Fi (nmtui)",
            Builtin::Update => "Update DOS (dos-update)",
            Builtin::Sh => "Open a bash shell; type exit to come back",
            Builtin::Cd => "Change the current folder",
            Builtin::Shutdown => "Power off the laptop",
            Builtin::Reboot => "Restart the laptop",
            Builtin::Exit => "Leave DOS (closes the display)",
        }
    }

    pub fn from_name(name: &str) -> Option<Builtin> {
        Builtin::ALL.iter().copied().find(|b| b.name() == name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip() {
        for b in Builtin::ALL {
            assert_eq!(Builtin::from_name(b.name()), Some(*b));
            assert!(!b.help().is_empty());
        }
        assert_eq!(Builtin::from_name("chrome"), None);
        assert_eq!(Builtin::from_name("HELP"), None);
    }

    #[test]
    fn required_builtins_exist() {
        for n in [
            "help", "clear", "history", "version", "wifi", "update", "sh", "shutdown", "reboot",
            "exit",
        ] {
            assert!(Builtin::from_name(n).is_some(), "missing built-in {n}");
        }
    }
}
