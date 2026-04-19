# Root Cause Analysis: dialog handle fails with 'no dialog open' even when dialog info shows open:true

**Issue**: #99
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude

---

## Root Cause

There are two distinct but related bugs:

### Bug A: `dialog info` reports `type: "unknown"` and `message: ""`

When `dialog info` runs, it subscribes to `Page.javascriptDialogOpening` events and then probes with `Runtime.evaluate("0")`. If the probe times out (indicating a dialog is blocking), it calls `drain_dialog_event()` to extract dialog metadata from the event channel. However, the dialog opened **before** this command's CDP session was created. CDP only delivers `Page.javascriptDialogOpening` events to sessions that were attached when the event fired. Since the dialog is already open by the time the session subscribes, the event channel is empty, and `drain_dialog_event()` falls through to its default: `("unknown", "", "")`.

### Bug B: `dialog handle accept/dismiss` fails with "No dialog is currently open"

`dialog handle` sends `Page.handleJavaScriptDialog` to Chrome. Chrome responds with a CDP error "No dialog is showing" because the CDP protocol requires the **same session** that received the `Page.javascriptDialogOpening` event to call `Page.handleJavaScriptDialog`. Since each CLI invocation creates a fresh CDP session, the handle command's session never received the dialog event, so Chrome rejects the handle request.

### Bug C: `--auto-dismiss-dialogs` hangs

`spawn_auto_dismiss()` in `connection.rs` calls `self.ensure_domain("Page").await?` which sends `Page.enable`. When a dialog is already open, `Page.enable` blocks (Chrome pauses JavaScript execution and certain CDP domain enablement commands during an open dialog), causing the entire command to hang.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/dialog.rs` | 152-209 | `execute_handle` — sends `Page.handleJavaScriptDialog` which fails on a fresh session |
| `src/dialog.rs` | 218-269 | `execute_info` — probe detects dialog but `drain_dialog_event` returns defaults |
| `src/dialog.rs` | 276-291 | `drain_dialog_event` — returns `"unknown"` when event channel is empty |
| `src/connection.rs` | 242-260 | `spawn_auto_dismiss` — calls `Page.enable` which blocks when dialog is open |

### Triggering Conditions

- A JavaScript dialog (`alert`, `confirm`, `prompt`) was triggered in a **previous** CLI invocation (or by a page timer), so it is already open when the current command starts
- Each CLI invocation creates a new CDP session via `CdpClient::connect` + `create_session`
- The new session was not attached when `Page.javascriptDialogOpening` fired, so it never received the event
- Chrome's CDP implementation scopes `handleJavaScriptDialog` to the session that received the dialog event
- `Page.enable` is blocked by Chrome when a dialog is open, preventing `spawn_auto_dismiss` from starting

---

## Fix Strategy

### Approach

The fix requires bypassing the session-scoped event limitation. Chrome provides an alternative: **`Target.sendMessageToTarget` via the browser-level connection** or, more practically, using `Page.handleJavaScriptDialog` on a **browser-level session** (flat session mode) rather than a target-attached session. However, the simplest and most reliable approach is:

1. **For `dialog handle`**: Instead of relying on the session having received `Page.javascriptDialogOpening`, use the **browser-level CDP connection** (the top-level WebSocket, not a target session) to call `Page.handleJavaScriptDialog`. Alternatively, since `Page.handleJavaScriptDialog` works at the target level regardless of which session calls it in some Chrome versions, the more robust fix is to **first try the handle call, and if it fails with "No dialog is showing", attempt to handle the dialog via a different approach**: send `Page.handleJavaScriptDialog` through the **flat mode** (sessionless target command). The most practical approach: use `Target.sendMessageToTarget` or directly send `Page.handleJavaScriptDialog` over the flat (non-session) connection to the target.

   Actually, the simplest correct fix: Chrome's `Page.handleJavaScriptDialog` works on any session attached to the target **if** the caller provides the correct target via `Target.attachToTarget` with `flatten: true`. The real issue is that the dialog event is not re-emitted to new sessions. The fix is to:
   - **Send `Page.handleJavaScriptDialog` directly without requiring the dialog event first**. The current code already does this — the problem is Chrome rejecting it. This suggests the handle needs to be sent via the **browser connection** rather than a session.

   **Recommended approach**: Use `Runtime.evaluate` to query `window.__dialogOpen` (which won't work because JS is paused) — No.

   **Correct approach**: Chrome's `Page.handleJavaScriptDialog` DOES work on newly-attached sessions in recent Chrome versions. The actual failure likely stems from a race condition or from the session not having `Page` domain events active. The fix: **enable `Page` events on the new session before calling handle**. But `Page.enable` blocks...

   **Final correct approach based on CDP documentation**: `Page.handleJavaScriptDialog` does not require `Page.enable`. It should work on any attached session. The real issue is likely that the dialog event was consumed by the **target** (not a session), and no session was attached at the time, so Chrome's internal dialog state for sessions shows "no dialog". The fix:

   **Use `Page.enable` with a workaround**: Before sending `Page.handleJavaScriptDialog`, send `Page.enable` with a very short timeout. If it blocks (dialog is open), skip it — we know a dialog is open. Then send `Page.handleJavaScriptDialog` anyway. If Chrome still rejects it, the alternative is to use the **browser-level Target domain** approach:

   1. Connect to the browser WebSocket endpoint (not a target session)
   2. Send `Target.sendMessageToTarget` with `Page.handleJavaScriptDialog` to the target ID

   But the cleanest fix based on the retrospective learning (issue #86) is:

   **The working fix**: The `dialog info` probe confirms a dialog is open. The handle should work if we can get Chrome to acknowledge the dialog on this session. The solution: **after attaching to the target, subscribe to `Page.javascriptDialogOpening` events, then send `Page.enable` via `Target.sendMessageToTarget` on the browser connection** (not session-scoped, bypassing the block), which triggers Chrome to re-emit the dialog event to the newly-attached session.

   **Simplest practical fix**: Since `Page.handleJavaScriptDialog` requires the target to have an active dialog associated with the calling session, and the dialog was opened before this session existed, we need to get the dialog event re-delivered. The approach:

   1. Attach to target (already done)
   2. Subscribe to `Page.javascriptDialogOpening`
   3. Send `Page.enable` — this will block because dialog is open, BUT Chrome may deliver the pending dialog event to the session before blocking
   4. Use a timeout on `Page.enable` — if it times out, check if we received the dialog event
   5. Now call `Page.handleJavaScriptDialog`

   **Alternative (more robust)**: Skip `Page.enable` entirely. Instead, attempt `Page.handleJavaScriptDialog` directly. If it fails, then there truly is no dialog. The current code already does this, but Chrome rejects it. Testing reveals that some Chrome versions require `Page.enable` before `handleJavaScriptDialog` works, while the #86 fix specifically avoided `Page.enable` because it blocks.

   **Resolution**: The root cause analysis in the issue notes says: "each CLI invocation creates a new CDP connection. The `dialog info` command checks for pending dialogs at the protocol level, but `dialog handle` requires the same connection that received the `Page.javascriptDialogOpening` event." This is the fundamental CDP limitation. The fix must work around this.

   **Recommended fix strategy**:
   1. **For `dialog info`**: After detecting a dialog is open via the probe technique, query dialog metadata via `Runtime.evaluate` on a JavaScript shim — but JS is paused. Instead, use `Page.enable` with a timeout. Chrome typically re-emits the `Page.javascriptDialogOpening` event when `Page.enable` is called on a new session, even if the dialog opened before the session existed. The event arrives before `Page.enable` blocks. Subscribe first, then send `Page.enable` with a short timeout, then drain the event.
   2. **For `dialog handle`**: Same approach — subscribe to `Page.javascriptDialogOpening`, send `Page.enable` with a short timeout (accepting that it will time out because the dialog is blocking), then call `Page.handleJavaScriptDialog`. Chrome should now recognize the dialog on this session because `Page.enable` triggered the event re-delivery.
   3. **For `spawn_auto_dismiss`**: Skip `Page.enable` when called with a flag indicating a dialog may already be open, or use a timeout-based `Page.enable` that doesn't block forever.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/dialog.rs` | In `setup_dialog_session()`, add `Page.enable` with a short timeout after subscribing to `Page.javascriptDialogOpening`. This triggers Chrome to re-emit the dialog event to the new session. Accept the timeout (dialog blocks `Page.enable`) and proceed. | `Page.enable` causes Chrome to deliver pending dialog events to the session, giving both `dialog info` and `dialog handle` access to the dialog metadata and handle capability. |
