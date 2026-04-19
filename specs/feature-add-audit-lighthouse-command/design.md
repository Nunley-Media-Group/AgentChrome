# Technical Design: Add `audit lighthouse` Command

**Issues**: #169
**Date**: 2026-03-16
**Status**: Draft
**Author**: Claude

---

## Architecture Overview

The `audit lighthouse` command follows the established command-group pattern used by `perf`, `tabs`, `cookie`, etc. It adds a new `audit` command group with a `lighthouse` subcommand that shells out to the external `lighthouse` CLI binary rather than using CDP directly.

```
CLI (clap) → main.rs dispatch → audit.rs → std::process::Command("lighthouse") → parse JSON → stdout
```

This is architecturally simpler than most commands (no CDP session needed for the audit itself), but still requires session/connection resolution to determine the Chrome port and optionally the active page URL.

---

## Component Design

### 1. CLI Layer (`src/cli/mod.rs`)

Add to the `Command` enum:

```rust
/// Run audits against the current page (Lighthouse)
Audit(AuditArgs),
```

New types:

```rust
pub struct AuditArgs {
    pub command: AuditCommand,
}

pub enum AuditCommand {
    /// Run a Google Lighthouse audit
    Lighthouse(AuditLighthouseArgs),
}

pub struct AuditLighthouseArgs {
    /// URL to audit (defaults to active page URL)
    pub url: Option<String>,
    /// Comma-separated list of categories to audit
    pub only: Option<String>,
    /// Path to save the full Lighthouse JSON report
    pub output_file: Option<PathBuf>,
}
```

### 2. Command Module (`src/audit.rs`)

New file following the pattern of `perf.rs`, `cookie.rs`, etc.

**Public entry point:**

```rust
pub async fn execute_audit(global: &GlobalOpts, args: &AuditArgs) -> Result<(), AppError>
```

**Internal flow:**

1. **Resolve connection** — `resolve_connection(host, port, ws_url)` to get the Chrome port
2. **Resolve URL** — If no positional URL arg, query `resolve_target()` + `Target.getTargets` to get the active page's URL
3. **Find lighthouse binary** — Use `which::which("lighthouse")` or `std::process::Command::new("which").arg("lighthouse")` to locate the binary. Since the project avoids adding dependencies unnecessarily, use a simple `PATH`-based lookup via `std::process::Command`.
4. **Build lighthouse command** — Construct `lighthouse <URL> --port <PORT> --output json --chrome-flags="--headless" --only-categories=<list>`
5. **Execute and capture output** — Run via `std::process::Command`, capture stdout/stderr
6. **Parse Lighthouse JSON** — Extract `lhr.categories[name].score` fields
7. **Format output** — Emit flat JSON scores summary to stdout
8. **Optionally save full report** — Write raw Lighthouse JSON to `--output-file`

### 3. Dispatch (`src/main.rs`)

Add match arm:

```rust
Command::Audit(args) => audit::execute_audit(&global, args).await,
```

Add module declaration:

```rust
mod audit;
```

### 4. Library Target (`src/lib.rs`)

No changes needed — `audit.rs` is a binary-crate command module like all others. The `lib.rs` only exposes shared infrastructure (`cdp`, `chrome`, `connection`, `session`, `error`).

---

## Data Flow

```
User invokes: agentchrome audit lighthouse [URL] [--only ...] [--output-file ...]
    │
    ▼
resolve_connection(host, port, ws_url) → ResolvedConnection { port }
    │
    ▼
[If no URL arg] resolve_target(host, port, tab, page_id) → TargetInfo { url }
    │
    ▼
Locate "lighthouse" binary in PATH
    │ Not found → AppError { "lighthouse binary not found...", code: 1 }
    ▼
Build command: lighthouse <URL> --port <PORT> --output json --chrome-flags="--headless"
    │ [If --only] append: --only-categories=performance,accessibility,...
    ▼
Execute std::process::Command, capture stdout + stderr + exit code
    │ Non-zero exit → AppError { stderr message, code: 1 }
    ▼
Parse stdout as JSON: lhr.categories.<name>.score
    │
    ▼
Build scores summary: {"url":"...","performance":0.91,"accessibility":0.87,...}
    │
    ├─[If --output-file] write raw lighthouse JSON to file
    ▼
Print scores summary JSON to stdout
```

---

## Lighthouse Binary Interaction

### Binary Discovery

Use a simple `PATH`-based lookup without adding external crates:

```rust
fn find_lighthouse_binary() -> Result<PathBuf, AppError> {
    // Try "lighthouse" in PATH using Command
    let output = std::process::Command::new("which")
        .arg("lighthouse")
        .output();
    // On Windows, use "where" instead
    // Parse output to get path, or return error with install hint
}
```

