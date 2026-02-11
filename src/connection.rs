use crate::chrome::{TargetInfo, discover_chrome, query_targets, query_version};
use crate::error::AppError;
use crate::session;

/// Resolved connection info ready for use by a command.
#[derive(Debug)]
#[allow(dead_code)]
pub struct ResolvedConnection {
    pub ws_url: String,
    pub host: String,
    pub port: u16,
}

/// Health-check a connection by querying `/json/version`.
///
/// Returns `Ok(())` if Chrome responds, or `Err(AppError::stale_session())` if not.
///
/// # Errors
///
/// Returns `AppError` with `ConnectionError` exit code if Chrome is unreachable.
pub async fn health_check(host: &str, port: u16) -> Result<(), AppError> {
    query_version(host, port)
        .await
        .map(|_| ())
        .map_err(|_| AppError::stale_session())
}

/// Resolve a Chrome connection using the priority chain:
///
/// 1. Explicit `--ws-url`
/// 2. Session file (with health check)
/// 3. Auto-discover (default host:port)
/// 4. Error with suggestion
///
/// # Errors
///
/// Returns `AppError` if no Chrome connection can be resolved.
#[allow(dead_code)]
pub async fn resolve_connection(
    host: &str,
    port: u16,
    ws_url: Option<&str>,
) -> Result<ResolvedConnection, AppError> {
    // 1. Explicit --ws-url
    if let Some(ws_url) = ws_url {
        let resolved_port = extract_port_from_ws_url(ws_url).unwrap_or(port);
        return Ok(ResolvedConnection {
            ws_url: ws_url.to_string(),
            host: host.to_string(),
            port: resolved_port,
        });
    }

    // 2. Session file
    if let Some(session_data) = session::read_session()? {
        health_check(host, session_data.port).await?;
        return Ok(ResolvedConnection {
            ws_url: session_data.ws_url,
            host: host.to_string(),
            port: session_data.port,
        });
    }

    // 3. Auto-discover
    match discover_chrome(host, port).await {
        Ok((ws_url, port)) => Ok(ResolvedConnection {
            ws_url,
            host: host.to_string(),
            port,
        }),
        Err(_) => Err(AppError::no_chrome_found()),
    }
}

/// Extract port from a WebSocket URL like `ws://host:port/path`.
#[must_use]
pub fn extract_port_from_ws_url(url: &str) -> Option<u16> {
    let without_scheme = url
        .strip_prefix("ws://")
        .or_else(|| url.strip_prefix("wss://"))?;
    let host_port = without_scheme.split('/').next()?;
    let port_str = host_port.rsplit(':').next()?;
    port_str.parse().ok()
}

/// Select a target from a list based on the `--tab` option.
///
/// - `None` → first target with `target_type == "page"`
/// - `Some(value)` → try as numeric index, then as target ID
///
/// This is a pure function for testability.
///
/// # Errors
///
/// Returns `AppError::no_page_targets()` if no page-type target exists,
/// or `AppError::target_not_found()` if the specified tab cannot be matched.
#[allow(dead_code)]
pub fn select_target<'a>(
    targets: &'a [TargetInfo],
    tab: Option<&str>,
) -> Result<&'a TargetInfo, AppError> {
    match tab {
        None => targets
            .iter()
            .find(|t| t.target_type == "page")
            .ok_or_else(AppError::no_page_targets),
        Some(value) => {
            // Try as numeric index first
            if let Ok(index) = value.parse::<usize>() {
                return targets
                    .get(index)
                    .ok_or_else(|| AppError::target_not_found(value));
            }
            // Try as target ID
            targets
                .iter()
                .find(|t| t.id == value)
                .ok_or_else(|| AppError::target_not_found(value))
        }
    }
}

/// Resolve the target tab from the `--tab` option by querying Chrome for targets.
///
/// # Errors
///
/// Returns `AppError` if targets cannot be queried or the specified tab is not found.
#[allow(dead_code)]
pub async fn resolve_target(
    host: &str,
    port: u16,
    tab: Option<&str>,
) -> Result<TargetInfo, AppError> {
    let targets = query_targets(host, port).await?;
    select_target(&targets, tab).cloned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_target(id: &str, target_type: &str) -> TargetInfo {
        TargetInfo {
            id: id.to_string(),
            target_type: target_type.to_string(),
            title: format!("Title {id}"),
            url: format!("https://example.com/{id}"),
            ws_debugger_url: Some(format!("ws://127.0.0.1:9222/devtools/page/{id}")),
        }
    }

    #[test]
    fn extract_port_ws() {
        assert_eq!(
            extract_port_from_ws_url("ws://127.0.0.1:9222/devtools/browser/abc"),
            Some(9222)
        );
    }

    #[test]
    fn extract_port_wss() {
        assert_eq!(
            extract_port_from_ws_url("wss://localhost:9333/devtools/browser/abc"),
            Some(9333)
        );
    }

    #[test]
    fn extract_port_no_scheme() {
        assert_eq!(extract_port_from_ws_url("http://localhost:9222"), None);
    }

    #[test]
    fn select_target_default_picks_first_page() {
        let targets = vec![
            make_target("bg1", "background_page"),
            make_target("page1", "page"),
            make_target("page2", "page"),
        ];
        let result = select_target(&targets, None).unwrap();
        assert_eq!(result.id, "page1");
    }

    #[test]
    fn select_target_default_skips_non_page() {
        let targets = vec![
            make_target("sw1", "service_worker"),
            make_target("p1", "page"),
        ];
        let result = select_target(&targets, None).unwrap();
        assert_eq!(result.id, "p1");
    }

    #[test]
    fn select_target_by_index() {
        let targets = vec![
            make_target("a", "page"),
            make_target("b", "page"),
            make_target("c", "page"),
        ];
        let result = select_target(&targets, Some("1")).unwrap();
        assert_eq!(result.id, "b");
    }

    #[test]
    fn select_target_by_id() {
        let targets = vec![make_target("ABCDEF", "page"), make_target("GHIJKL", "page")];
        let result = select_target(&targets, Some("GHIJKL")).unwrap();
        assert_eq!(result.id, "GHIJKL");
    }

    #[test]
    fn select_target_invalid_tab() {
        let targets = vec![make_target("a", "page")];
        let result = select_target(&targets, Some("nonexistent"));
        assert!(result.is_err());
        assert!(result.unwrap_err().message.contains("not found"));
    }

    #[test]
    fn select_target_index_out_of_bounds() {
        let targets = vec![make_target("a", "page")];
        let result = select_target(&targets, Some("5"));
        assert!(result.is_err());
    }

    #[test]
    fn select_target_empty_list_no_tab() {
        let targets: Vec<TargetInfo> = vec![];
        let result = select_target(&targets, None);
        assert!(result.is_err());
        assert!(result.unwrap_err().message.contains("No page targets"));
    }

    #[test]
    fn select_target_no_page_targets() {
        let targets = vec![
            make_target("sw1", "service_worker"),
            make_target("bg1", "background_page"),
        ];
        let result = select_target(&targets, None);
        assert!(result.is_err());
    }
}
