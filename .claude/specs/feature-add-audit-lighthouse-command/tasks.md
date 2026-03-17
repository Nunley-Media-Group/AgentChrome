# Implementation Tasks: Add `audit lighthouse` Command

**Issues**: #169
**Date**: 2026-03-16
**Status**: Draft
**Author**: Claude

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1: Setup | T001–T002 | CLI types and command dispatch wiring |
| 2: Core | T003–T006 | audit.rs module with binary discovery, execution, parsing, output |
| 3: Testing | T007–T009 | BDD feature file, step registration, unit tests |
| 4: Verification | T010–T011 | Manual smoke test and regression check |

---

## Phase 1: Setup

### T001: Add `audit` command group and `lighthouse` subcommand to CLI

**File**: `src/cli/mod.rs`

**Changes**:
1. Add `Audit(AuditArgs)` variant to the `Command` enum with help text and examples
2. Define `AuditArgs` struct with `#[command(subcommand)] pub command: AuditCommand`
3. Define `AuditCommand` enum with `Lighthouse(AuditLighthouseArgs)` variant
4. Define `AuditLighthouseArgs` struct with:
   - `pub url: Option<String>` — positional, optional URL override
   - `#[arg(long)] pub only: Option<String>` — comma-separated category filter
   - `#[arg(long)] pub output_file: Option<PathBuf>` — path to save full report

**Acceptance Criteria**:
- `agentchrome audit --help` shows the audit command group
- `agentchrome audit lighthouse --help` shows all flags and arguments
- `agentchrome audit` without subcommand exits non-zero with "subcommand" in stderr

**Dependencies**: None

---

### T002: Wire `audit` command dispatch in `main.rs`

**Files**: `src/main.rs`

**Changes**:
1. Add `mod audit;` declaration at the top of main.rs
2. Add match arm: `Command::Audit(args) => audit::execute_audit(&global, args).await,`
3. Add `AuditArgs` to the `use cli::{...}` import list

**Acceptance Criteria**:
- `agentchrome audit lighthouse` routes to `audit::execute_audit`
- Project compiles with `cargo check`

**Dependencies**: T001

---

## Phase 2: Core Implementation

### T003: Create `src/audit.rs` with `execute_audit` entry point

**File**: `src/audit.rs` (new)

**Changes**:
1. Create the module with standard imports (serde, AppError, ExitCode, GlobalOpts, etc.)
2. Implement `pub async fn execute_audit(global: &GlobalOpts, args: &AuditArgs) -> Result<(), AppError>` that matches on `AuditCommand::Lighthouse` and delegates to `execute_lighthouse`
3. Implement `async fn execute_lighthouse(global: &GlobalOpts, args: &AuditLighthouseArgs) -> Result<(), AppError>` as the main orchestration function:
   - Resolve connection to get port
   - Resolve URL (from arg or active page)
   - Find lighthouse binary
   - Validate `--only` categories
   - Build and execute lighthouse command
   - Parse output and print scores summary
   - Optionally save full report

**Acceptance Criteria**:
- Function compiles and is reachable from dispatch
- Returns `AppError::no_session()` when no session exists

**Dependencies**: T001, T002

---

### T004: Implement lighthouse binary discovery and category validation

**File**: `src/audit.rs`

**Changes**:
1. Define `const VALID_CATEGORIES: &[&str] = &["performance", "accessibility", "best-practices", "seo", "pwa"];`
2. Implement `fn find_lighthouse_binary() -> Result<(), AppError>` that runs `lighthouse --version` as a probe:
   - On success, return `Ok(())`
   - On failure (not found / not executable), return `AppError` with message: `"lighthouse binary not found. Install it with: npm install -g lighthouse"` and code `GeneralError`
3. Implement `fn validate_categories(only: &str) -> Result<Vec<&str>, AppError>` that:
   - Splits on commas, trims whitespace
   - Validates each against `VALID_CATEGORIES`
   - Returns error for invalid: `"Invalid category: '<name>'. Valid categories: performance, accessibility, best-practices, seo, pwa"`

**Acceptance Criteria**:
- `find_lighthouse_binary()` returns structured error with install hint when lighthouse is not installed
- `validate_categories("performance,accessibility")` returns `Ok(vec!["performance", "accessibility"])`
- `validate_categories("performance,invalid")` returns error naming the invalid category

**Dependencies**: T003

---

### T005: Implement lighthouse execution and JSON parsing

**File**: `src/audit.rs`

**Changes**:
1. Implement `fn build_lighthouse_command(url: &str, port: u16, categories: Option<&[&str]>) -> std::process::Command` that constructs:
   ```
   lighthouse <URL> --port <PORT> --output json --chrome-flags="--headless"
   [--only-categories=cat1,cat2,...]
   ```
2. Implement `fn run_lighthouse(cmd: &mut std::process::Command) -> Result<serde_json::Value, AppError>` that:
   - Executes the command, captures stdout/stderr
   - On non-zero exit: returns `AppError` with `"Lighthouse audit failed: <stderr trimmed>"` and code `GeneralError`
   - On zero exit: parses stdout as JSON, returns the parsed value
   - On parse failure: returns `AppError` with `"Failed to parse Lighthouse output: <reason>"`

**Acceptance Criteria**:
- Command is constructed with correct flags
- Non-zero exit code produces a structured error with lighthouse's stderr
- Stdout is parsed as JSON successfully

