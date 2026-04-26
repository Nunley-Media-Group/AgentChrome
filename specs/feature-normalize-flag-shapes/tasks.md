# Tasks: Normalize Flag Shapes

**Issues**: #230
**Date**: 2026-04-22
**Status**: Planning
**Author**: Rich Nunley

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 1 | [ ] |
| Backend | 3 | [ ] |
| Integration | 1 | [ ] |
| Testing | 4 | [ ] |
| **Total** | 9 | |

No frontend phase — this is a CLI-only change.

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

## Phase 1: Setup

### T001: Add `url` crate as a direct dependency

**File(s)**: `Cargo.toml`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `url = "2"` (or latest 2.x) added under `[dependencies]`
- [ ] `cargo build` succeeds
- [ ] `Cargo.lock` updated by cargo (do not hand-edit)

**Notes**: Needed by `src/cookie.rs` for `Url::parse` + `host_str()` extraction in T003. Keep the feature set default — no extra features required.

---

## Phase 2: Backend Implementation

### T002: Add clap aliases to `CookieSetArgs`, `TabsCloseArgs`, and `DomCommand::Select`

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `CookieSetArgs` gains `pub url: Option<String>` with `#[arg(long, hide = true, conflicts_with = "domain")]` and a doc comment
- [ ] `TabsCloseArgs` gains `pub tab: Vec<String>` with `#[arg(long, hide = true, action = ArgAction::Append)]`; `#[arg(required = true)]` is removed from `targets`
- [ ] `DomCommand::Select` gains `#[command(alias = "query")]` (keeping existing `long_about` and `after_long_help`)
- [ ] `cargo build` succeeds
- [ ] `cargo clippy --all-targets` passes with zero warnings

**Notes**: Do NOT touch the `long_about` or `after_long_help` strings — those are the canonical documentation and must remain alias-free per AC6 / FR4.

### T003: Implement `--url` → `--domain` folding in `cookie set` handler

