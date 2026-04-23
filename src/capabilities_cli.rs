use clap::CommandFactory;

use agentchrome::capabilities::{CapabilitiesManifestListing, build_manifest};
use agentchrome::error::{AppError, ExitCode};

use crate::cli::{CapabilitiesArgs, Cli, GlobalOpts};
use crate::output::{self, print_output};

/// Build the `{subcommand_count, top_level_flags_count}` summary for a
/// `capabilities <command>` detail descriptor offloaded above the threshold.
fn summary_of_capabilities_detail(value: &serde_json::Value) -> serde_json::Value {
    let subcommand_count = value
        .get("subcommands")
        .and_then(serde_json::Value::as_array)
        .map(Vec::len);
    let top_level_flags_count = value
        .get("flags")
        .and_then(serde_json::Value::as_array)
        .map(Vec::len);

    serde_json::json!({
        "subcommand_count": subcommand_count,
        "top_level_flags_count": top_level_flags_count,
    })
}

pub fn execute_capabilities(global: &GlobalOpts, args: &CapabilitiesArgs) -> Result<(), AppError> {
    let cmd = Cli::command();
    let manifest = build_manifest(&cmd, args.compact);

    match &args.command {
        None => {
            // Progressive-disclosure listing — summaries only.
            let listing = CapabilitiesManifestListing::from(&manifest);
            print_output(&listing, &global.output)
        }
        Some(name) => {
            let available: Vec<String> = manifest.commands.iter().map(|c| c.name.clone()).collect();
            let Some(descriptor) = manifest.commands.iter().find(|c| c.name == *name) else {
                return Err(AppError {
                    message: format!(
                        "Unknown command: '{name}'. Available: {}",
                        available.join(", ")
                    ),
                    code: ExitCode::GeneralError,
                    custom_json: None,
                });
            };
            output::emit(descriptor, &global.output, "capabilities", |d| {
                summary_of_capabilities_detail(&serde_json::to_value(d).unwrap_or_default())
            })
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn global_opts() -> GlobalOpts {
        GlobalOpts {
            port: None,
            host: "127.0.0.1".into(),
            ws_url: None,
            timeout: None,
            tab: None,
            page_id: None,
            auto_dismiss_dialogs: false,
            config: None,
            keepalive_interval: None,
            no_keepalive: false,
            output: crate::cli::OutputFormat {
                json: false,
                pretty: false,
                plain: false,
                large_response_threshold: None,
            },
        }
    }

    #[test]
    fn execute_capabilities_unknown_command_returns_error() {
        let global = global_opts();
        let args = CapabilitiesArgs {
            command: Some("nonexistent".into()),
            compact: false,
        };
        let result = execute_capabilities(&global, &args);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.message.contains("Unknown command"));
        assert!(err.message.contains("nonexistent"));
    }

    #[test]
    fn unknown_command_returns_error_with_available_list() {
        let global = global_opts();
        let args = CapabilitiesArgs {
            command: Some("nonexistent".into()),
            compact: false,
        };
        let err = execute_capabilities(&global, &args).unwrap_err();
        assert!(err.message.contains("Unknown command"));
        let known = ["navigate", "tabs", "page", "dom", "interact"];
        let hit_count = known.iter().filter(|n| err.message.contains(*n)).count();
        assert!(
            hit_count >= 5,
            "expected ≥5 known commands listed in error: {}",
            err.message
        );
    }
}