**Dependencies**: T003, T004

---

### T006: Implement score extraction and output formatting

**File**: `src/audit.rs`

**Changes**:
1. Implement `fn extract_scores(lhr: &serde_json::Value, url: &str, requested: Option<&[&str]>) -> Result<serde_json::Value, AppError>` that:
   - Reads `lhr["categories"]` object
   - For each category, extracts `.score` (which may be `null` or a number)
   - If `requested` is `Some`, only includes those categories; others are omitted
   - If `requested` is `None`, includes all 5 categories
   - Builds a `serde_json::Map` with `url` plus category scores
   - Returns the JSON value
2. Implement the `--output-file` logic: if provided, write the raw `lhr` JSON to the file path using `std::fs::write`
3. Print the scores summary JSON to stdout via `println!`

**Output format**:
```json
{"url":"https://example.com","performance":0.91,"accessibility":0.87,"best-practices":0.93,"seo":0.90,"pwa":0.30}
```

When `--only performance,accessibility` is used:
```json
{"url":"https://example.com","performance":0.91,"accessibility":0.87}
```

When a category score is `null` in Lighthouse output:
```json
{"url":"https://example.com","performance":0.91,"pwa":null}
```

**Acceptance Criteria**:
- All 5 categories extracted when no `--only` filter
- Only requested categories present when `--only` is used
- `null` scores preserved as JSON `null`, not omitted
- `--output-file` writes the full Lighthouse JSON report to disk
- Scores summary always printed to stdout

**Dependencies**: T005

---

## Phase 3: Testing

### T007: Create BDD feature file

**File**: `tests/features/audit-lighthouse.feature` (new)

**Changes**:
1. Write Gherkin scenarios covering all 8 acceptance criteria from requirements.md
2. Include CLI-testable scenarios (argument validation, help text, invalid categories)
3. Include Chrome-dependent scenarios (full audit, URL override) marked with comments

**Acceptance Criteria**:
- Feature file covers AC1–AC8
- Scenarios use existing CliWorld step patterns (`Given agentchrome is built`, `When I run "..."`, `Then ...`)

**Dependencies**: T001

---

### T008: Register BDD feature file in test runner

**File**: `tests/bdd.rs`

**Changes**:
1. Add `CliWorld::cucumber()` block at the end of `main()` that runs `tests/features/audit-lighthouse.feature`
2. Filter to CLI-testable scenarios only (argument validation, help text, invalid `--only`, subcommand required)
3. Chrome-dependent scenarios filtered out with a comment explaining they're verified via smoke test

**Acceptance Criteria**:
- `cargo test --test bdd` includes the audit lighthouse feature
- CLI-testable scenarios pass
- Chrome-dependent scenarios are skipped with explanation

**Dependencies**: T007

---

### T009: Add unit tests for category validation and score extraction

**File**: `src/audit.rs` (inline `#[cfg(test)] mod tests`)

**Changes**:
1. Test `validate_categories` with valid, invalid, and mixed inputs
2. Test `extract_scores` with:
   - Full Lighthouse JSON → all 5 scores extracted
   - `--only` filter → only requested categories in output
   - `null` score → preserved as `null` in output
   - Missing `categories` key → error
3. Test `find_lighthouse_binary` error message contains install hint

**Acceptance Criteria**:
- `cargo test --lib` passes all unit tests
- Coverage for happy path, filtering, null handling, and error cases

**Dependencies**: T004, T006

---

## Phase 4: Verification

### T010: Manual smoke test against real Chrome

**Procedure**:
1. `cargo build`
2. `./target/debug/agentchrome connect --launch --headless`
3. `./target/debug/agentchrome navigate https://example.com`
4. `./target/debug/agentchrome audit lighthouse` — verify JSON scores on stdout
5. `./target/debug/agentchrome audit lighthouse --only performance,accessibility` — verify filtered output
6. `./target/debug/agentchrome audit lighthouse --output-file /tmp/lh-report.json` — verify file written + scores on stdout
7. `./target/debug/agentchrome audit lighthouse https://www.saucedemo.com/` — verify URL override
8. `./target/debug/agentchrome audit lighthouse --only invalid` — verify error message
9. SauceDemo baseline: navigate + snapshot against https://www.saucedemo.com/
10. `./target/debug/agentchrome connect disconnect`
11. `pkill -f 'chrome.*--remote-debugging' || true`

**Acceptance Criteria**:
- All ACs verified against real browser
- SauceDemo baseline passes

**Dependencies**: T001–T009

---

### T011: Verify no regressions

**Procedure**:
1. `cargo fmt --check` — no formatting violations
2. `cargo clippy` — no new warnings
3. `cargo test` — all existing tests pass
4. `cargo build` — clean build

**Acceptance Criteria**:
- Zero clippy warnings
- Zero test failures
- Clean build

**Dependencies**: T001–T009

---

## Dependency Graph

```
T001 (CLI types)
  ├── T002 (dispatch wiring) ── T003 (audit.rs scaffold)
  │                                ├── T004 (binary discovery + validation)
  │                                │     └── T005 (execution + parsing)
  │                                │           └── T006 (score extraction + output)
  │                                │
  └── T007 (feature file) ── T008 (BDD registration)

T004 + T006 ── T009 (unit tests)

T001–T009 ── T010 (smoke test)
T001–T009 ── T011 (regression check)
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #169 | 2026-03-16 | Initial task breakdown |
