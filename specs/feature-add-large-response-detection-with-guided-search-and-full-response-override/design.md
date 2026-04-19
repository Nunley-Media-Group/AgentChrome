# Design: Large Response Detection with Temp File Output

**Issues**: #168, #177
**Date**: 2026-03-13
**Status**: Draft
**Author**: AI (nmg-sdlc)

---

## Overview

This feature provides a unified output gate that intercepts serialized JSON before it reaches stdout, compares its byte length against a configurable threshold (default 16 KB), and either passes it through or writes it to a temp file.

The original design (#168) introduced a guidance object + `--search`/`--full-response` flags requiring agents to re-invoke commands. Issue #177 simplifies this: when output exceeds the threshold, the full JSON is written to a UUID-named temp file in the OS temp directory, and stdout receives a small output object containing the file path, size, command name, and a command-specific summary. The agent reads the file directly — single-step, no re-invocation.

The existing `src/output.rs` module is refactored: `LargeResponseGuidance` is replaced by `TempFileOutput`, `emit()` is updated to write to a temp file instead of printing a guidance object, and `emit_searched()` is removed. The `--search` per-command flags and `--full-response` global flag are removed from the CLI. The `build_guidance_text()` and `command_specific_guidance()` helper functions are removed.

The key architectural principle remains **serialize once, check once, act once**: the output is serialized to a JSON string, the byte length is checked against the threshold, and either the original string is printed inline or written to a temp file with a reference object printed to stdout.

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLI Layer                                │
│  GlobalOpts { OutputFormat { threshold, ... } }                  │
│  (--search and --full-response REMOVED)                         │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Command Modules                              │
│  page/snapshot.rs, page/text.rs, js.rs, network.rs              │
│                                                                  │
│  1. Execute CDP commands, produce typed result                   │
│  2. If --plain: delegate to output::emit_plain() (NEW)          │
│  3. Call output::emit() with typed result + summary generator    │
│     (search filtering removed from all commands)                 │
└──────────────────────────┬──────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────────┐
│                    output.rs (MODIFIED)                           │
│                                                                  │
│  emit(value, output_format, command_name, summary_fn)            │
│    1. Serialize value to JSON string                             │
│    2. Determine effective threshold                              │
│    3. If len <= threshold: print JSON string, return             │
│    4. Generate UUID filename                                     │
│    5. Write JSON string to temp file                             │
│    6. Build TempFileOutput object                                │
│    7. Serialize and print output object to stdout                │
│                                                                  │
│  emit_plain(text, output_format)                                 │
│    1. If len <= threshold: print text, return                    │
│    2. Write text to temp file (.txt)                             │
│    3. Print file path to stdout as plain text                    │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. CLI parses args → GlobalOpts (with threshold) + command Args (no --search)
2. Config loaded → threshold merged (CLI > config > default 16384)
3. Command module executes CDP calls → produces typed result (e.g., SnapshotNode)
4. If --plain: command calls output::emit_plain(&text, &output_format)
   a. If len <= threshold: print text, return
   b. Else: write text to {temp_dir}/agentchrome-{uuid}.txt, print path to stdout
5. Command calls output::emit(&result, &output_format, "page snapshot", summary_fn)
6. output::emit() serializes result to JSON string
7. If byte_len <= threshold: print JSON string
8. Else: write JSON to {temp_dir}/agentchrome-{uuid}.json → print TempFileOutput object
```

---

## API / Interface Changes

### Removed Global CLI Flags

| Flag | Status | Notes |
|------|--------|-------|
| `--full-response` | **REMOVED** | No longer needed — full data is always in the temp file |
| `--search` (per-command) | **REMOVED** | Removed from all 5 commands |

### Retained Global CLI Flags

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--large-response-threshold` | usize | `16384` | Byte threshold for triggering temp file output |

### Removed Per-Command Flags

| Command | Flag Removed |
|---------|-------------|
| `page snapshot` | `--search` |
| `page text` | `--search` |
| `js exec` | `--search` |
| `network list` | `--search` |
| `network get` | `--search` |

### CLI Struct Changes

```rust
// src/cli/mod.rs — OutputFormat (modified)
#[derive(Args)]
pub struct OutputFormat {
    /// Output as compact JSON (mutually exclusive with --pretty, --plain)
    #[arg(long, global = true, conflicts_with_all = ["pretty", "plain"])]
    pub json: bool,

    /// Output as pretty-printed JSON (mutually exclusive with --json, --plain)
    #[arg(long, global = true, conflicts_with_all = ["json", "plain"])]
    pub pretty: bool,

    /// Output as human-readable plain text (mutually exclusive with --json, --pretty)
    #[arg(long, global = true, conflicts_with_all = ["json", "pretty"])]
    pub plain: bool,

    // REMOVED: pub full_response: bool,

    /// Byte threshold for large-response detection (default: 16384)
    #[arg(long, global = true, value_parser = parse_nonzero_usize)]
    pub large_response_threshold: Option<usize>,
}
```

### Per-Command Args Changes

```rust
// Example: src/cli/mod.rs — PageSnapshotArgs (modified)
#[derive(Args)]
pub struct PageSnapshotArgs {
    // REMOVED: pub search: Option<String>,
    // ... remaining fields unchanged
}

// Same pattern for PageTextArgs, JsExecArgs, NetworkListArgs, NetworkGetArgs
```

### Temp File Output Object Schema

```rust
// src/output.rs (replaces LargeResponseGuidance)
#[derive(Serialize)]
pub struct TempFileOutput {
    pub output_file: String,           // absolute path to temp file
    pub size_bytes: u64,               // byte count of the written file
    pub command: String,               // e.g., "page snapshot"
    pub summary: serde_json::Value,    // command-specific metadata
}
```

**Example output (JSON mode):**

```json
{
  "output_file": "/tmp/agentchrome-a1b2c3d4-e5f6-7890-abcd-ef1234567890.json",
  "size_bytes": 536576,
  "command": "page snapshot",
  "summary": {
    "total_nodes": 8500,
    "top_roles": ["main", "navigation", "complementary"]
  }
}
```

**Example output (plain mode):**

```
/tmp/agentchrome-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt
```

### Config File Key (Unchanged)

```toml
[output]
large_response_threshold = 16384
```

### Command-Specific Summary Schemas (Unchanged)

| Command | Summary Fields | Example |
|---------|---------------|---------|
| `page snapshot` | `total_nodes`, `top_roles` | `{"total_nodes": 8500, "top_roles": ["main", "navigation"]}` |
| `page text` | `character_count`, `line_count` | `{"character_count": 45000, "line_count": 1200}` |
| `js exec` | `result_type`, `size_bytes` | `{"result_type": "object", "size_bytes": 32000}` |
| `network list` | `request_count`, `methods`, `domains` | `{"request_count": 150, "methods": ["GET", "POST"], "domains": ["api.example.com"]}` |
| `network get` | `url`, `status`, `content_type`, `body_size_bytes` | `{"url": "https://...", "status": 200, "content_type": "application/json", "body_size_bytes": 50000}` |

---

## Module Changes: `src/output.rs`

### Removed

- `LargeResponseGuidance` struct
- `emit_searched()` function
- `build_guidance_text()` function
- `command_specific_guidance()` function
- All tests for guidance text building and `emit_searched`

### Added

- `TempFileOutput` struct (replaces `LargeResponseGuidance`)
- `write_temp_file()` helper — writes content to `{temp_dir}/agentchrome-{uuid}.json`
- `emit_plain()` function — handles `--plain` mode with temp file support

### Modified: `emit()` function

```rust
pub fn emit<T, F>(
    value: &T,
    output: &OutputFormat,
    command_name: &str,
    summary_fn: F,
) -> Result<(), AppError>
where
    T: Serialize,
    F: FnOnce(&T) -> serde_json::Value,
{
    // 1. Serialize to JSON string (once)
    let json_string = if output.pretty {
        serde_json::to_string_pretty(value)
    } else {
        serde_json::to_string(value)
    }.map_err(serialization_error)?;

    // 2. Determine effective threshold
    let threshold = output.large_response_threshold.unwrap_or(DEFAULT_THRESHOLD);

    // 3. If under threshold, print inline and return
    if json_string.len() <= threshold {
        println!("{json_string}");
        return Ok(());
    }

    // 4. Write to temp file
    let file_path = write_temp_file(&json_string, "json")?;
    let size_bytes = json_string.len() as u64;

    // 5. Build and print output object
    let summary = summary_fn(value);
    let output_obj = TempFileOutput {
        output_file: file_path,
        size_bytes,
        command: command_name.to_string(),
        summary,
    };
    let output_json = serde_json::to_string(&output_obj).map_err(serialization_error)?;
    println!("{output_json}");
    Ok(())
}
```

### New: `emit_plain()` function

```rust
/// Emit plain text through the large-response gate.
///
/// If text exceeds the threshold, writes to a temp file and prints the path.
pub fn emit_plain(text: &str, output: &OutputFormat) -> Result<(), AppError> {
    let threshold = output.large_response_threshold.unwrap_or(DEFAULT_THRESHOLD);

    if text.len() <= threshold {
        print!("{text}");
        return Ok(());
    }

    let file_path = write_temp_file(text, "txt")?;
    println!("{file_path}");
    Ok(())
}
```

### New: `write_temp_file()` helper

```rust
use std::io::Write;
use uuid::Uuid;

fn write_temp_file(content: &str, extension: &str) -> Result<String, AppError> {
    let uuid = Uuid::new_v4();
    let file_name = format!("agentchrome-{uuid}.{extension}");
    let file_path = std::env::temp_dir().join(&file_name);
    let path_str = file_path.display().to_string();

    let mut file = std::fs::File::create(&file_path).map_err(|e| AppError {
        message: format!("failed to create temp file {path_str}: {e}"),
        code: ExitCode::GeneralError,
        custom_json: None,
    })?;

    file.write_all(content.as_bytes()).map_err(|e| AppError {
        message: format!("failed to write temp file {path_str}: {e}"),
        code: ExitCode::GeneralError,
        custom_json: None,
    })?;

    Ok(path_str)
}
```

---

## Command Module Changes

### Pattern: Remove --search and Use emit() Directly

Each affected command module currently has:

```rust
// Before (e.g., page/text.rs)
if let Some(ref query) = args.search {
    let filtered = filter_text_paragraphs(&text, query);
    let result = PageTextResult { text: filtered, url, title };
    return output::emit_searched(&result, &global.output);
}
if global.output.plain {
    print!("{text}");
    return Ok(());
}
let result = PageTextResult { text, url, title };
output::emit(&result, &global.output, "page text", |r| { ... })
```

Changes to:

```rust
// After
if global.output.plain {
    return output::emit_plain(&text, &global.output);
}
let result = PageTextResult { text, url, title };
output::emit(&result, &global.output, "page text", |r| {
    serde_json::json!({
        "character_count": r.text.len(),
        "line_count": r.text.lines().count(),
    })
})
```

### Files Modified

| File | Changes |
|------|---------|
| `src/page/snapshot.rs` | Remove `--search` branch and `filter_tree()` call; remove `emit_searched()` call; update `--plain` path to use `emit_plain()` |
| `src/page/text.rs` | Remove `--search` branch and `filter_text_paragraphs()` call; remove `emit_searched()` call; update `--plain` path to use `emit_plain()` |
| `src/js.rs` | Remove `--search` branch and `filter_json_value()` call; remove `emit_searched()` call; update `--plain` path to use `emit_plain()` |
| `src/network.rs` | Remove `--search` branches from both `network list` and `network get`; remove `emit_searched()` calls; update `--plain` paths to use `emit_plain()` |
| `src/snapshot.rs` | Remove `filter_tree()` and `filter_node()` functions (dead code after --search removal); retain `count_nodes()` and `extract_top_roles()` for summary generation |

### Summary Functions (Unchanged)

Each command continues to provide a summary closure to `output::emit()`. These are unchanged from the #168 design:

```rust
// page/snapshot.rs
|v| serde_json::json!({
    "total_nodes": count_nodes(v),
    "top_roles": extract_top_roles(v, 5),
})

// page/text.rs
|r| serde_json::json!({
    "character_count": r.text.len(),
    "line_count": r.text.lines().count(),
})

// js.rs
|r| serde_json::json!({
    "result_type": &r.r#type,
    "size_bytes": serde_json::to_string(&r.result).map(|s| s.len()).unwrap_or(0),
})

// network.rs (list)
|reqs| serde_json::json!({
    "request_count": reqs.len(),
    "methods": unique_methods(reqs),
    "domains": unique_domains(reqs, 10),
})

// network.rs (get)
|d| serde_json::json!({
    "url": d.request.url,
    "status": d.response.status,
    "content_type": d.response.mime_type,
    "body_size_bytes": d.response.body.as_ref().map(|b| b.len()),
})
```

---

## Config Changes

### `src/config.rs` (Unchanged)

The `OutputConfig` and `ResolvedOutput` structs remain the same — `large_response_threshold` key is unchanged.

### `src/main.rs` — `apply_config_defaults()` (Modified)

```rust
// Before
output: cli::OutputFormat {
    json: cli_global.output.json,
    pretty: cli_global.output.pretty,
    plain: cli_global.output.plain,
    full_response: cli_global.output.full_response,    // REMOVED
    large_response_threshold: cli_global
        .output
        .large_response_threshold
        .or(config.output.large_response_threshold),
},

// After
output: cli::OutputFormat {
    json: cli_global.output.json,
    pretty: cli_global.output.pretty,
    plain: cli_global.output.plain,
    large_response_threshold: cli_global
        .output
        .large_response_threshold
        .or(config.output.large_response_threshold),
},
```

### Other Files Referencing `full_response`

| File | Change |
|------|--------|
| `src/examples.rs` | Remove `full_response: false` from test `OutputFormat` initializers |
| `src/capabilities.rs` | Remove `full_response: false` from test `OutputFormat` initializers |

---

## New Dependency: `uuid`

Add to `Cargo.toml`:

```toml
[dependencies]
uuid = { version = "1", features = ["v4"] }
```

This provides `Uuid::new_v4()` for generating collision-resistant file names. The `uuid` crate is well-established (1B+ downloads), adds minimal binary size (~20 KB), and is the standard approach for this pattern in Rust.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: Centralized emit function (original #168)** | Guidance object + `--search`/`--full-response` re-invocation pattern | Agents can filter server-side | Two-step pattern adds latency; complex per-command search implementations | **Replaced by #177** |
| **B: Temp file with UUID** | Write full output to temp file, return path object | Single-step; agent reads file directly; no re-invocation; simpler implementation | Requires filesystem I/O; temp file cleanup left to OS/agent | **Selected (#177)** |
| **C: Random hex instead of UUID** | Use `rand` to generate hex string for file names | Avoids `uuid` dependency | Less standard; `rand` is a heavier dependency than `uuid`; collision resistance less well-understood | Rejected |
| **D: Named pipe / stdout redirect** | Use OS pipes to stream large output | No temp files | Platform-specific; complex; doesn't solve context consumption | Rejected |

---

## Security Considerations

- [x] **No new external communication**: All processing is local; temp file is written to the OS temp directory.
- [x] **File path in output**: The `output_file` field contains an absolute path. This is safe — the temp directory is a well-known, user-writable location.
- [x] **No sensitive data in output object**: Summary contains only structural metadata (counts, roles, types), never actual page content.
- [x] **Temp file permissions**: `std::fs::File::create()` uses default OS permissions (typically `0600` on Unix). The file is readable only by the current user.
- [x] **Input validation**: `--large-response-threshold` validated as > 0 by clap's `parse_nonzero_usize`.

---

## Performance Considerations

- [x] **Single serialization pass**: Output is serialized once to a JSON string; byte length check is O(1) on the string length.
- [x] **Summary generation is lazy**: Summary closure is only called when the threshold is exceeded.
- [x] **Temp file I/O**: Writing to temp directory is fast (typically in-memory tmpfs on Linux, SSD-backed on macOS). Expected < 10ms for typical payloads (< 10 MB).
- [x] **No memory duplication**: The serialized JSON string is owned once; after writing to the temp file, only the small output object is serialized.
- [x] **UUID generation**: `Uuid::new_v4()` is negligible overhead (~100ns).
- [x] **Reduced complexity vs #168**: Removing `--search` eliminates O(n) filtering operations that occurred before output.

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| `output::emit()` | Unit | Below-threshold inline output; above-threshold temp file write; file content verification; output object schema |
| `output::emit_plain()` | Unit | Below-threshold inline print; above-threshold temp file write (.txt); path printed to stdout |
| `write_temp_file()` | Unit | File creation, content integrity, UUID uniqueness |
| `TempFileOutput` | Unit | Serialization schema (exactly 4 fields, correct types) |
| Summary functions | Unit | Per-command summary generation with known inputs (unchanged from #168) |
| CLI flag removal | BDD | `--search` and `--full-response` produce clap validation errors |
| Config file | BDD | `large_response_threshold` loaded from config, CLI override |
| Cross-command consistency | BDD | Output object schema is identical across all commands that trigger temp file output |
| Plain mode temp file | BDD | `--plain` mode writes to temp file when above threshold |
| Below-threshold | BDD | Small responses are inline, no temp file written |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Temp file write fails (disk full, permissions) | Low | High | Return structured JSON error on stderr with exit code 1; error message includes path and OS error |
| Breaking change for scripts using `--search`/`--full-response` | Medium | Medium | These flags are removed; scripts will get clap validation errors. This is intentional — document in release notes |
| Temp files accumulate on disk | Low | Low | Out of scope — OS tmp cleanup or agent cleanup handles lifecycle; file names are prefixed with `agentchrome-` for easy glob cleanup |
| Above-threshold output object breaks scripts that parse full JSON | Low | Medium | Only affects above-threshold responses (same as #168); below-threshold behavior is unchanged |

---

## Open Questions

- [x] Should `output::emit()` support `serde_json::Value` directly? — **Yes, `Value` implements `Serialize` (unchanged from #168)**
- [x] Should the output object be pretty-printed when `--pretty` is active? — **No, always compact JSON for machine readability (unchanged from #168)**
- [x] Should temp files use UUID or random hex? — **UUID v4 via the `uuid` crate**
- [x] What file extension for plain mode temp files? — **`.txt` (JSON mode uses `.json`)**

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #168 | 2026-03-12 | Initial design: guidance object + `--search` + `--full-response` |
| #177 | 2026-03-13 | Replace guidance object with temp file output; remove `--search` and `--full-response`; add `emit_plain()` for plain-mode temp file support; add `uuid` dependency; remove search filtering from all commands |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] N/A — No database/storage changes
- [x] N/A — No state management (CLI tool, no persistent state beyond session)
- [x] N/A — No UI components (CLI tool)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
