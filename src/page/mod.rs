mod element;
mod find;
mod screenshot;
mod snapshot;
mod text;
pub(crate) mod wait;

use std::time::Duration;

use serde::Serialize;

use agentchrome::cdp::{CdpClient, CdpConfig};
use agentchrome::connection::{ManagedSession, resolve_connection, resolve_target};
use agentchrome::error::{AppError, ExitCode};

use crate::cli::{GlobalOpts, PageArgs, PageCommand, PageResizeArgs};
use crate::emulate::apply_emulate_state;

// =============================================================================
// Output formatting
// =============================================================================

fn print_output(value: &impl Serialize, output: &crate::cli::OutputFormat) -> Result<(), AppError> {
    let json = if output.pretty {
        serde_json::to_string_pretty(value)
    } else {
        serde_json::to_string(value)
    };
    let json = json.map_err(|e| AppError {
        message: format!("serialization error: {e}"),
        code: ExitCode::GeneralError,
        custom_json: None,
    })?;
    println!("{json}");
    Ok(())
}

// =============================================================================
// Config helper
// =============================================================================

fn cdp_config(global: &GlobalOpts) -> CdpConfig {
    let mut config = CdpConfig::default();
    if let Some(timeout_ms) = global.timeout {
        config.command_timeout = Duration::from_millis(timeout_ms);
    }
    config
}

// =============================================================================
// Session setup
// =============================================================================

async fn setup_session(global: &GlobalOpts) -> Result<(CdpClient, ManagedSession), AppError> {
    let conn = resolve_connection(&global.host, global.port, global.ws_url.as_deref()).await?;
    let target = resolve_target(
        &conn.host,
        conn.port,
        global.tab.as_deref(),
        global.page_id.as_deref(),
    )
    .await?;

    let config = cdp_config(global);
    let client = CdpClient::connect(&conn.ws_url, config).await?;
    let session = client.create_session(&target.id).await?;
    let mut managed = ManagedSession::new(session);
    apply_emulate_state(&mut managed).await?;
    managed.install_dialog_interceptors().await;

    Ok((client, managed))
}

// =============================================================================
// Page info helper
// =============================================================================

async fn get_page_info(managed: &ManagedSession) -> Result<(String, String), AppError> {
    let url_result = managed
        .send_command(
            "Runtime.evaluate",
            Some(serde_json::json!({ "expression": "location.href" })),
        )
        .await?;

    let title_result = managed
        .send_command(
            "Runtime.evaluate",
            Some(serde_json::json!({ "expression": "document.title" })),
        )
        .await?;

    let url = url_result["result"]["value"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let title = title_result["result"]["value"]
        .as_str()
        .unwrap_or_default()
        .to_string();

    Ok((url, title))
}

// =============================================================================
// Viewport dimensions helper (shared by screenshot + element)
// =============================================================================

/// Get the current viewport dimensions via `Runtime.evaluate`.
async fn get_viewport_dimensions(managed: &ManagedSession) -> Result<(u32, u32), AppError> {
    let result = managed
        .send_command(
            "Runtime.evaluate",
            Some(serde_json::json!({
                "expression": "JSON.stringify({ width: window.innerWidth, height: window.innerHeight })",
                "returnByValue": true,
            })),
        )
        .await
        .map_err(|e| {
            AppError::screenshot_failed(&format!("Failed to get viewport dimensions: {e}"))
        })?;

    let value_str = result["result"]["value"]
        .as_str()
        .ok_or_else(|| AppError::screenshot_failed("Failed to read viewport dimensions"))?;
    let dims: serde_json::Value = serde_json::from_str(value_str).map_err(|e| {
        AppError::screenshot_failed(&format!("Failed to parse viewport dimensions: {e}"))
    })?;

    #[allow(clippy::cast_possible_truncation)]
    let width = dims["width"].as_u64().unwrap_or(1280) as u32;
    #[allow(clippy::cast_possible_truncation)]
    let height = dims["height"].as_u64().unwrap_or(720) as u32;

    Ok((width, height))
}

// =============================================================================
// Dispatcher
// =============================================================================

/// Execute the `page` subcommand group.
///
/// # Errors
///
/// Returns `AppError` if the subcommand fails.
pub async fn execute_page(global: &GlobalOpts, args: &PageArgs) -> Result<(), AppError> {
    let frame = args.frame.as_deref();
    match &args.command {
        PageCommand::Text(text_args) => text::execute_text(global, text_args, frame).await,
        PageCommand::Snapshot(snap_args) => {
            snapshot::execute_snapshot(global, snap_args, frame).await
        }
        PageCommand::Find(find_args) => find::execute_find(global, find_args, frame).await,
        PageCommand::Screenshot(ss_args) => {
            screenshot::execute_screenshot(global, ss_args, frame).await
        }
        PageCommand::Resize(resize_args) => execute_page_resize(global, resize_args).await,
        PageCommand::Element(elem_args) => element::execute_element(global, elem_args, frame).await,
        PageCommand::Wait(wait_args) => wait::execute_wait(global, wait_args, frame).await,
        PageCommand::Frames => execute_frames(global).await,
        PageCommand::Workers => execute_workers(global).await,
    }
}

async fn execute_frames(global: &GlobalOpts) -> Result<(), AppError> {
    let (_client, mut managed) = setup_session(global).await?;
    let frames = agentchrome::frame::list_frames(&mut managed).await?;
    print_output(&frames, &global.output)?;
    Ok(())
}

#[derive(Serialize)]
struct WorkerInfo {
    index: u32,
    id: String,
    #[serde(rename = "type")]
    worker_type: String,
    url: String,
    status: String,
}

async fn execute_workers(global: &GlobalOpts) -> Result<(), AppError> {
    let (client, _managed) = setup_session(global).await?;
    let result = client
        .send_command("Target.getTargets", None)
        .await
        .map_err(|e| AppError {
            message: format!("Failed to enumerate targets: {e}"),
            code: ExitCode::ProtocolError,
            custom_json: None,
        })?;

    let empty = Vec::new();
    let targets = result["targetInfos"].as_array().unwrap_or(&empty);

    #[allow(clippy::cast_possible_truncation)]
    let workers: Vec<WorkerInfo> = targets
        .iter()
        .filter(|t| {
            matches!(
                t["type"].as_str(),
                Some("service_worker" | "shared_worker" | "worker")
            )
        })
        .enumerate()
        .map(|(i, t)| WorkerInfo {
            index: i as u32,
            id: t["targetId"].as_str().unwrap_or_default().to_string(),
            worker_type: t["type"].as_str().unwrap_or("worker").to_string(),
            url: t["url"].as_str().unwrap_or_default().to_string(),
            status: worker_status(t),
        })
        .collect();

    print_output(&workers, &global.output)?;
    Ok(())
}

fn worker_status(target: &serde_json::Value) -> String {
    // CDP Target.getTargets doesn't directly provide lifecycle state.
    // Use `attached` as a proxy and fall back to a reasonable default.
    if target["attached"].as_bool() == Some(true) {
        "attached".to_string()
    } else {
        match target["type"].as_str() {
            Some("service_worker") => "activated".to_string(),
            _ => "running".to_string(),
        }
    }
}

async fn execute_page_resize(global: &GlobalOpts, args: &PageResizeArgs) -> Result<(), AppError> {
    crate::emulate::execute_resize(global, &args.size).await
}
