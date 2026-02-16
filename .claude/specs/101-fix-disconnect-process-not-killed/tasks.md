# Tasks: Disconnect reports killed_pid but process remains alive

**Issue**: #101
**Date**: 2026-02-15
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Fix the defect | [ ] |
| T002 | Add regression test | [ ] |
| T003 | Verify no regressions | [ ] |

---

### T001: Fix the Defect

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `kill_process()` sends SIGTERM to the process group (`-pid`) via `libc::kill()` on Unix
- [ ] `kill_process()` polls for process termination with a ~2-second timeout after SIGTERM
- [ ] `kill_process()` escalates to SIGKILL (process group) if SIGTERM doesn't terminate the process within the timeout
- [ ] On Windows, `kill_process()` uses `taskkill /T /F /PID` to kill the process tree
- [ ] `execute_disconnect()` correctly reports `killed_pid` in the output
- [ ] If the process is already dead when disconnect runs, the function handles it gracefully (no panic, no error)
- [ ] No unrelated changes included in the diff

**Notes**: Follow the fix strategy from design.md. Use `libc::kill()` for Unix signals and `libc::waitpid()` or `/proc`/`kill(pid, 0)` polling for termination checks. Keep `execute_disconnect()` synchronous. The `libc` crate is implicitly available on Unix targets in Rust — add it to `Cargo.toml` if not already a dependency.

### T002: Add Regression Test

**File(s)**: `.claude/specs/101-fix-disconnect-process-not-killed/feature.gherkin`, `tests/features/101-fix-disconnect-process-not-killed.feature`
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Gherkin scenario reproduces the original bug condition (launch Chrome, disconnect, verify process is dead)
- [ ] Scenario for child process cleanup is included
- [ ] Scenario for already-exited process is included
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions implemented (or mapped to existing steps)
- [ ] Test passes with the fix applied

### T003: Verify No Regressions

**File(s)**: Existing test files
**Type**: Verify (no file changes)
**Depends**: T001, T002
**Acceptance**:
- [ ] All existing tests pass (`cargo test`)
- [ ] Existing disconnect scenarios in `tests/features/session-connection-management.feature` still pass
- [ ] No side effects in the connect/disconnect code path
- [ ] `cargo clippy` passes with no new warnings

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
