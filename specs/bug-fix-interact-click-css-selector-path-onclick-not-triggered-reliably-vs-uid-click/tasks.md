# Tasks: interact click CSS selector path fails to trigger onclick

**Issue**: #252
**Date**: 2026-04-23
**Status**: Planning
**Author**: Rich Nunley

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Diagnose + fix the CSS-selector click dispatch path | [ ] |
| T002 | Add `@regression` Gherkin scenarios and step definitions | [ ] |
| T003 | Verify no regressions across adjacent `interact` behavior | [ ] |

---

### T001: Diagnose and Fix the Defect

**File(s)**: `src/interact.rs` (CSS branch of `resolve_target_to_backend_node_id` at lines 271–305, and/or `resolve_target_coords` at lines 366–373)
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] CDP frames captured for the three click paths (UID, CSS, `click-at`) on `the-internet.herokuapp.com/add_remove_elements/`; divergence recorded in the PR description.
- [ ] `interact click "css:button[onclick='addElement()']"` on the reference page causes a `.added-manually` element to be appended (AC1).
- [ ] Root cause from `design.md` is addressed — not a symptom-only workaround.
- [ ] Only the CSS branch / resolver ordering is modified; UID branch and `click-at` path are untouched.
- [ ] No unrelated changes included in the diff.
- [ ] `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` pass.

**Notes**: Follow the fix strategy from `design.md`. The edit must leave `dispatch_click` and the UID branch byte-identical.

### T002: Add Regression Test

**File(s)**: `tests/features/bug-fix-interact-click-css-selector-path-onclick-not-triggered-reliably-vs-uid-click.feature`; step definitions in `tests/bdd.rs` (or the corresponding steps module referenced by `steering/tech.md`)
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Gherkin `Feature` is tagged `@regression`; every `Scenario` is tagged `@regression`.
- [ ] Scenario for AC1 (CSS selector click triggers onclick) fails against `main` before the T001 fix and passes after.
- [ ] Scenario for AC2 (UID click unchanged) passes both before and after the T001 fix.
- [ ] Scenario for AC3 (CSS-selector navigation click reports `navigated: true`) passes both before and after.
- [ ] Step definitions reuse existing BDD helpers where possible; no new helper modules.
- [ ] `cargo test --test bdd` is green.

### T003: Verify No Regressions

**File(s)**: Existing test suite only — no edits.
**Type**: Verify
**Depends**: T001, T002
**Acceptance**:
- [ ] `cargo test --workspace` passes.
- [ ] Existing `feature-mouse-interactions` BDD scenarios still pass.
- [ ] Manual smoke: `interact click` via UID, CSS, and `click-at` all succeed against `the-internet.herokuapp.com/add_remove_elements/`.
- [ ] Blast-radius sites from `design.md` reviewed: no other `interact` subcommand that shares `resolve_target_coords` has changed behaviour.

---

## Validation Checklist

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #252 | 2026-04-23 | Initial defect tasks |
