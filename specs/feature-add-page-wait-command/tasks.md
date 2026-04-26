# Tasks: Add Page Wait Command

**Issues**: #163, #195
**Date**: 2026-04-16
**Status**: Planning
**Author**: Claude

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 3 | [x] |
| Backend | 3 | [x] |
| Integration | 1 | [x] |
| Testing | 5 | [x] |
| Enhancement — Issue #195 | 7 | [ ] |
| **Total** | **19** | |

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

### T001: Add `globset` dependency to Cargo.toml

**File(s)**: `Cargo.toml`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [x] `globset = "0.4"` added to `[dependencies]` section
- [x] `cargo check` passes with the new dependency

**Notes**: The `globset` crate provides URL-appropriate glob matching where `*` matches across `/` characters.

### T002: Define `PageWaitArgs` and add `Wait` variant to `PageCommand`

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [x] `PageWaitArgs` struct defined with `--url`, `--text`, `--selector`, `--network-idle`, and `--interval` fields
- [x] `--url`, `--text`, `--selector`, and `--network-idle` use `group = "condition"` to enforce exactly one condition
- [x] `#[command(arg_required_else_help = true)]` attribute on `PageWaitArgs`
- [x] `--interval` defaults to `100` (milliseconds)
- [x] `Wait(PageWaitArgs)` variant added to `PageCommand` enum with `/// Wait until a condition is met on the current page` doc comment
- [x] `cargo check` passes

**Notes**: Use `#[arg(long, group = "condition")]` on each condition flag. The `network_idle` field is `bool` (presence flag); others are `Option<String>`.

### T003: Add `wait_timeout` error constructor to `AppError`

**File(s)**: `src/error.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [x] `pub fn wait_timeout(timeout_ms: u64, condition: &str) -> Self` added to `impl AppError`
- [x] Returns `ExitCode::TimeoutError` (code 4)
- [x] Message format: `"Wait timed out after {timeout_ms}ms: {condition}"`
- [x] `cargo check` passes

---

## Phase 2: Backend Implementation

### T004: Create `src/page/wait.rs` — core structure and condition dispatch

**File(s)**: `src/page/wait.rs`
**Type**: Create
**Depends**: T001, T002, T003
**Acceptance**:
- [x] `WaitResult` struct defined with `condition`, `matched`, `url`, `title`, and optional `pattern`/`text`/`selector` fields (using `skip_serializing_if`)
- [x] `pub async fn execute_wait(global: &GlobalOpts, args: &PageWaitArgs) -> Result<(), AppError>` implemented
- [x] Function calls `setup_session(global)` and `ensure_domain("Runtime")`
- [x] Timeout derived from `global.timeout.unwrap_or(DEFAULT_NAVIGATE_TIMEOUT_MS)`
- [x] Dispatches to poll-based path for `--url`/`--text`/`--selector` or event-driven path for `--network-idle`
- [x] On success, calls `get_page_info()` for URL/title and outputs via `print_output()`
- [x] Supports `--plain` output format
- [x] `cargo check` passes

**Notes**: Import `setup_session`, `get_page_info`, `print_output`, `cdp_config` from `super`. Import `DEFAULT_NAVIGATE_TIMEOUT_MS` from `crate::navigate`.

### T005: Implement poll-based condition checking (`--url`, `--text`, `--selector`)

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [x] `--url`: Compiles glob pattern with `GlobBuilder::new(pattern).literal_separator(false).build()` and matches against `location.href` via `Runtime.evaluate`
- [x] `--text`: Evaluates `document.body.innerText.includes(...)` via `Runtime.evaluate` — text value properly JSON-encoded with `serde_json::to_string()` before embedding in JS expression to prevent injection
- [x] `--selector`: Evaluates `document.querySelector(...) !== null` via `Runtime.evaluate` — selector value properly escaped
- [x] Immediate pre-check: condition evaluated once before entering poll loop; returns immediately if already satisfied (AC7)
- [x] Poll loop: `tokio::time::sleep(Duration::from_millis(args.interval))` between checks
- [x] Deadline enforcement: returns `AppError::wait_timeout()` when elapsed time exceeds timeout
- [x] Invalid glob pattern produces a clear error (exit code 1) before any CDP interaction
- [x] JS evaluation errors during polling are caught and retried on next interval (page may be navigating)
- [x] `cargo check` passes

**Notes**: For `--url`, fetch `location.href` as a string and match in Rust with `globset`. For `--text` and `--selector`, the entire check runs in JS returning a boolean.

### T006: Implement event-driven `--network-idle` path

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [x] Enables `Network` domain via `managed.ensure_domain("Network")`
- [x] Subscribes to `Network.requestWillBeSent`, `Network.loadingFinished`, `Network.loadingFailed`
- [x] Calls `navigate::wait_for_network_idle(req_rx, fin_rx, fail_rx, timeout_ms)`
- [x] Returns immediately when network is already idle (inherent behavior of `wait_for_network_idle` — idle timer starts at 0 in-flight) (AC6)
- [x] On success, retrieves page info and outputs `WaitResult` with `condition: "network-idle"`
- [x] `cargo check` passes

**Notes**: Direct reuse of `wait_for_network_idle()` from `src/navigate.rs` — no modifications needed to that function.

---

## Phase 3: Integration

### T007: Wire wait module into page dispatcher

**File(s)**: `src/page/mod.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [x] `mod wait;` declaration added alongside other submodule declarations
- [x] `PageCommand::Wait(wait_args) => wait::execute_wait(global, wait_args).await,` arm added to `execute_page` match
- [x] `cargo build` succeeds
- [x] `cargo clippy` passes with no new warnings
- [x] `cargo fmt --check` passes

