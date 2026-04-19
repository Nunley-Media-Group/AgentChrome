# Tasks: dialog handle fails with 'no dialog open' even when dialog info shows open:true

**Issue**: #99
**Date**: 2026-02-15
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Fix dialog session setup to enable Page domain with timeout | [ ] |
| T002 | Fix spawn_auto_dismiss to not block on Page.enable | [ ] |
| T003 | Add regression tests | [ ] |
| T004 | Verify no regressions | [ ] |

---

### T001: Fix Dialog Session Setup and Commands

**File(s)**: `src/dialog.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `setup_dialog_session()` subscribes to `Page.javascriptDialogOpening` and sends `Page.enable` with a short timeout, so Chrome re-emits the dialog event to the new session
- [ ] `execute_info()` correctly reports dialog `type` and `message` from the re-emitted event (not `"unknown"` / `""`)
- [ ] `execute_handle()` successfully calls `Page.handleJavaScriptDialog` because the session received the dialog event via `Page.enable`
- [ ] When no dialog is open, `dialog info` still reports `open: false` and `dialog handle` still errors appropriately
- [ ] No unrelated changes included in the diff

**Notes**: The key insight is that `Page.enable` triggers Chrome to re-emit `Page.javascriptDialogOpening` to the newly-attached session. The `Page.enable` call will block/timeout because the dialog is open, but the event is delivered before the block occurs. Use a short timeout (similar to the existing 200ms probe timeout) and treat timeout as expected behavior. The dialog event subscription must be set up before `Page.enable` is sent.

### T002: Fix spawn_auto_dismiss to Handle Pre-existing Dialogs

**File(s)**: `src/connection.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `spawn_auto_dismiss()` does not call `ensure_domain("Page")` (or uses a timeout-based approach) so it doesn't block when a dialog is already open
- [ ] `spawn_auto_dismiss()` still correctly auto-dismisses dialogs that appear during command execution
- [ ] Commands using `--auto-dismiss-dialogs` no longer hang when a dialog is already blocking
- [ ] No unrelated changes included in the diff

**Notes**: CDP delivers `Page.javascriptDialogOpening` events at the session level once attached, without requiring `Page.enable` (confirmed by existing code comments in `dialog.rs` lines 156-159). Remove or timeout the `ensure_domain("Page")` call. Consider also handling the pre-existing dialog by subscribing, sending `Page.enable` with a timeout (to trigger re-emission), and dismissing the re-emitted dialog event.

### T003: Add Regression Tests

**File(s)**: `tests/features/dialog-handle-no-dialog-open-fix.feature`, `tests/bdd.rs`
**Type**: Create / Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] Gherkin scenario reproduces the original bug condition (dialog opened by previous command, new command's handle/info works)
- [ ] Scenarios tagged `@regression`
- [ ] Step definitions implemented (or reuse existing dialog step definitions)
- [ ] Tests pass with the fix applied
- [ ] Tests fail if the fix is reverted (confirms they catch the bug)

### T004: Verify No Regressions

**File(s)**: existing test files
**Type**: Verify (no file changes)
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] All existing tests pass (`cargo test`)
- [ ] Existing dialog BDD scenarios still pass
- [ ] `--auto-dismiss-dialogs` works for commands that use it (navigate, js, etc.)
- [ ] No side effects in related code paths (per blast radius from design.md)

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T003)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
