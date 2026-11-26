//! The DOS Shell: the `DOS>` prompt of Dhruv's Operating System.

pub mod builtins;
pub mod complete;
pub mod help;
pub mod lookup;
pub mod parse;
pub mod repl;
pub mod run;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