**File(s)**: `src/cookie.rs`
**Type**: Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] New private helper `extract_host(&str) -> Result<String, AppError>` using `url::Url::parse` + `host_str()`
- [ ] Malformed URLs error with `ExitCode::GeneralError` and a message naming `--domain` as the alternative
- [ ] URLs without a host (e.g., `file:///foo`) error with `ExitCode::GeneralError` and the same guidance
- [ ] `execute_set` computes `domain` from `args.url` when present, otherwise from `args.domain`
- [ ] When both are `Some` (defensive — clap's `conflicts_with` should prevent it), returns `ExitCode::GeneralError` with a message identifying them as aliases
- [ ] The downstream `Network.setCookie` params use the folded `domain` value
- [ ] The `SetResult.domain` field reflects the folded value so `--url` and `--domain` produce identical JSON output

**Notes**: Keep this handler-local. Do not expose `extract_host` outside the module.

### T004: Implement positional + `--tab` merge in `tabs close` dispatcher

**File(s)**: `src/tabs.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] The `TabsCommand::Close` match arm merges `close_args.targets` and `close_args.tab` into one `Vec<String>`, preserving order (positional first, then `--tab` values in appearance order)
- [ ] When the merged list is empty, return `AppError { code: ExitCode::GeneralError, ... }` with a message explaining that at least one target is required (positional or `--tab`)
- [ ] `execute_close` is called with the merged list and otherwise unchanged
- [ ] Duplicate IDs are NOT deduplicated (preserve existing semantics where a user could theoretically pass duplicates)

**Notes**: Do not modify `execute_close` — the merge happens at the dispatcher layer.

---

## Phase 3: Integration

### T005: Confirm `examples` and `capabilities` surfaces show no aliases

**File(s)**: `src/examples/commands.rs`, `src/capabilities.rs` (read-only verification; edits only if required)
**Type**: Verify (likely no edits)
**Depends**: T002
**Acceptance**:
- [ ] `agentchrome examples cookie` output contains no `--url` mention for `cookie set`
- [ ] `agentchrome examples tabs` output contains no `--tab` mention for `tabs close`
- [ ] `agentchrome examples dom` output contains no `query` mention
- [ ] `agentchrome capabilities --json` output does NOT list the alias flag/command names (clap's `hide = true` / subcommand `alias` naturally excludes them — verify this is the case)
- [ ] If any surface does leak an alias, update it to show canonical forms only

**Notes**: This task is mostly verification. Changes are only needed if the capabilities reflection layer inadvertently includes hidden flags.

---

## Phase 4: Testing (BDD required — every AC has a scenario)

### T006: Create BDD feature file

**File(s)**: `tests/features/230-normalize-flag-shapes.feature`
**Type**: Create
**Depends**: T003, T004
**Acceptance**:
- [ ] Scenarios cover AC1–AC8 from `requirements.md`
- [ ] Uses Given/When/Then format
- [ ] Matches the Gherkin file at `specs/feature-normalize-flag-shapes/feature.gherkin`
- [ ] Valid Gherkin syntax (`cargo test --test bdd` compiles scenario parsing)

### T007: Implement BDD step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify (add new World or extend existing CLI-only World)
**Depends**: T006
**Acceptance**:
- [ ] Steps run the built binary (`cargo run --` or `assert_cmd`) for each scenario
- [ ] Scenarios that require a live Chrome instance are gated by the existing Chrome-gate pattern (skip in CI)
- [ ] Pure-parse scenarios (`--help` contents, `cookie set --url --domain` conflict, missing-target case) run without Chrome and must NOT be Chrome-gated
- [ ] `cargo test --test bdd` passes

### T008: Add unit tests for clap parsing and host extraction

**File(s)**: `src/cli/mod.rs` (inline `#[cfg(test)] mod tests`), `src/cookie.rs` (inline tests)
**Type**: Create / Modify
**Depends**: T002, T003
**Acceptance**:
- [ ] Test: `Cli::try_parse_from(["agentchrome", "cookie", "set", "n", "v", "--url", "https://example.com/"])` succeeds with `url = Some(...)` and `domain = None`
- [ ] Test: passing both `--url` and `--domain` fails clap parsing (`conflicts_with`)
- [ ] Test: `Cli::try_parse_from(["agentchrome", "tabs", "close", "--tab", "A", "--tab", "B"])` parses with `targets = []` and `tab = ["A", "B"]`
- [ ] Test: `Cli::try_parse_from(["agentchrome", "tabs", "close"])` parses successfully (no `required = true` anymore); the handler-layer emptiness check is covered by T007
- [ ] Test: `Cli::try_parse_from(["agentchrome", "dom", "query", "h1"])` parses into `DomCommand::Select(DomSelectArgs { selector: "h1", xpath: false })`
- [ ] Test: `extract_host("https://example.com/path?x=1")` returns `"example.com"`
- [ ] Test: `extract_host("not a url")` returns an `AppError` whose message names `--domain`
- [ ] Test: `extract_host("file:///foo")` returns an `AppError` whose message names `--domain`
- [ ] `cargo test --lib` passes

### T009: Manual smoke test against headless Chrome (per tech.md)

**File(s)**: `tests/fixtures/230-normalize-flag-shapes.html` (created), verification log in PR description
**Type**: Create + Verify
**Depends**: T006, T007, T008
**Acceptance**:
- [ ] Fixture HTML contains a minimal page with a table (for AC4) and sets a cookie-relevant origin
- [ ] Per tech.md "Manual Smoke Test" procedure:
  - [ ] `cargo build` (debug)
  - [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
  - [ ] Navigate to fixture via `file://` URL
  - [ ] Exercise AC1: `cookie set test_cookie hello --url file:///...` — verify cookie set with host-derived domain (or fall back to AC1-variant: use `http://localhost/...` URL for realistic host extraction)
  - [ ] Exercise AC2/AC3: open an extra tab, close via `tabs close --tab <ID>` and verify remaining count
  - [ ] Exercise AC4: `dom query "table tbody tr"` — verify output matches `dom select`
  - [ ] Exercise AC5: re-run canonical forms, confirm unchanged behavior
  - [ ] Exercise AC6: run `cookie set --help`, `tabs close --help`, `dom --help`, grep for absence of alias names
  - [ ] Exercise AC7: run `cookie set n v --url U --domain D`, confirm exit code 1 + error JSON
  - [ ] Exercise AC8: run `cookie set n v --host example.com`, confirm error names `--domain`
- [ ] Disconnect and kill any orphaned Chrome processes
- [ ] All 5 verification gates pass: `cargo build`, `cargo test --lib`, `cargo clippy --all-targets`, `cargo fmt --check`, feature exercise

**Notes**: Fixture name per tech.md convention (uses the slug without the `feature-` prefix is fine — match existing fixture naming if one exists).

---

## Dependency Graph

```
T001 ─────▶ T003
T002 ─┬──▶ T003 ──▶ T006 ──▶ T007 ──▶ T009
      ├──▶ T004 ──▶ T006
      ├──▶ T005
      └──▶ T008 ──▶ T009
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #230 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included for each layer (unit + BDD + manual smoke)
- [x] No circular dependencies
- [x] Tasks are in logical execution order
