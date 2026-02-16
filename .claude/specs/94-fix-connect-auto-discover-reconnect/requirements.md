# Defect Report: connect auto-discover launches new Chrome instead of reconnecting to existing session

**Issue**: #94
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/6-session-and-connection-management/`

---

## Reproduction

### Steps to Reproduce

1. Clean any existing session: `chrome-cli connect --disconnect`
2. Launch headless Chrome: `chrome-cli connect --launch --headless` — note the `port` and `pid` in output
3. Verify session: `cat ~/.chrome-cli/session.json` — shows the launched PID
4. Run auto-discover: `chrome-cli connect` (bare, no flags)
5. Observe: output shows a **different** `port` and `pid` — a new Chrome instance was launched
6. Verify: `ps aux | grep Chrome.*remote-debugging` shows **two** Chrome processes
7. The original headless Chrome is now orphaned (not tracked in session.json)

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS (Darwin 25.3.0) |
| **Version / Commit** | `c584d2d` (main) |
| **Browser / Runtime** | Chrome 144.0.7559.133 |
| **Configuration** | Default (no env vars set) |

### Frequency

Always

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `connect` (auto-discover) checks the existing session.json first; if the session points to a reachable Chrome instance, reconnects to it without launching a new process; the session PID is preserved |
| **Actual** | `connect` (auto-discover) skips the session file entirely, runs `discover_chrome()` which may find a different Chrome or fall back to auto-launch, creating a second Chrome process; the original headless Chrome is orphaned |

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Auto-discover reconnects to existing session

**Given** Chrome was launched with `connect --launch --headless` and session.json exists with a PID and port
**When** I run `connect` (auto-discover) without any flags
**Then** the CLI reconnects to the existing Chrome instance using the session file's ws_url
**And** no new Chrome process is spawned
**And** the session file's PID is preserved

### AC2: Auto-discover falls back to discovery when session is stale

**Given** a session.json exists but the Chrome process at the recorded port is no longer running
**When** I run `connect` (auto-discover)
**Then** the CLI attempts to discover a running Chrome instance via `DevToolsActivePort` or default port
**And** if none is found, reports a clear error (does not silently launch a new one)

### AC3: No orphaned Chrome processes

**Given** Chrome was launched with `connect --launch --headless`
**When** I run `connect` (auto-discover) followed by `connect --disconnect`
**Then** exactly zero Chrome processes related to chrome-cli remain running

### AC4: Session PID preserved after reconnection

**Given** Chrome was launched with `connect --launch` storing a specific PID on a given port
**When** I run `connect` auto-discover and it reconnects to the same port
**Then** the session file retains the original PID

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `execute_connect()` auto-discover path must check session.json and verify reachability (health check) before calling `discover_chrome()` | Must |
| FR2 | When the session is reachable, `connect` must reconnect using the session's ws_url and port without calling `discover_chrome()` or `execute_launch()` | Must |
| FR3 | When the session is stale (health check fails), `connect` must fall through to `discover_chrome()` and then auto-launch as it does today | Must |
| FR4 | Session PID must be preserved across reconnections — regression guard for #87 | Must |

---

## Out of Scope

- Changing `connect --launch` behavior
- Multi-session support
- Automatic cleanup of orphaned Chrome processes from previous sessions
- Refactoring `execute_connect()` to use `resolve_connection()` (the fix should be minimal)

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3, AC4)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
