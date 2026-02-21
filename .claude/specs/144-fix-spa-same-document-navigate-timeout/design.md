# Root Cause Analysis: Fix navigate back/forward timeout on SPA same-document history navigations

**Issue**: #144
**Date**: 2026-02-19
**Status**: Draft
**Author**: Claude

---

## Root Cause

The `execute_back()` and `execute_forward()` functions in `src/navigate.rs` subscribe exclusively to the `Page.frameNavigated` CDP event to detect when history navigation completes. This event fires for **cross-document** navigations (full page loads, cross-origin navigations), which is why the #72 fix correctly resolved cross-origin timeout issues.

However, SPA frameworks (React Router, Vue Router, etc.) create history entries via `history.pushState()`. When navigating back/forward through these entries, Chrome performs a **same-document navigation** — the URL changes but no frame-level navigation occurs. For same-document navigations, Chrome fires `Page.navigatedWithinDocument` instead of `Page.frameNavigated`. Since the code only listens for `Page.frameNavigated`, the event never arrives, and the `wait_for_event` function blocks until the 30-second timeout expires.

The navigation itself succeeds (verified by querying `window.location.href` after the timeout), but the command reports failure because it never received the expected completion event.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/navigate.rs` | 238 | `execute_back` subscribes only to `Page.frameNavigated` |
| `src/navigate.rs` | 298 | `execute_forward` subscribes only to `Page.frameNavigated` |
| `src/navigate.rs` | 352–373 | `wait_for_event` waits for a single event receiver |

### Triggering Conditions

- The browser has history entries created by `history.pushState()` (SPA client-side routing)
- The user runs `agentchrome navigate back` or `agentchrome navigate forward` through those entries
- Chrome fires `Page.navigatedWithinDocument` instead of `Page.frameNavigated`
- The `wait_for_event` function never receives the expected event and times out

---

## Fix Strategy

### Approach

Subscribe to **both** `Page.frameNavigated` and `Page.navigatedWithinDocument` events before issuing the history navigation command. Introduce a new helper function `wait_for_history_navigation` that uses `tokio::select!` to resolve as soon as **either** event fires. This preserves the existing cross-document behavior (where `Page.frameNavigated` fires) while adding support for same-document navigations (where `Page.navigatedWithinDocument` fires).

The existing `wait_for_event` function is preserved unchanged — it is used by `execute_reload`, which only expects `Page.frameNavigated` (reloads are always cross-document). The new helper is specific to back/forward history navigation.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/navigate.rs` (`execute_back`) | Subscribe to both `Page.frameNavigated` and `Page.navigatedWithinDocument`; call `wait_for_history_navigation` instead of `wait_for_event` | Detects completion for both cross-document and same-document history navigations |
| `src/navigate.rs` (`execute_forward`) | Same change as `execute_back` | Same root cause applies to forward navigation |
| `src/navigate.rs` (new function) | Add `wait_for_history_navigation` that accepts two receivers and uses `tokio::select!` to wait for either | Reusable helper that encapsulates the dual-event wait logic |

### Blast Radius

- **Direct impact**: `execute_back` and `execute_forward` in `src/navigate.rs`
- **Indirect impact**: None — no other code calls these functions; the `wait_for_event` function is left unchanged for `execute_reload`
- **Risk level**: Low — the change is additive (subscribing to one additional event) and the `tokio::select!` pattern is identical to the existing `wait_for_event` logic

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Cross-document navigate back/forward breaks | Low | `Page.frameNavigated` subscription is preserved; `tokio::select!` still resolves on it. AC3 and AC4 verify this explicitly. |
| `wait_for_event` callers affected | None | `wait_for_event` is unchanged; the new function is separate |
| Double-fire (both events fire for the same navigation) | Low | `tokio::select!` resolves on the first event and drops the other receiver — no issue |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Non-blocking `try_recv` with sleep (like `interact click`) | Sleep 100ms then check if any event arrived | Less reliable for slow navigations; the back/forward commands should confirm completion, not guess. The `interact click` pattern is appropriate there because click may or may not trigger navigation. |
| Modify `wait_for_event` to accept multiple receivers | Generalize the existing function | Over-engineering — only back/forward need dual-event detection. `execute_reload` and other callers should not be changed. |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
