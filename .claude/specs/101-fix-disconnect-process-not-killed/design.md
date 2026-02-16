# Root Cause Analysis: Disconnect reports killed_pid but process remains alive

**Issue**: #101
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude

---

## Root Cause

The `kill_process()` function in `src/main.rs:500-513` sends a termination signal but has two fundamental problems:

1. **Fire-and-forget signal delivery**: On Unix, `kill_process()` shells out to the `kill` command which sends SIGTERM, but the result is discarded with `let _ = ...`. The function returns immediately without checking whether the process actually terminated. Chrome may take time to shut down (flushing state, closing child processes) or may even ignore SIGTERM under certain conditions.

2. **No process group kill**: Chrome spawns multiple child processes (GPU process, renderer, utility, etc.). The current code only sends a signal to the main Chrome PID. Even if the main process exits, the child processes become orphans and continue running. On macOS, the proper approach is to kill the entire process group using `kill -- -<pgid>` or to use `sysctl`/`pkill -P` to find and kill children.

The `execute_disconnect()` function at line 486 unconditionally sets `killed_pid = Some(pid)` after calling `kill_process()`, regardless of whether the kill actually succeeded. This means the JSON output claims the process was killed even when it wasn't.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/main.rs` | 500-513 | `kill_process()` — sends signal but doesn't wait or verify |
| `src/main.rs` | 479-498 | `execute_disconnect()` — reports `killed_pid` without confirming termination |

### Triggering Conditions

- Chrome is launched via `connect --launch` (PID is stored in session)
- `connect --disconnect` is called
- SIGTERM is sent but Chrome doesn't exit immediately (common with multi-process Chrome)
- The function returns before the process terminates
- The user observes the process still running

---

## Fix Strategy

### Approach

Replace the fire-and-forget `kill` command invocation with a robust process termination sequence:

1. **Send SIGTERM** to the process group (negative PID) to terminate Chrome and all its children
2. **Poll for termination** with a short timeout (~2 seconds), checking if the process has exited
3. **Escalate to SIGKILL** if SIGTERM didn't work within the timeout, again targeting the process group
4. **Use native signals** via `libc::kill()` instead of shelling out to the `kill` command for reliability and to support process group signals

On Unix, sending a signal to `-pid` (negative PID) targets the entire process group, which handles Chrome's child processes. Chrome typically sets itself as a process group leader when launched, so this will catch renderer, GPU, and utility processes.

On Windows, `taskkill /T /F /PID` already handles the process tree.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/main.rs` | Rewrite `kill_process()` to: (1) send SIGTERM to process group via `libc::kill(-pid, SIGTERM)`, (2) poll with timeout, (3) escalate to SIGKILL | Ensures process is actually dead before returning |
| `src/main.rs` | Update Windows `kill_process()` to use `taskkill /T /F` flags | `/T` kills the process tree, `/F` forces termination |

### Blast Radius

- **Direct impact**: `kill_process()` and `execute_disconnect()` in `src/main.rs`
- **Indirect impact**: None — `kill_process()` is only called from `execute_disconnect()`, which is only triggered by `connect --disconnect`
- **Risk level**: Low — the change is isolated to the disconnect code path. No other commands or features call `kill_process()`.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Killing a process group that chrome-cli didn't create | Low | Only kill the process group if the PID matches what was stored in the session file from `--launch` |
| Timeout too short for Chrome to shut down gracefully | Low | Use 2-second SIGTERM timeout before SIGKILL — sufficient for Chrome to flush state |
| SIGKILL leaves Chrome profile in corrupt state | Low | Chrome is designed to recover from hard kills; profile corruption is Chrome's responsibility, not chrome-cli's |
| Disconnect takes longer (up to ~2s) in the happy path | Low | Only waits if SIGTERM doesn't immediately terminate; most Chrome instances exit quickly on SIGTERM |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Keep shelling out to `kill` but add `waitpid` | Run `kill <pid>` then poll with `ps` | Less reliable than native signals; can't target process groups; extra process spawning overhead |
| Use `nix` crate for signal handling | Provides safe Rust wrappers for Unix signals | Adding a dependency for 2-3 `libc` calls is unnecessary; `libc` is already available |
| Kill only the main PID, not the process group | Simpler change, just add wait-and-verify | Doesn't address AC2 (child process cleanup); Chrome children become orphans |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