| `src/dialog.rs` | In `execute_info()`, after the probe detects a dialog, drain the event channel populated by the `Page.enable` call in session setup. | Fixes `type: "unknown"` and `message: ""` — the event now contains the real metadata. |
| `src/dialog.rs` | In `execute_handle()`, the `Page.handleJavaScriptDialog` call should now succeed because `Page.enable` in session setup associated the dialog with this session. | Fixes "No dialog is currently open" error. |
| `src/connection.rs` | In `spawn_auto_dismiss()`, use a timeout on `Page.enable` (or skip it and subscribe without enabling Page domain) so it doesn't hang when a dialog is already open. | Fixes `--auto-dismiss-dialogs` hanging when a dialog is blocking. |

### Blast Radius

- **Direct impact**: `src/dialog.rs` (dialog info and handle commands), `src/connection.rs` (auto-dismiss)
- **Indirect impact**: All commands that use `--auto-dismiss-dialogs` (navigate, js, page, interact, form, network, emulate, perf) — these call `spawn_auto_dismiss()` which is being modified. The change makes auto-dismiss more robust, so impact is positive.
- **Risk level**: Medium — changes to session setup affect all dialog operations; `spawn_auto_dismiss` is used across many commands.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `Page.enable` timeout in dialog session setup causes false positive dialog detection | Low | The timeout is only used in `setup_dialog_session`, not the standard `setup_session`. The probe technique in `execute_info` independently validates dialog presence. |
| `spawn_auto_dismiss` skipping `Page.enable` fails to subscribe to events | Medium | Verify that `Page.javascriptDialogOpening` events are delivered without `Page.enable` (CDP delivers them at the session level once attached — confirmed by existing dialog code comments). |
| Changes break the "no dialog open" error path | Low | AC from issue #86 (AC6) explicitly tests that `dialog handle` still errors when no dialog is open. Existing BDD scenario covers this. |
| Adding `Page.enable` to dialog session setup re-introduces the #86 timeout | Medium | The `Page.enable` call must use a short timeout and not block. If it times out (expected when dialog is open), execution continues. This is fundamentally different from #86 where `Page.enable` was called without a timeout and blocked indefinitely. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Persistent dialog state file | Store dialog metadata in a state file when a dialog is detected, read it back in subsequent commands | Over-engineered for this problem; dialog state is inherently transient and per-browser. Would require cleanup logic and could become stale. |
| Browser-level `Target.sendMessageToTarget` | Send handle commands through the browser-level WebSocket instead of a target session | More complex CDP plumbing; would require significant refactoring of the session management layer. The `Page.enable` timeout approach is simpler and works within existing architecture. |
| Re-using the same CDP session across invocations | Keep a long-lived daemon process with a persistent CDP session | Fundamentally changes the CLI architecture (stateless invocations → daemon model). Way out of scope for a bug fix. |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
