# Tasks: Form Submit Subcommand

**Issues**: #147
**Date**: 2026-02-26
**Status**: Planning
**Author**: Claude (nmg-sdlc)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 3 | [ ] |
| Integration | 1 | [ ] |
| Testing | 3 | [ ] |
| **Total** | **9** | |

---

## Phase 1: Setup

### T001: Add FormSubmitArgs and Submit variant to CLI

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `FormCommand` enum has a `Submit(FormSubmitArgs)` variant
- [ ] `FormSubmitArgs` struct has `target: String` and `include_snapshot: bool` fields
- [ ] Submit variant has descriptive `long_about` and `after_long_help` with examples
- [ ] `agentchrome form submit --help` shows TARGET and --include-snapshot
- [ ] `agentchrome form --help` lists "submit" in subcommands
- [ ] `cargo build` succeeds without warnings

**Notes**: Follow the exact pattern of `FormFillArgs` / `FormClearArgs` for the struct. The `Submit` variant should be placed after `Upload` in the enum to maintain alphabetical-ish ordering. Import `FormSubmitArgs` in `src/form.rs`.

### T002: Add not_in_form error constructor to AppError

**File(s)**: `src/error.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `AppError::not_in_form(target: &str)` constructor exists
- [ ] Returns message `"No form found for target: {target}"`
- [ ] Uses `ExitCode::GeneralError`
- [ ] Unit test for the error constructor passes

**Notes**: Follow the pattern of `not_file_input()`. Add a corresponding unit test in the `tests` module at the bottom of `error.rs`.

---

## Phase 2: Backend Implementation

### T003: Add SubmitResult output type and formatting

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `SubmitResult` struct with `submitted: String`, optional `url: Option<String>`, optional `snapshot: Option<serde_json::Value>`
- [ ] `url` and `snapshot` fields use `#[serde(skip_serializing_if = "Option::is_none")]`
- [ ] `print_submit_plain()` function prints `"Submitted <target>"` format
- [ ] Unit tests for `SubmitResult` serialization pass (with/without url, with/without snapshot)

**Notes**: Follow the pattern of `FillResult`, `ClearResult`, `UploadResult` in the same file.

### T004: Implement SUBMIT_JS and execute_submit function

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T002, T003
**Acceptance**:
- [ ] `SUBMIT_JS` const defined: resolves `this` to form (self or `closest('form')`), calls `requestSubmit()`, returns `{ found: true/false }`
- [ ] `execute_submit()` async function implemented following the established pattern:
  1. `setup_session()` with auto-dismiss dialogs
  2. Enable `DOM`, `Runtime`, `Page` domains
  3. Resolve target via `resolve_to_object_id()`
  4. Subscribe to `Page.frameNavigated` before submit
  5. Call `SUBMIT_JS` via `Runtime.callFunctionOn` with `returnByValue: true`
  6. Check JS return value for `found: false` and return `AppError::not_in_form()` if so
  7. Wait 100ms, check navigation via `try_recv()`
  8. Get current URL if navigated
  9. Optionally take snapshot
  10. Build and print `SubmitResult`
- [ ] Handles both `--plain` and JSON output modes
- [ ] `cargo build` succeeds without warnings
- [ ] `cargo clippy` passes

**Notes**: Follow the click-with-navigation pattern from `interact.rs` for navigation detection. Use `managed.subscribe("Page.frameNavigated")` before the submit call.

### T005: Wire Submit variant into execute_form dispatcher

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001, T004
**Acceptance**:
- [ ] `execute_form()` match has `FormCommand::Submit(submit_args) => execute_submit(global, submit_args).await`
- [ ] Import of `FormSubmitArgs` is added to the `use crate::cli::` block at top of file
- [ ] `cargo build` succeeds
- [ ] No changes needed to `main.rs` (dispatch already routes `Form` to `execute_form`)

---

## Phase 3: Integration

### T006: Verify end-to-end CLI wiring

**File(s)**: (no file changes -- verification only)
**Type**: Verify
**Depends**: T005
**Acceptance**:
- [ ] `cargo build` succeeds
- [ ] `cargo clippy` passes with no warnings
- [ ] `cargo fmt --check` passes
- [ ] Running `./target/debug/agentchrome form submit --help` shows correct help
- [ ] Running `./target/debug/agentchrome form --help` lists submit
- [ ] Running `./target/debug/agentchrome form submit` (no args) returns nonzero exit and error message

---

## Phase 4: Testing

### T007: Create BDD feature file

**File(s)**: `tests/features/form-submit.feature`
**Type**: Create
**Depends**: T005
**Acceptance**:
- [ ] All acceptance criteria from requirements.md are represented as scenarios
- [ ] CLI argument validation scenarios (AC8, AC9, AC10) are active (not commented)
- [ ] Chrome-required scenarios (AC1-AC7, AC11) are documented as comments
- [ ] Uses Given/When/Then format matching existing feature file conventions
- [ ] Feature file is valid Gherkin syntax

**Notes**: Follow the pattern from `tests/features/form.feature` -- active scenarios for CLI validation, commented scenarios for Chrome-dependent tests.

### T008: Implement BDD step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] No new step definitions needed -- existing `CliWorld` steps handle all active scenarios:
  - `"agentchrome is built"` given step
  - `"I run {string}"` when step
  - `"the exit code should be {int}"` / `"the exit code should be nonzero"` then steps
  - `"stdout should contain {string}"` / `"stderr should contain {string}"` then steps
- [ ] `cargo test --test bdd` passes with all new scenarios green
- [ ] No regressions in existing BDD tests

### T009: Smoke test against real Chrome and SauceDemo

**File(s)**: (no file changes -- manual verification)
**Type**: Verify
**Depends**: T006
**Acceptance**:
- [ ] Build in debug mode: `cargo build`
- [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to SauceDemo: `./target/debug/agentchrome navigate https://www.saucedemo.com/`
- [ ] Take snapshot: `./target/debug/agentchrome page snapshot`
- [ ] Fill username field: `./target/debug/agentchrome form fill <UID> "standard_user"`
- [ ] Fill password field: `./target/debug/agentchrome form fill <UID> "secret_sauce"`
- [ ] Submit the login form: `./target/debug/agentchrome form submit <FORM_UID_OR_CHILD>`
- [ ] Verify output contains `submitted` key and `url` field showing inventory page
- [ ] Test error case: submit on element not in a form returns error
- [ ] Disconnect: `./target/debug/agentchrome connect disconnect`
- [ ] Kill orphaned Chrome processes: `pkill -f 'chrome.*--remote-debugging' || true`
- [ ] SauceDemo baseline: navigate + snapshot passes

---

## Dependency Graph

```
T001 ──┬──▶ T003 ──▶ T004 ──▶ T005 ──▶ T006 ──▶ T009
       │                ▲
T002 ──┘                │
                        │
T005 ──▶ T007 ──▶ T008
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #147 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included (T007, T008, T009)
- [x] No circular dependencies
- [x] Tasks are in logical execution order
- [x] Smoke test task included (T009) per tech.md requirements
