# Tasks: Fix interact click timeout when JavaScript dialog opens

**Issue**: #267
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Related Spec**: `specs/feature-browser-dialog-handling/`

---

## Task List

| ID | Task | Status |
|----|------|--------|
| T001 | Make click dispatch dialog-aware for native JavaScript dialog openings. | [x] |
| T002 | Add regression coverage for alert, prompt, and auto-dismiss click flows. | [x] |
| T003 | Verify focused interact/dialog behavior against a real headless Chrome session. | [x] |

---

## T001: Make Click Dispatch Dialog-Aware

**File(s)**: `src/interact.rs`

Acceptance:
- [x] `interact click` subscribes to `Page.javascriptDialogOpening` before dispatch when `--auto-dismiss-dialogs` is not active.
- [x] `interact click-at` uses the same dialog-aware dispatch behavior.
- [x] A dialog-opening mouse release no longer returns `Interaction failed (mouse_release): CDP command timed out: Input.dispatchMouseEvent`.
- [x] Non-dialog click behavior remains unchanged.

## T002: Add Regression Coverage

**File(s)**: `tests/features/267-fix-interact-click-timeout-when-javascript-dialog-opens.feature`, focused Rust tests where practical.

Acceptance:
- [x] Defect Gherkin scenarios map to AC1-AC3 and are tagged `@regression`.
- [x] Manual smoke verifies alert and prompt flows against `https://the-internet.herokuapp.com/javascript_alerts` or an equivalent local fixture.
- [x] Auto-dismiss click still exits 0 and leaves no dialog open.

## T003: Verify

**File(s)**: `CHANGELOG.md`, `VERSION`, `Cargo.toml`, `Cargo.lock`

Acceptance:
- [x] `cargo fmt --check` passes.
- [x] Focused interact tests pass.
- [x] Real-headless Chrome smoke covers alert, prompt, and auto-dismiss paths.
- [x] Patch version and changelog include issue #267.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #267 | 2026-04-25 | Initial defect task plan |