---

## Phase 4: Testing

### T008: Create BDD feature file

**File(s)**: `tests/features/page-wait.feature`
**Type**: Create
**Depends**: T007
**Acceptance**:
- [x] All 8 acceptance criteria from requirements.md (AC1-AC8) mapped to scenarios
- [x] Valid Gherkin syntax
- [x] Scenarios are independent (no shared mutable state)
- [x] Uses concrete examples from requirements.md

### T009: Implement BDD step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T008
**Acceptance**:
- [x] All step definitions for page-wait scenarios implemented
- [x] Steps follow existing patterns in `tests/bdd.rs`
- [x] `cargo test --test bdd` passes (Chrome-independent scenarios)

### T010: Add unit tests for glob URL matching

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T005
**Acceptance**:
- [x] `#[cfg(test)] mod tests` block with unit tests for glob matching
- [x] Tests cover: wildcard match, literal match, no match, pattern with `*` across `/`, empty pattern edge case
- [x] `cargo test --lib` passes

### T011: Manual smoke test against real Chrome

**File(s)**: (no file changes — execution only)
**Type**: Verify
**Depends**: T007
**Acceptance**:
- [x] Build debug binary: `cargo build`
- [x] Connect to headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [x] Navigate to SauceDemo: `./target/debug/agentchrome navigate https://www.saucedemo.com/`
- [x] Test `--text`: `./target/debug/agentchrome page wait --text "Swag Labs"` returns successfully with JSON
- [x] Test `--url`: `./target/debug/agentchrome page wait --url "*saucedemo*"` returns successfully with JSON
- [x] Test `--selector`: `./target/debug/agentchrome page wait --selector "#login-button"` returns successfully with JSON
- [x] Test `--network-idle`: `./target/debug/agentchrome page wait --network-idle` returns successfully with JSON
- [x] Test timeout: `./target/debug/agentchrome page wait --text "nonexistent" --timeout 2000` exits with code 4
- [x] Test no condition: `./target/debug/agentchrome page wait` shows help/error
- [x] Disconnect and kill Chrome: `./target/debug/agentchrome connect disconnect && pkill -f 'chrome.*--remote-debugging' || true`

### T012: Verify no regressions

