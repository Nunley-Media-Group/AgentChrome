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
- [ ] `FormSubmitArgs` struct defined with `target: String` and `include_snapshot: bool` fields
- [ ] `FormCommand::Submit(FormSubmitArgs)` variant added to the enum
- [ ] `Submit` variant has `long_about` and `after_long_help` documentation consistent with other form subcommands
- [ ] Help examples show UID and CSS selector usage
- [ ] `FormSubmitArgs` is exported in the module's imports
- [ ] `cargo check` passes

**Notes**: Follow the exact pattern of `FormFillArgs` / `FormClearArgs`. The positional arg is `target`, the optional flag is `--include-snapshot`.

### T002: Add `not_in_form` error helper to AppError

**File(s)**: `src/error.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `AppError::not_in_form(target: &str) -> Self` method added
- [ ] Error message clearly states the element is not a form and not inside a form
- [ ] Uses `ExitCode::TargetError` (exit code 3)
- [ ] Unit test added for the new error helper
- [ ] `cargo check` passes

**Notes**: Follow the pattern of `not_file_input()`.

---

## Phase 2: Backend Implementation

### T003: Add SubmitResult output type and print helper

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `SubmitResult` struct with `submitted: String`, optional `url: Option<String>`, optional `snapshot: Option<serde_json::Value>`
- [ ] `url` and `snapshot` fields use `#[serde(skip_serializing_if = "Option::is_none")]`
- [ ] `print_submit_plain()` helper for plain text output
- [ ] Unit tests for `SubmitResult` serialization (without url, with url, with snapshot)
- [ ] `cargo check` passes

### T004: Implement FIND_FORM_JS and SUBMIT_JS constants

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `FIND_FORM_JS` constant: JavaScript function that checks if `this` is a `<form>`, if so returns true; otherwise calls `this.closest('form')` and returns whether a form was found
- [ ] `SUBMIT_JS` constant: JavaScript function that calls `this.requestSubmit()` on the form element
- [ ] JavaScript handles the case where `closest('form')` returns null (throws an error that CDP will propagate)

**Notes**: `FIND_FORM_JS` should be called on the resolved target element. It returns an object `{ isForm: bool, formFound: bool }` or similar so the Rust code can determine next steps. Alternatively, it can directly return the form element's reference. The design uses `Runtime.callFunctionOn` which allows returning object references.

### T005: Implement execute_submit function and update dispatcher

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001, T002, T003, T004
**Acceptance**:
- [ ] `execute_submit()` async function follows the pattern of `execute_fill()` / `execute_clear()`
- [ ] Sets up session via `setup_session()`
- [ ] Enables DOM, Runtime, and Page domains
- [ ] Resolves target to object ID via `resolve_to_object_id()`
- [ ] Uses `FIND_FORM_JS` to locate the enclosing form; returns `AppError::not_in_form()` if no form found
- [ ] Subscribes to `Page.frameNavigated` before submitting
- [ ] Records pre-submit URL via `get_current_url()`
- [ ] Calls `SUBMIT_JS` on the resolved form element via `Runtime.callFunctionOn`
- [ ] Waits 100ms grace period, checks for `frameNavigated` event
- [ ] If navigated, gets post-submit URL
- [ ] If `--include-snapshot`, takes snapshot via `take_snapshot()`
- [ ] Builds `SubmitResult` and outputs via `print_output()` or `print_submit_plain()`
- [ ] `execute_form()` dispatcher updated: `FormCommand::Submit(args) => execute_submit(global, args).await`
- [ ] `FormSubmitArgs` added to the import list from `crate::cli`
- [ ] `cargo check` passes

---

## Phase 3: Integration

### T006: Verify CLI integration end-to-end

**File(s)**: `src/cli/mod.rs`, `src/form.rs`, `src/main.rs`
**Type**: Verify (no file changes expected)
**Depends**: T005
**Acceptance**:
- [ ] `cargo build` succeeds
- [ ] `./target/debug/agentchrome form --help` lists "submit" as a subcommand
- [ ] `./target/debug/agentchrome form submit --help` shows TARGET and --include-snapshot
- [ ] `./target/debug/agentchrome form submit` (no args) produces a non-zero exit code with usage error
- [ ] Existing form subcommands (`fill`, `clear`, `upload`, `fill-many`) are unaffected

---

## Phase 4: BDD Testing

### T007: Create BDD feature file for form submit

**File(s)**: `tests/features/form-submit.feature`
**Type**: Create
**Depends**: T005
**Acceptance**:
- [ ] All acceptance criteria from requirements.md are scenarios
- [ ] CLI-testable scenarios (help, missing args) are active (not commented)
- [ ] Chrome-dependent scenarios are documented as commented scenarios
- [ ] Uses Given/When/Then format
- [ ] Feature file is valid Gherkin syntax

### T008: Implement step definitions for form submit BDD scenarios

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] CLI-testable scenarios have working step definitions
- [ ] Steps reuse existing patterns (agentchrome is built, run command, check exit code, check stdout/stderr)
- [ ] All active scenarios pass: `cargo test --test bdd`

### T009: Manual smoke test against headless Chrome

**File(s)**: (none — verification only)
**Type**: Verify
**Depends**: T005, T006
**Acceptance**:
- [ ] Build debug binary: `cargo build`
- [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to a page with a form (e.g., https://www.saucedemo.com/)
- [ ] Take snapshot: `./target/debug/agentchrome page snapshot`
- [ ] Submit the login form: `./target/debug/agentchrome form submit <FORM_UID>`
- [ ] Verify JSON output includes `submitted` key
- [ ] Verify no regressions in `form fill`, `form clear`
- [ ] Disconnect: `./target/debug/agentchrome connect disconnect`
- [ ] Kill orphaned Chrome processes

---

## Dependency Graph

```
T001 ──┬──▶ T003 ──▶ T005 ──▶ T006 ──▶ T009
       │              ▲
T002 ──┘              │
                      │
T004 ─────────────────┘

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
- [x] BDD test tasks included
- [x] No circular dependencies
- [x] Tasks are in logical execution order
