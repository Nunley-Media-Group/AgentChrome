# Tasks: connect auto-discover launches new Chrome instead of reconnecting

**Issue**: #94
**Date**: 2026-02-15
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Fix the defect — add session check before discover | [ ] |
| T002 | Add regression test | [ ] |
| T003 | Verify no regressions | [ ] |

---

### T001: Fix the Defect

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `execute_connect()` checks session.json before calling `discover_chrome()` on the auto-discover path
- [ ] When session exists and Chrome is reachable at `session.port`, reconnects using session data (ws_url, port, pid)
- [ ] When session exists but Chrome is not reachable (health check fails), falls through to existing `discover_chrome()` → auto-launch chain
- [ ] When no session exists, behavior is unchanged (discovery → auto-launch)
- [ ] `save_session()` is called with the session's PID to preserve it
- [ ] No new Chrome process is spawned when reconnecting to an existing session

**Notes**: Insert the session check between line 337 (after `--launch` check) and line 339 (before `discover_chrome()` call). Pattern to follow is `resolve_connection()` lines 76-84 in `src/connection.rs`: read session → health check on session port → return resolved connection. Use `health_check()` from `src/connection.rs` or equivalent (`query_version()` from `src/chrome/discovery.rs`). Construct a `ConnectionInfo` with the session's PID and call `save_session()` + `print_json()`.

### T002: Add Regression Test

**File(s)**: `tests/features/94-fix-connect-auto-discover-reconnect.feature`
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Gherkin scenarios cover all 4 acceptance criteria from requirements.md
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions implemented or reuse existing steps from session management tests
- [ ] Tests pass with the fix applied

### T003: Verify No Regressions

**File(s)**: Existing test files
**Type**: Verify (no file changes)
**Depends**: T001, T002
**Acceptance**:
- [ ] All existing tests pass (`cargo test`)
- [ ] `tests/features/session-connection-management.feature` scenarios unaffected
- [ ] `tests/features/87-fix-connect-auto-discover-overwrites-session-pid.feature` scenarios unaffected
- [ ] No side effects in `resolve_connection()` or `save_session()`

---

## Validation Checklist

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