Cross-platform approach: attempt to run `lighthouse --version` and check if it succeeds. This is simpler and works across macOS, Linux, and Windows without `which`/`where` branching.

### Lighthouse CLI Arguments

```
lighthouse <URL> \
  --port <PORT> \
  --output json \
  --chrome-flags="--headless" \
  [--only-categories=performance,accessibility,best-practices,seo,pwa]
```

Key flags:
- `--port`: Connects to the existing Chrome instance managed by agentchrome
- `--output json`: Machine-readable output (the full Lighthouse Result object)
- `--chrome-flags="--headless"`: Required even if Chrome is already headless; Lighthouse uses this to configure its internal behavior
- `--only-categories`: Comma-separated category IDs to audit

### Output Parsing

Lighthouse JSON output structure (relevant subset):

```json
{
  "requestedUrl": "https://example.com",
  "finalUrl": "https://example.com",
  "categories": {
    "performance": { "score": 0.91 },
    "accessibility": { "score": 0.87 },
    "best-practices": { "score": 0.93 },
    "seo": { "score": 0.90 },
    "pwa": { "score": 0.30 }
  }
}
```

Extract `categories.<name>.score` for each category. Scores are `f64` in range `[0.0, 1.0]` or `null` (unmeasurable).

---

## Category Validation

Valid category names: `performance`, `accessibility`, `best-practices`, `seo`, `pwa`.

When `--only` is provided, validate each comma-separated value against this list before invoking Lighthouse. Return a structured error for invalid category names.

---

## Error Handling

| Condition | Error Message | Exit Code |
|-----------|--------------|-----------|
| `lighthouse` not in PATH | `"lighthouse binary not found. Install it with: npm install -g lighthouse"` | 1 (GeneralError) |
| No active session | Standard `AppError::no_session()` | 2 (ConnectionError) |
| Lighthouse exits non-zero | `"Lighthouse audit failed: <stderr>"` | 1 (GeneralError) |
| Invalid `--only` category | `"Invalid category: '<name>'. Valid categories: performance, accessibility, best-practices, seo, pwa"` | 1 (GeneralError) |
| Failed to parse Lighthouse output | `"Failed to parse Lighthouse output: <reason>"` | 1 (GeneralError) |
| Failed to write output file | Standard `AppError::file_write_failed()` | 1 (GeneralError) |

---

## Output Types

```rust
#[derive(Serialize)]
struct AuditLighthouseResult {
    url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    performance: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    accessibility: Option<f64>,
    #[serde(rename = "best-practices", skip_serializing_if = "Option::is_none")]
    best_practices: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    seo: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pwa: Option<f64>,
}
```

When `--only` is used, only the requested categories are populated; unrequested categories are `None` (omitted from JSON via `skip_serializing_if`). When a requested category has a `null` score from Lighthouse, the field is present as `null` — this requires a wrapper to distinguish `Some(None)` (requested but null) from `None` (not requested).

Revised approach using an explicit wrapper:

```rust
#[derive(Serialize)]
struct AuditLighthouseResult {
    url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    performance: Option<Option<f64>>,
    // ... same pattern for others
}
```

Or simpler: build the JSON object manually with `serde_json::Map` to control exactly which keys appear and whether values are `null` vs absent.

---

## Alternatives Considered

### 1. Use Lighthouse as a library (Node.js)

Rejected: Would require bundling Node.js or running a subprocess to a JS script. Shelling out to the `lighthouse` binary is simpler, more maintainable, and consistent with the tool's philosophy of composing existing CLI tools.

### 2. Implement audits via CDP directly

Rejected: Lighthouse performs hundreds of individual audits with complex scoring logic. Reimplementing this would be enormous and fragile. The `lighthouse` binary is the canonical implementation.

### 3. Add `lighthouse` as a Cargo dependency

Not possible: Lighthouse is a Node.js tool, not a Rust crate.

### 4. Use `which` crate for binary discovery

Rejected: Adds an external dependency for a simple PATH lookup. A `Command::new("lighthouse").arg("--version")` probe is sufficient and dependency-free.

---

## Testing Strategy

### BDD Tests (cucumber-rs)

- **CLI-testable** (no Chrome needed): argument validation, help text, `--only` with invalid categories, subcommand requirement
- **Chrome-dependent** (skipped in CI): full audit run, URL override, output file generation — verified via manual smoke test

### Unit Tests

- Category validation logic
- Lighthouse output JSON parsing
- Score extraction with null handling
- Output serialization (requested vs unrequested categories)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #169 | 2026-03-16 | Initial technical design |