**File(s)**: (no file changes — execution only)
**Type**: Verify
**Depends**: T007, T009
**Acceptance**:
- [x] `cargo test --lib` passes (all unit tests)
- [x] `cargo test --test bdd` passes (all BDD tests)
- [x] `cargo clippy` passes with no new warnings
- [x] `cargo fmt --check` passes
- [x] No changes to existing page subcommand behavior

---

## Phase 5: Enhancement — Issue #195

### T013: Add `--js-expression` field and `--count` field to `PageWaitArgs`

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `js_expression: Option<String>` field added with `#[arg(long, group = "condition")]`
- [ ] `count: u64` field added with `#[arg(long, requires = "selector", default_value = "1")]`
- [ ] `--js-expression` participates in the `"condition"` group (mutually exclusive with other conditions)
- [ ] `--count` requires `--selector` (clap enforced)
- [ ] `--count` defaults to 1 (backward compatible — existing selector wait behavior unchanged)
- [ ] `after_long_help` text updated with `--js-expression` and `--count` examples
- [ ] `cargo check` passes

**Notes**: The `--count` field is NOT in the condition group — it modifies `--selector` behavior. `requires = "selector"` ensures it can only be used with `--selector`.

### T014: Add `js_eval_error` constructor to `AppError` and `is_truthy` helper

**File(s)**: `src/error.rs`, `src/page/wait.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] `pub fn js_eval_error(js_message: &str) -> Self` added to `impl AppError`
- [ ] Returns `ExitCode::GeneralError` (code 1)
- [ ] Message format: `"JavaScript expression evaluation failed: {js_message}"`
- [ ] Unit test for `js_eval_error` added
- [ ] `is_truthy(value: &serde_json::Value) -> bool` helper added to `src/page/wait.rs`
- [ ] Truthiness follows JS semantics: `true` for non-zero numbers, non-empty strings, true booleans, arrays, objects; `false` for null, false, 0, empty string
- [ ] Unit tests for `is_truthy` covering all JSON value types
- [ ] `cargo check` passes

### T015: Implement `eval_js_checked` and `--js-expression` poll path

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T013, T014
**Acceptance**:
- [ ] `EvalOutcome` enum defined with `Value(serde_json::Value)`, `JsException(String)`, `TransientError` variants
- [ ] `eval_js_checked(managed, expression) -> EvalOutcome` implemented — sends `Runtime.evaluate`, checks response for `exceptionDetails` field, returns appropriate variant
- [ ] `poll_js_expression(global, managed, expression, timeout_ms, interval_ms)` function implemented
- [ ] Immediate pre-check: if expression is truthy on first eval → return immediately
- [ ] Poll loop: sleep(interval) → eval_js_checked → check truthiness
- [ ] Consecutive JS exception counter: after 3 consecutive `JsException` results, return `AppError::js_eval_error(msg)`
- [ ] Counter resets on any `Value(_)` result (even falsy) or `TransientError`
- [ ] On timeout, returns `AppError::wait_timeout(timeout_ms, "js-expression not truthy")`
- [ ] `WaitResult` output includes `js_expression` field with the original expression string
- [ ] Frame context is respected (expression evaluated in frame if `--frame` is specified)
- [ ] `cargo check` passes

### T016: Implement `--count` modifier for `--selector` poll path

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T013
**Acceptance**:
- [ ] `check_selector_condition` updated to accept `count: u64` parameter
- [ ] When `count <= 1`: uses existing `document.querySelector(sel) !== null` (backward compatible)
- [ ] When `count > 1`: uses `document.querySelectorAll(sel).length >= count`
- [ ] `poll_selector` updated to pass `args.count` through to condition checker
- [ ] `WaitResult` includes `count: Some(n)` when `count > 1`, omitted when count is 1
- [ ] Timeout message includes count: `"selector \".item\" count >= 3 not reached"`
- [ ] `finish_poll_wait` updated to accept optional count parameter
- [ ] Frame context is respected
- [ ] `cargo check` passes

### T017: Investigate and fix intermittent exit code 1 reliability issue

**File(s)**: `src/page/wait.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [ ] Root cause identified (session setup race, domain enablement, or poll loop error handling)
- [ ] Fix applied with clear comment explaining what was wrong
- [ ] Pre-satisfied conditions return exit code 0 reliably (no intermittent failures)
- [ ] Transient CDP errors during polling do not propagate as exit code 1
- [ ] `cargo check` passes

