# Tasks: Large Response Detection with Temp File Output

**Issues**: #168, #177
**Date**: 2026-03-13
**Status**: Planning
**Author**: AI (nmg-sdlc)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 3 (T001–T003) | [x] Completed (#168) |
| Backend | 5 (T004–T008) | [x] Completed (#168), superseded by #177 |
| Integration | 2 (T009–T010) | [x] Completed (#168), T010 updated by #177 |
| Testing | 5 (T011–T015) | [x] Completed (#168), updated by #177 |
| Enhancement — #177 | 9 (T016–T024) | [ ] |
| **Total** | **24** | |

---

## Task Format

Each task follows this structure:

```
### T[NNN]: [Task Title]

**File(s)**: `{layer}/path/to/file`
**Type**: Create | Modify | Delete
**Depends**: T[NNN], T[NNN] (or None)
**Acceptance**:
- [ ] [Verifiable criterion 1]
- [ ] [Verifiable criterion 2]

**Notes**: [Optional implementation hints]
```

Map `{layer}/` placeholders to actual project paths using `structure.md`.

---

## Phase 1: Setup [Completed — #168]

### T001: Create output.rs Module with Large-Response Gate [COMPLETED]

**File(s)**: `src/output.rs`
**Type**: Create
**Depends**: None
**Acceptance**:
- [x] `DEFAULT_THRESHOLD` constant is `16_384` (16 KB)
- [x] `LargeResponseGuidance` struct serializes correctly
- [x] `emit()` function accepts `&impl Serialize`, `&OutputFormat`, command name, and summary closure
- [x] `emit()` serializes value once, checks threshold, prints JSON or guidance
- [x] `emit()` bypasses threshold check when `full_response` is `true`
- [x] `format_human_size()` returns human-readable sizes
- [x] `build_guidance_text()` generates guidance string
- [x] `command_specific_guidance()` returns per-command details

### T002: Extend OutputFormat with Global Flags [COMPLETED]

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [x] `OutputFormat` has `full_response: bool` and `large_response_threshold: Option<usize>`
- [x] Format flags remain mutually exclusive
- [x] `--large-response-threshold 0` is rejected

### T003: Extend Config with large_response_threshold [COMPLETED]

**File(s)**: `src/config.rs`, `src/main.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [x] `OutputConfig` has `large_response_threshold: Option<usize>`
- [x] Config merging: CLI flag > config file > default

---

## Phase 2: Backend Implementation [COMPLETED — #168, SUPERSEDED by #177]

### T004: ~~Add --search to page snapshot~~ [SUPERSEDED by T019]

### T005: ~~Add --search to page text~~ [SUPERSEDED by T019]

### T006: ~~Add --search to js exec~~ [SUPERSEDED by T019]

### T007: ~~Add --search to network list~~ [SUPERSEDED by T019]

### T008: ~~Add --search to network get~~ [SUPERSEDED by T019]

---

## Phase 3: Integration [COMPLETED — #168]

### T009: Register output Module in lib.rs [COMPLETED]

**File(s)**: `src/lib.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [x] `pub mod output;` in `src/lib.rs`
- [x] Module accessible as `agentchrome::output`

### T010: Wire Config Merging for large_response_threshold [COMPLETED, updated by T018]

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: T002, T003
**Acceptance**:
- [x] `apply_config_defaults()` merges `large_response_threshold`

---

## Phase 4: Testing [COMPLETED — #168, updated by #177]

### T011: ~~Create BDD Feature File~~ [SUPERSEDED by T021]

### T012: ~~Implement BDD Step Definitions~~ [SUPERSEDED by T022]

### T013: ~~Unit Tests for output.rs~~ [SUPERSEDED by T023]

### T014: ~~Manual Smoke Test~~ [SUPERSEDED by T024]

### T015: ~~Verify No Regressions~~ [SUPERSEDED by T025]

---

## Phase 5: Enhancement — Issue #177

### T016: Add uuid Dependency

**File(s)**: `Cargo.toml`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `uuid = { version = "1", features = ["v4"] }` added to `[dependencies]`
- [ ] `cargo build` compiles successfully with the new dependency

### T017: Refactor output.rs — Replace Guidance with Temp File Output

**File(s)**: `src/output.rs`
**Type**: Modify
**Depends**: T016
**Acceptance**:
- [ ] `LargeResponseGuidance` struct replaced by `TempFileOutput` with fields: `output_file` (String), `size_bytes` (u64), `command` (String), `summary` (serde_json::Value)
- [ ] `emit()` modified: when above threshold, writes JSON to `{temp_dir}/agentchrome-{uuid}.json` and prints `TempFileOutput` object to stdout
- [ ] `emit()` no longer checks `full_response` field (removed)
- [ ] `write_temp_file(content: &str, extension: &str)` helper added — creates file in `std::env::temp_dir()`, returns absolute path as String
- [ ] `write_temp_file()` returns `AppError` with descriptive message on I/O failure
- [ ] `emit_plain(text: &str, output: &OutputFormat)` added — below threshold prints text; above threshold writes to `.txt` temp file and prints path to stdout
- [ ] `emit_searched()` function removed
- [ ] `build_guidance_text()` function removed
- [ ] `command_specific_guidance()` function removed
- [ ] `format_human_size()` retained (still useful elsewhere or for future use, but acceptable to remove if unused)
- [ ] `DEFAULT_THRESHOLD` constant retained at `16_384`

**Notes**: The `emit()` function signature remains the same (`value`, `output`, `command_name`, `summary_fn`). The summary closure is still only called when threshold is exceeded. The temp file is written synchronously — no async I/O needed since this runs after CDP communication is complete.

### T018: Remove --full-response and --search from CLI

**File(s)**: `src/cli/mod.rs`, `src/main.rs`, `src/examples.rs`, `src/capabilities.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `full_response: bool` field removed from `OutputFormat` struct
- [ ] `search: Option<String>` field removed from `PageSnapshotArgs`
- [ ] `search: Option<String>` field removed from `PageTextArgs`
- [ ] `search: Option<String>` field removed from `JsExecArgs`
- [ ] `search: Option<String>` field removed from `NetworkListArgs`
- [ ] `search: Option<String>` field removed from `NetworkGetArgs`
- [ ] `apply_config_defaults()` in `main.rs` no longer sets `full_response`
- [ ] `OutputFormat` initializers in `src/examples.rs` updated (remove `full_response: false`)
- [ ] `OutputFormat` initializers in `src/capabilities.rs` updated (remove `full_response: false`)
- [ ] `agentchrome --help` does NOT show `--full-response` or `--search`
- [ ] `agentchrome page snapshot --search foo` returns clap validation error (unknown argument)
- [ ] `agentchrome --full-response page snapshot` returns clap validation error (unknown argument)

### T019: Update Command Modules — Remove Search Logic, Add Plain-Mode Temp File

**File(s)**: `src/page/snapshot.rs`, `src/page/text.rs`, `src/js.rs`, `src/network.rs`, `src/snapshot.rs`
**Type**: Modify
**Depends**: T017, T018
**Acceptance**:
- [ ] `src/page/snapshot.rs`: Search filtering branch removed; `emit_searched()` call removed; `--plain` path updated to call `output::emit_plain()` instead of direct `print!()`
- [ ] `src/page/text.rs`: Search filtering branch and `filter_text_paragraphs()` removed; `emit_searched()` call removed; `--plain` path updated to call `output::emit_plain()`
- [ ] `src/js.rs`: Search filtering branch and `filter_json_value()` removed; `emit_searched()` call removed; `--plain` path updated to call `output::emit_plain()`
- [ ] `src/network.rs` (list): Search filtering branch and `filter_by_search()` removed; `emit_searched()` call removed; `--plain` path updated to call `output::emit_plain()`
- [ ] `src/network.rs` (get): Inline search filtering removed; `emit_searched()` call removed; `--plain` path updated to call `output::emit_plain()`
- [ ] `src/snapshot.rs`: `filter_tree()` and `filter_node()` functions removed (dead code); `count_nodes()` and `extract_top_roles()` retained for summary generation
- [ ] `cargo build` compiles with no errors or warnings
- [ ] All `emit()` calls pass through the temp file gate (no search bypass)

**Notes**: Each command module's output path simplifies to: (1) if `--plain`: call `emit_plain()`; (2) else: call `emit()` with summary closure. No more search branching.

### T020: Update Config Propagation for Removed full_response Field

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: T018
**Acceptance**:
- [ ] `apply_config_defaults()` no longer references `full_response` in the `OutputFormat` construction
- [ ] `large_response_threshold` merging remains unchanged (CLI > config > default)
- [ ] `cargo build` compiles with no errors

**Notes**: This is a small change — just remove the `full_response: cli_global.output.full_response` line from the `OutputFormat` construction in `apply_config_defaults()`.

### T021: Update BDD Feature File for Temp File Output

**File(s)**: `tests/features/large-response-detection.feature`
**Type**: Modify
**Depends**: T019
**Acceptance**:
- [ ] Superseded scenarios (guidance object, --search, --full-response) removed or replaced
- [ ] New scenarios added for: temp file output (AC18), file content verification (AC19), UUID collision prevention (AC20), output object schema (AC21), plain-mode temp file (AC22), command-specific summary (AC23), flag removal errors (AC24)
- [ ] Retained scenarios updated: below-threshold (AC5), threshold CLI (AC6), threshold config (AC7), per-command truncation (AC15)
- [ ] Valid Gherkin syntax
- [ ] Scenarios are independent

### T022: Update BDD Step Definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T021
**Acceptance**:
- [ ] Step definitions for search/full-response scenarios removed
- [ ] New step definitions added for temp file verification:
  - Step to check stdout contains `output_file` field
  - Step to read file at `output_file` path and verify contents
  - Step to verify `--search` / `--full-response` produce clap errors
  - Step to verify plain-mode temp file (stdout is a file path, file contains text)
- [ ] `cargo test --test bdd` passes for all new scenarios

### T023: Update Unit Tests in output.rs

**File(s)**: `src/output.rs`
**Type**: Modify
**Depends**: T017
**Acceptance**:
- [ ] Tests for `LargeResponseGuidance` serialization removed
- [ ] Tests for `build_guidance_text()` removed
- [ ] Tests for `emit_searched()` removed
- [ ] Tests for `emit()` with `full_response = true` removed
- [ ] New test: `emit()` with value below threshold → prints JSON inline
- [ ] New test: `emit()` with value above threshold → creates temp file, prints `TempFileOutput` object
- [ ] New test: temp file contains the full serialized JSON
- [ ] New test: `TempFileOutput` serialization has exactly 4 fields (`output_file`, `size_bytes`, `command`, `summary`)
- [ ] New test: `write_temp_file()` creates file with correct content and `.json`/`.txt` extension
- [ ] New test: `emit_plain()` below threshold prints text inline
- [ ] New test: `emit_plain()` above threshold writes `.txt` file, prints path
- [ ] New test: two `write_temp_file()` calls produce distinct file paths (UUID uniqueness)
- [ ] `format_human_size()` tests retained if function is retained
- [ ] `cargo test --lib` passes

### T024: Manual Smoke Test Against Real Chrome

**File(s)**: (no file changes — execution only)
**Type**: Verify
**Depends**: T019, T020
**Acceptance**:
- [ ] Build debug binary: `cargo build`
- [ ] Connect to headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to https://www.saucedemo.com/
- [ ] `page snapshot` on SauceDemo: if tree > 16 KB, stdout shows `output_file` path; reading the file returns the full accessibility tree JSON
- [ ] `page snapshot --large-response-threshold 100`: forces temp file for any response; verify file path returned and file readable
- [ ] `page text`: verify correct behavior (inline or temp file depending on size)
- [ ] `js exec "JSON.stringify(performance.getEntries())"`: verify JS path works
- [ ] `network list` after page load: verify network data
- [ ] `page snapshot --plain --large-response-threshold 100`: verify plain-mode temp file (stdout is a file path ending in `.txt`)
- [ ] `page snapshot --search login`: verify clap error (unknown argument)
- [ ] `agentchrome --full-response page snapshot`: verify clap error (unknown argument)
- [ ] Disconnect: `./target/debug/agentchrome connect disconnect`
- [ ] Kill orphaned Chrome: `pkill -f 'chrome.*--remote-debugging' || true`

### T025: Verify No Regressions

**File(s)**: (no file changes — execution only)
**Type**: Verify
**Depends**: T021, T022, T023, T024
**Acceptance**:
- [ ] `cargo test --lib` passes (all unit tests)
- [ ] `cargo test --test bdd` passes (all BDD tests)
- [ ] `cargo clippy` passes with no new warnings
- [ ] `cargo fmt --check` passes
- [ ] Existing BDD feature files (not related to large-response) still pass
- [ ] Below-threshold responses produce identical JSON output to pre-#177 behavior

---

## Dependency Graph

```
Phase 1–4 (Completed #168):
  T001–T015 — all completed, many superseded by Phase 5

Phase 5 (Enhancement #177):

T016 (uuid dep) ──▶ T017 (refactor output.rs)
                                │
T018 (remove CLI flags) ───────┤
                                │
T020 (config propagation) ◀─── T018
                                │
T019 (update commands) ◀─────── T017, T018
        │
        ├──▶ T021 (update BDD feature) ──▶ T022 (update step defs)
        │
        └──▶ T024 (smoke test)
                                │
T023 (update unit tests) ◀──── T017
                                │
T025 (regressions) ◀────────── T021, T022, T023, T024
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #168 | 2026-03-12 | Initial task breakdown: 15 tasks across 4 phases |
| #177 | 2026-03-13 | Added Phase 5 (Enhancement): 9 new tasks (T016–T024, T025); T004–T008 superseded (search removed); T011–T015 superseded by T021–T025 |

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included for each layer
- [x] No circular dependencies
- [x] Tasks are in logical execution order
