# Design: Fix interact click timeout when JavaScript dialog opens

**Issue**: #267
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Related Spec**: `specs/feature-browser-dialog-handling/`

---

## Root Cause Analysis

`src/interact.rs::dispatch_click` sends `Input.dispatchMouseEvent` for mouse press and mouse release, then waits for each CDP command response. When the release event synchronously opens a native JavaScript dialog, Chrome blocks the renderer before the release response reaches AgentChrome. The transport eventually returns `CdpError::CommandTimeout { method: "Input.dispatchMouseEvent" }`, which `dispatch_click` maps to `AppError::interaction_failed("mouse_release", ...)` and exit code 5.

The click itself succeeded: a subsequent `agentchrome dialog info` reports `open=true` with the alert or prompt metadata, and `agentchrome dialog handle` can accept it. Existing `--auto-dismiss-dialogs` behavior succeeds because that path subscribes to and handles dialog events before process exit. The missing default-path behavior is to recognize "dialog opened" as a successful click outcome rather than waiting for a release response that Chrome will not send while the dialog is blocking.

## Minimal Fix Strategy

Subscribe to `Page.javascriptDialogOpening` before dispatching click events on non-auto-dismiss `interact click` and `interact click-at` paths. Route mouse dispatch through a helper that races the mouse-release CDP response against the dialog-opening event. If the dialog event arrives first, treat the click dispatch as successful and allow the command to emit its normal clicked JSON result. Follow-up `dialog info` / `dialog handle` remains responsible for inspecting or closing the dialog.

| File | Change |
|------|--------|
| `src/interact.rs` | Add dialog-aware mouse event dispatch helper and thread an optional dialog-opening receiver through `dispatch_click`. |
| `src/interact.rs` | Subscribe to `Page.javascriptDialogOpening` for `click` and `click-at` when `--auto-dismiss-dialogs` is not active. |
| `tests/features/267-fix-interact-click-timeout-when-javascript-dialog-opens.feature` | Add regression scenarios for alert, prompt, and auto-dismiss behavior. |

## Blast Radius

- Directly affects `interact click` and `interact click-at`.
- Does not change `dialog info` or `dialog handle` output contracts.
- Does not change the successful `--auto-dismiss-dialogs` path.
- Adds one event subscription for default click paths. This is local to the active CDP session and only watches native JavaScript dialog openings.

## Regression Risk

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| A normal non-dialog click could return early incorrectly. | Low | High | Only return early when `Page.javascriptDialogOpening` is actually received; otherwise await the dispatch response exactly as before. |
| Click-at behavior diverges from click behavior. | Medium | Medium | Reuse the same `dispatch_click` helper for both command paths. |
| Auto-dismiss behavior changes. | Low | High | Keep the existing `spawn_auto_dismiss_with_settle` flow unchanged and do not install the new default-path receiver when auto-dismiss is active. |

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #267 | 2026-04-25 | Initial defect design |
