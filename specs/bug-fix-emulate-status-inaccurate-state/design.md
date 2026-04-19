# Root Cause Analysis: emulate status always reports inaccurate emulation state

**Issue**: #74
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude

---

## Root Cause

The `execute_status` function in `src/emulate.rs:545-613` constructs an `EmulateStatusOutput` struct with `mobile: false`, `network: None`, and `cpu: None` hardcoded at lines 597-605. These three fields are never queried or populated from any source.

The function queries only JavaScript-detectable settings via `Runtime.evaluate` (viewport dimensions from `window.innerWidth`/`window.innerHeight`, user agent from `navigator.userAgent`, color scheme from `window.matchMedia`, and device pixel ratio from `window.devicePixelRatio`). However, mobile emulation mode, network throttling, and CPU throttling are CDP-level overrides that are invisible to in-page JavaScript. There is no CDP query API to retrieve the current state of these overrides — they are "fire-and-forget" commands.

The `emulate set` command (`execute_set` at line 263) correctly applies these overrides via CDP and returns accurate status in its own output, but this state is ephemeral — it exists only within the `execute_set` function's local `status` variable and is never persisted. Since `emulate set` and `emulate status` are separate CLI invocations (separate processes), the status command has no way to know what was previously set.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/emulate.rs` | 597-606 (`execute_status`) | Constructs `EmulateStatusOutput` with hardcoded `mobile: false`, `network: None`, `cpu: None` |
| `src/emulate.rs` | 263-458 (`execute_set`) | Applies mobile/network/cpu via CDP but does not persist the state |
| `src/emulate.rs` | 464-539 (`execute_reset`) | Resets all overrides via CDP but does not clear any persisted state |

### Triggering Conditions

- User runs `emulate set` with `--mobile`, `--network`, or `--cpu` flags in one CLI invocation
- User then runs `emulate status` in a separate CLI invocation
- The status command has no access to the previous invocation's state
- JavaScript introspection cannot detect these CDP-level overrides

---

## Fix Strategy

### Approach

Introduce a lightweight emulation state file (`~/.agentchrome/emulate-state.json`) that persists the CDP-only overrides across CLI invocations. This mirrors the existing `session.json` pattern in `src/session.rs`. When `emulate set` applies mobile, network, or CPU overrides, it writes the state to this file. When `emulate status` runs, it reads the persisted state to supplement the JavaScript-detected values. When `emulate reset` runs, it deletes the state file.

This is the session-level state tracking approach suggested in the issue. It is minimal, follows existing project patterns, and avoids relying on non-existent CDP query APIs.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/emulate.rs` — new struct `EmulateState` | Add a `Serialize`/`Deserialize` struct with `mobile: bool`, `network: Option<String>`, `cpu: Option<u32>` | Defines the shape of persisted emulation state |
| `src/emulate.rs` — new functions `emulate_state_path()`, `write_emulate_state()`, `read_emulate_state()`, `delete_emulate_state()` | Add state file I/O helpers following the pattern from `src/session.rs` | Read/write/delete `~/.agentchrome/emulate-state.json` |
| `src/emulate.rs` — `execute_set()` (line 263) | After applying CDP overrides, persist the state by calling `write_emulate_state()` | Saves mobile/network/cpu state for later retrieval |
| `src/emulate.rs` — `execute_status()` (line 545) | Read persisted state via `read_emulate_state()` and populate `mobile`, `network`, `cpu` fields from it | Status now reflects actual emulation state |
| `src/emulate.rs` — `execute_reset()` (line 464) | Call `delete_emulate_state()` after clearing CDP overrides | Clears persisted state so status returns to defaults |
| `src/emulate.rs` — unit tests | Add tests for state file round-trip, read-when-missing, and reset-clears-state | Prove the state persistence works |

### Blast Radius

- **Direct impact**: `src/emulate.rs` — `execute_set()`, `execute_status()`, `execute_reset()`, plus new state I/O functions. All changes are within the emulate module.
- **Indirect impact**: None. The emulate module is self-contained. No other commands read or depend on emulation state. The new state file is independent of `session.json`.
- **Risk level**: Low — changes are additive (new file I/O) and the existing JavaScript-based detection in `execute_status()` remains unchanged. The persisted state supplements, not replaces, the existing logic.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Stale state file after Chrome restarts (emulation state cleared by Chrome but file remains) | Medium | Session lifecycle: `emulate status` could validate that the session is still the same one that set the state (compare session timestamps or ws_url). For simplicity, accept this as a known limitation — `emulate reset` always clears the file. |
| State file write fails (permissions, disk full) | Low | Use `Result` propagation; a write failure doesn't prevent the CDP override from being applied — the set command still works, only status reporting degrades. |
| Concurrent CLI invocations race on state file | Very Low | CLI is single-user; atomic write (temp file + rename) as used in `session.rs` prevents corruption. |
| `page resize` sets viewport without updating state file | Low | `page resize` hardcodes `mobile: false` and doesn't interact with emulation state — this is existing behavior and out of scope for this fix. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| CDP-based querying | Query Chrome for active emulation overrides via CDP methods | CDP does not expose query APIs for `setDeviceMetricsOverride`, `emulateNetworkConditions`, or `setCPUThrottlingRate`. There is no way to retrieve what has been set. |
| In-memory state via long-running daemon | Run a persistent daemon that tracks state across invocations | Violates the project's CLI-first, single-binary principle. Massive over-engineering for three fields. |
| Embed state in session.json | Add emulation fields to the existing `SessionData` struct | Would require changing the session module's public API and coupling session lifecycle to emulation lifecycle. The emulation state has different semantics (cleared by `emulate reset`, not by `disconnect`). |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
