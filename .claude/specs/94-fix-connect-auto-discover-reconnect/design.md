# Root Cause Analysis: connect auto-discover launches new Chrome instead of reconnecting

**Issue**: #94
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude

---

## Root Cause

The `execute_connect()` function in `src/main.rs` has a three-strategy dispatch for bare `connect` (no `--disconnect`, `--status`, `--launch`, or `--ws-url` flags):

1. **Strategy 1** (line 321): Direct `--ws-url` — uses the provided WebSocket URL
2. **Strategy 2** (line 334): Explicit `--launch` — launches a new Chrome
3. **Strategy 3** (line 339): Auto-discover — calls `discover_chrome()` then falls back to `execute_launch()`

The bug is that **Strategy 3 never checks the existing session file**. It jumps directly to `discover_chrome()`, which tries the `DevToolsActivePort` file and then the default port (9222). If the launched Chrome is on a non-default port (which is typical for `--launch` with auto-assigned ports), `discover_chrome()` won't find it, falls through to `execute_launch()`, and spawns a second Chrome process.

Meanwhile, `resolve_connection()` in `src/connection.rs` (used by all non-connect commands like `navigate`, `eval`, etc.) **does** check the session file at priority 3 with a health check. The connect command's auto-discover path was written independently and omits this step.

The issue is compounded by the retrospective learning from #87: the `save_session()` function already has PID-preservation logic (lines 278-303), but it only helps when reconnecting to the **same port**. Since auto-discover finds a different port or launches on a new port, the PID preservation never triggers, and the original session is overwritten.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/main.rs` | 338-357 | Auto-discover path in `execute_connect()` — missing session check before `discover_chrome()` |
| `src/main.rs` | 278-303 | `save_session()` — PID preservation only works when ports match (correct, but not reached in this bug) |
| `src/connection.rs` | 76-84 | `resolve_connection()` — has the correct session-first logic but is not used by `execute_connect()` |

### Triggering Conditions

- A session.json exists with a valid, reachable Chrome instance (typically launched via `connect --launch`)
- The Chrome is running on a non-default port (auto-assigned by `--launch`)
- The user runs bare `connect` (auto-discover) without specifying `--port` or `--ws-url`
- `discover_chrome()` fails to find the existing Chrome because it checks the default port (9222), not the session's port

---

## Fix Strategy

### Approach

Insert a session file check with health verification **before** the `discover_chrome()` call in `execute_connect()`, mirroring the logic in `resolve_connection()` (lines 76-84). When the session exists and the Chrome instance at its port is reachable, reconnect using the session's ws_url and port, preserving the PID. When the session is stale (health check fails), fall through to the existing `discover_chrome()` → auto-launch chain.

This is a minimal, targeted fix: add ~10-15 lines of session-check logic before line 339 in `execute_connect()`. No refactoring of the function's overall structure is needed.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/main.rs` | Add session file read + health check before the `discover_chrome()` call (before line 339). If session exists and is reachable, save session (preserving PID) and return. | Mirrors the proven logic in `resolve_connection()` lines 76-84, ensuring `connect` checks the session before attempting discovery |

### Blast Radius

- **Direct impact**: `execute_connect()` in `src/main.rs` — only the auto-discover code path is modified
- **Indirect impact**: None — `save_session()`, `resolve_connection()`, `discover_chrome()`, and `execute_launch()` are not modified
- **Risk level**: Low — the change adds a check-before-proceed guard; all existing paths remain as fallbacks

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Stale session blocks discovery of a new Chrome | Low | Health check ensures reachability; stale sessions fall through to existing discover logic |
| PID not preserved on reconnection | Low | Existing `save_session()` PID-preservation logic handles this when port matches (AC4 regression test) |
| Auto-launch stops working | Low | Session check is additive; only triggers when a valid session exists; auto-launch remains the final fallback |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Refactor `execute_connect()` to call `resolve_connection()` | Reuse the existing connection resolution chain | Higher blast radius — `resolve_connection()` has different error handling semantics (returns `AppError::no_chrome_found()` vs falling back to auto-launch). Would require restructuring the fallback chain. Better suited for a separate refactoring issue. |
| Check session in `discover_chrome()` | Move session awareness into the discovery layer | Violates layer separation — discovery should find running Chrome, not manage sessions. Session is a CLI-level concern. |

---

## Validation Checklist

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
