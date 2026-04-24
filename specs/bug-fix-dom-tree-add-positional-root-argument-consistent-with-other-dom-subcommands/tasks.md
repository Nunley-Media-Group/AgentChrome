# Tasks: Fix `dom tree` positional ROOT argument

**Issue**: #251
**Date**: 2026-04-23
**Status**: Planning
**Author**: Rich Nunley

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Add positional `ROOT` to `DomTreeArgs` and wire it through `execute_tree`; update clap help, examples_data, and man page. | [ ] |
| T002 | Add `@regression` BDD scenarios covering AC1–AC5. | [ ] |
| T003 | Verify no regressions via build, clippy, unit tests, BDD, and headless smoke test. | [ ] |

---

### T001: Fix the Defect

**File(s)**:
- `src/cli/mod.rs` (`DomTreeArgs` struct; `Tree` variant's `after_long_help`)
- `src/dom.rs` (`execute_tree` root resolution)
- `src/examples_data.rs` (DOM examples list)
- `man/agentchrome-dom-tree.1` (regenerated)

**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `DomTreeArgs` gains `pub root_positional: Option<String>` with `#[arg(value_name = "ROOT", conflicts_with = "root")]`.
- [ ] `execute_tree` resolves the effective target as `args.root_positional.as_ref().or(args.root.as_ref())` and uses it in place of `args.root`.
- [ ] `Tree` variant's `after_long_help` EXAMPLES block includes a positional-form example (e.g., `agentchrome dom tree css:div.content`).
- [ ] `src/examples_data.rs` includes one new entry demonstrating the positional form.
- [ ] `man/agentchrome-dom-tree.1` is regenerated so the SYNOPSIS shows `[ROOT]` and the EXAMPLES section includes the positional form.
- [ ] `cargo fmt --check`, `cargo clippy --all-targets`, and `cargo build` all succeed.

**Notes**: Keep the change to `DomTreeArgs` additive — do not rename or re-type the existing `root` field. The `conflicts_with = "root"` attribute yields the AC4 conflict error with zero runtime validation code.

### T002: Add Regression Test

**File(s)**:
- `tests/features/dom-tree-positional-root.feature` (new)
- `tests/bdd.rs` (extend with step definitions as needed)
- `tests/fixtures/dom-tree-positional-root.html` (new minimal fixture)

**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] New feature file is tagged `@regression` at the feature level and on every scenario.
- [ ] Scenarios cover AC1 (positional), AC2 (`--root` still works), AC3 (no-arg), AC4 (conflict), and AC5 (help text includes `[ROOT]` and a positional example).
- [ ] Step definitions wired into `tests/bdd.rs` following the cucumber-rs pattern documented in `steering/tech.md`.
- [ ] Fixture HTML contains at least one `<table>` with recognizable children so AC1's output can be asserted.
- [ ] `cargo test --test bdd` passes with the fix applied.
- [ ] Temporarily reverting T001's struct change causes the AC1 scenario to fail (confirms the test catches the bug).

### T003: Verify No Regressions

**File(s)**: [no file changes — verification only]
**Type**: Verify
**Depends**: T001, T002
**Acceptance**:
- [ ] `cargo build` exits 0.
- [ ] `cargo test --lib` exits 0.
- [ ] `cargo clippy --all-targets` exits 0.
- [ ] `cargo fmt --check` exits 0.
- [ ] Feature Exercise Gate (per `steering/tech.md`): launch headless Chrome, navigate to the new fixture, and exercise AC1–AC5 against the real binary. Record pass/fail per AC.
- [ ] Kill any orphaned Chrome processes after the smoke test.
- [ ] `agentchrome capabilities` output reflects the new positional on `dom tree`.

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
| #251 | 2026-04-23 | Initial defect tasks |