**Notes**: Investigate whether the error originates from `setup_session()`, `ensure_domain()`, or the poll loop. Check if `eval_js()` returning `None` on the first call can cascade to an error. Add guard logic as needed.

### T018: Update BDD feature file and step definitions for new conditions

**File(s)**: `tests/features/page-wait.feature`, `tests/bdd.rs`
**Type**: Modify
**Depends**: T015, T016, T017, T008, T009
**Acceptance**:
- [ ] 6 new scenarios added for AC9-AC14 (appended to existing scenarios)
- [ ] New scenarios tagged with `# Added by issue #195` comment
- [ ] Step definitions for new scenarios implemented in `tests/bdd.rs`
- [ ] Existing scenarios unmodified (backward compatible)
- [ ] `cargo test --test bdd` passes
- [ ] Valid Gherkin syntax

### T019: Manual smoke test for new conditions and verify no regressions

**File(s)**: (no file changes — execution only)
**Type**: Verify
**Depends**: T015, T016, T017, T018
**Acceptance**:
- [ ] Build debug binary: `cargo build`
- [ ] Connect to headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to test page
- [ ] Test `--js-expression`: `./target/debug/agentchrome page wait --js-expression "document.readyState === 'complete'"` returns successfully
- [ ] Test `--js-expression` falsy-then-truthy: verify polling works (e.g., expression that becomes truthy after delay)
- [ ] Test `--js-expression` error: `./target/debug/agentchrome page wait --js-expression "invalid(((" --timeout 2000` exits with code 1 and descriptive error
- [ ] Test `--selector --count`: `./target/debug/agentchrome page wait --selector "a" --count 2` returns successfully when page has >= 2 links
- [ ] Test `--count` without `--selector`: verify clap rejects it
- [ ] Test existing conditions still work (--url, --text, --selector without --count, --network-idle)
- [ ] Test `page wait --help` shows new examples for --js-expression and --count
- [ ] `cargo test --lib` passes (all unit tests including new truthiness/serialization tests)
- [ ] `cargo test --test bdd` passes (all BDD tests)
- [ ] `cargo clippy` passes with no new warnings
- [ ] `cargo fmt --check` passes
- [ ] Disconnect and kill Chrome: `./target/debug/agentchrome connect disconnect && pkill -f 'chrome.*--remote-debugging' || true`

---

## Dependency Graph

```
T001 (globset dep) ──────┐
                         ├──▶ T004 (core wait.rs) ──┬──▶ T005 (poll conditions) ──▶ T010 (unit tests)
T002 (CLI args) ─────────┤                          │
                         │                          ├──▶ T006 (network idle)
T003 (error ctor) ───────┘                          │
                                                    └──▶ T007 (wire dispatcher) ──┬──▶ T008 (feature file) ──▶ T009 (step defs)
                                                                                  ├──▶ T011 (smoke test)
                                                                                  └──▶ T012 (regressions)

                         Issue #195 Enhancement Tasks:
T002 ──▶ T013 (add --js-expression, --count to CLI args) ──┬──▶ T015 (JS expression poll path)
T003 ──▶ T014 (js_eval_error ctor, is_truthy helper)  ─────┘    │
                                                                  ├──▶ T018 (BDD + steps)
T013 ──▶ T016 (--count modifier for selector)  ───────────────────┤
                                                                  └──▶ T019 (smoke test + regressions)
T004 ──▶ T017 (reliability fix for exit code 1)  ─────────────────┘
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #163 | 2026-03-12 | Initial task breakdown (T001-T012) |
| #195 | 2026-04-16 | Add Phase 5 enhancement tasks (T013-T019): JS expression condition, selector count modifier, reliability fix, updated BDD tests and smoke test |

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included (BDD + unit + smoke)
- [x] No circular dependencies
- [x] Tasks are in logical execution order
