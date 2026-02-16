# Defect Report: Disconnect reports killed_pid but process remains alive

**Issue**: #101
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/6-session-and-connection-management/`

---

## Reproduction

### Steps to Reproduce

1. Run `chrome-cli connect --launch --headless` — note the PID (e.g., 25675)
2. Run `chrome-cli connect --disconnect` — output shows `{"disconnected":true,"killed_pid":25675}`
3. Run `ps -p 25675` — process is still running
4. Run `kill 25675` manually — process terminates normally

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS (Darwin 25.3.0) |
| **Version / Commit** | `c584d2d` (main) |
| **Browser / Runtime** | Chrome/Chromium (headless) |
| **Configuration** | Default |

### Frequency

Always

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | After `connect --disconnect`, the Chrome process at the reported PID is terminated. `ps -p <pid>` shows no process. |
| **Actual** | The response claims `killed_pid: 25675` but the process is still alive. Manual `kill` succeeds, proving the process is killable. |

### Error Output

```
$ chrome-cli connect --disconnect
{"disconnected":true,"killed_pid":25675}

$ ps -p 25675
  PID TTY           TIME CMD
25675 ??         0:00.50 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless ...
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Disconnect actually kills the Chrome process

**Given** Chrome was launched with `connect --launch --headless` with PID X
**When** I run `connect --disconnect`
**Then** the output contains `killed_pid` with value X
**And** the process at PID X is no longer running

**Example**:
- Given: `chrome-cli connect --launch --headless` → PID 25675
- When: `chrome-cli connect --disconnect`
- Then: output is `{"disconnected":true,"killed_pid":25675}` and `ps -p 25675` returns no process

### AC2: Child processes are also cleaned up

**Given** Chrome was launched with PID X and has spawned child processes (renderer, GPU, etc.)
**When** I run `connect --disconnect`
**Then** all Chrome child processes of PID X are also terminated

**Example**:
- Given: Chrome PID 25675 has children [25676, 25677, 25678]
- When: `chrome-cli connect --disconnect`
- Then: none of PIDs 25675-25678 are running

### AC3: Disconnect with already-exited process reports cleanly

**Given** a session file exists but the Chrome process has already exited
**When** I run `connect --disconnect`
**Then** the session file is removed
**And** the output indicates disconnection succeeded
**And** the exit code is 0

**Example**:
- Given: session file references PID 99999 which no longer exists
- When: `chrome-cli connect --disconnect`
- Then: output is `{"disconnected":true,"killed_pid":99999}` and exit code is 0

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `kill_process` must verify the process is actually terminated after sending a signal | Must |
| FR2 | Should send SIGTERM first, then escalate to SIGKILL after a timeout if the process is still alive | Should |
| FR3 | Must kill the entire process group (or child processes) to clean up Chrome helper processes | Must |
| FR4 | Must not report `killed_pid` unless the kill signal was sent (existing behavior is acceptable — reporting the PID even if the process was already dead is fine) | Should |

---

## Out of Scope

- Cleaning up Chrome profile directories on disk
- Killing Chrome processes not managed by chrome-cli (not in the session file)
- Changing the `DisconnectInfo` JSON output schema beyond what is needed
- Refactoring the session file format

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
