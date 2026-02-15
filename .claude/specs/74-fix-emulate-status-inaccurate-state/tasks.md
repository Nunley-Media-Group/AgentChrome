# Tasks: emulate status always reports inaccurate emulation state

**Issue**: #74
**Date**: 2026-02-14
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Add emulation state persistence | [ ] |
| T002 | Wire state into set, status, and reset commands | [ ] |
| T003 | Add regression test | [ ] |

---

### T001: Add Emulation State Persistence

**File(s)**: `src/emulate.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `EmulateState` struct defined with `mobile: bool`, `network: Option<String>`, `cpu: Option<u32>` and derives `Serialize`, `Deserialize`
- [ ] `emulate_state_path()` returns `~/.chrome-cli/emulate-state.json` (following `session_file_path()` pattern from `src/session.rs`)
- [ ] `write_emulate_state()` writes state atomically (temp file + rename) with `0o600` permissions on Unix
- [ ] `read_emulate_state()` returns `Ok(None)` if the file does not exist, `Ok(Some(state))` if it does
- [ ] `delete_emulate_state()` removes the file, returns `Ok(())` if already absent
- [ ] Unit tests: round-trip write/read, read-when-missing returns None, delete-when-missing returns Ok

**Notes**: Follow the exact pattern from `src/session.rs` (`write_session_to`, `read_session_from`, `delete_session_from`). Reuse the `session_file_path()` parent directory (`~/.chrome-cli/`) — the state file lives alongside `session.json`.

### T002: Wire State into Set, Status, and Reset Commands

**File(s)**: `src/emulate.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `execute_set()`: after applying CDP overrides, reads existing state (if any), merges the newly-set fields, and writes the updated state via `write_emulate_state()`
- [ ] `execute_status()`: reads persisted state via `read_emulate_state()` and populates `mobile`, `network`, `cpu` fields from it instead of hardcoded values
- [ ] `execute_reset()`: calls `delete_emulate_state()` after clearing CDP overrides
- [ ] `emulate set --mobile` followed by `emulate status` reports `mobile: true`
- [ ] `emulate set --network slow4g` followed by `emulate status` reports the network profile
- [ ] `emulate set --cpu 4` followed by `emulate status` reports `cpu: 4`
- [ ] `emulate reset` followed by `emulate status` reports defaults (`mobile: false`, no network/cpu)

**Notes**: `execute_set` must merge with existing state so that `emulate set --mobile` doesn't clear a previously set `--network`. Read existing state, overlay the new fields, write back.

### T003: Add Regression Test

**File(s)**: `tests/features/74-fix-emulate-status-inaccurate-state.feature`
**Type**: Create
**Depends**: T001, T002
**Acceptance**:
- [ ] Gherkin feature file covers all acceptance criteria from requirements.md
- [ ] All scenarios tagged `@regression`
- [ ] Feature file is valid Gherkin syntax
- [ ] Scenarios cover: mobile state, network state, CPU state, existing fields still work, defaults after reset

**Notes**: This is the Gherkin feature file only. Step definitions are created separately during implementation.

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T003)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
