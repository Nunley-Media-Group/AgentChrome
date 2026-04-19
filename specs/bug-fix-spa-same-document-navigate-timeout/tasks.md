# Tasks: Fix navigate back/forward timeout on SPA same-document history navigations

**Issue**: #144
**Date**: 2026-02-19
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Fix the defect | [ ] |
| T002 | Add regression test | [ ] |
| T003 | Run manual smoke test | [ ] |
| T004 | Verify no regressions | [ ] |

---

### T001: Fix the Defect

**File(s)**: `src/navigate.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] New `wait_for_history_navigation` function added that accepts two `mpsc::Receiver<CdpEvent>` (one for `Page.frameNavigated`, one for `Page.navigatedWithinDocument`) and uses `tokio::select!` to resolve on whichever fires first, with the same timeout behavior as `wait_for_event`
- [ ] `execute_back` subscribes to both `Page.frameNavigated` and `Page.navigatedWithinDocument` before calling `Page.navigateToHistoryEntry`, and calls `wait_for_history_navigation` instead of `wait_for_event`
- [ ] `execute_forward` subscribes to both `Page.frameNavigated` and `Page.navigatedWithinDocument` before calling `Page.navigateToHistoryEntry`, and calls `wait_for_history_navigation` instead of `wait_for_event`
- [ ] `wait_for_event` is unchanged (still used by `execute_reload`)
- [ ] `cargo build` succeeds
- [ ] `cargo clippy` passes with no new warnings
- [ ] `cargo fmt --check` passes

**Notes**: Follow the fix strategy from design.md. The new helper function should mirror the structure of `wait_for_event` but use `tokio::select!` across both receivers plus the timeout.

### T002: Add Regression Test

**File(s)**: `tests/features/144-fix-spa-same-document-navigate-timeout.feature`, `tests/bdd.rs`
**Type**: Create / Modify
**Depends**: T001
**Acceptance**:
- [ ] Gherkin feature file covers AC1 (SPA back), AC2 (SPA forward), AC3 (cross-document back regression), AC4 (cross-origin back regression)
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions implemented in `tests/bdd.rs` (or reuse existing navigate steps)
- [ ] `cargo test --test bdd` passes (BDD tests that don't require Chrome pass)

### T003: Run Manual Smoke Test

**File(s)**: None (verification only)
**Type**: Verify
**Depends**: T001, T002
**Acceptance**:
- [ ] Build debug binary: `cargo build`
- [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Reproduce the original bug steps from requirements.md against saucedemo.com and confirm `navigate back` now succeeds (exit code 0, correct URL in output)
- [ ] Verify `navigate forward` also works after navigating back
- [ ] Verify cross-document `navigate back` still works (navigate to two different URLs, then back)
- [ ] Run SauceDemo smoke test (navigate + snapshot baseline check)
- [ ] Disconnect and kill orphaned Chrome processes

### T004: Verify No Regressions

**File(s)**: Existing test files
**Type**: Verify (no file changes)
**Depends**: T001, T002
**Acceptance**:
- [ ] `cargo test --lib` passes (unit tests)
- [ ] `cargo test --test bdd` passes (BDD tests)
- [ ] `cargo clippy` passes
- [ ] `cargo fmt --check` passes
- [ ] No side effects in `execute_reload` or other navigate functions

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
