# Tasks: Fix dialog handle clap error for --accept / --dismiss

**Issue**: #250
**Date**: 2026-04-23
**Status**: Planning
**Author**: Rich Nunley

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Extend `syntax_hint` to handle `--accept` / `--dismiss` on `dialog handle` | [ ] |
| T002 | Add regression feature file and BDD scenarios | [ ] |
| T003 | Verify no regressions across CLI parsing tests | [ ] |

---

### T001: Fix the Defect

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `syntax_hint` recognizes `--accept` and `--dismiss` when the resolved subcommand path is `dialog handle`.
- [ ] For those flags, the returned hint is `Did you mean: agentchrome dialog handle accept` (or `dismiss`), derived from the flag name.
- [ ] Existing `--uid` / `--selector` branches are unchanged.
- [ ] New unit tests in `src/main.rs` cover:
  - [ ] `dialog handle --accept` → hint contains `agentchrome dialog handle accept`.
  - [ ] `dialog handle --dismiss` → hint contains `agentchrome dialog handle dismiss`.
  - [ ] The hint does **not** fire on a different subcommand that raises `UnknownArgument` for `--accept` (negative/guard test).
- [ ] `cargo fmt` and `cargo clippy --all-targets -- -D warnings` pass.
- [ ] No changes to `DialogHandleArgs` or `DialogAction` in `src/cli/mod.rs`.

**Notes**: Follow the fix strategy in design.md. The flag-to-value mapping is `bare.trim_start_matches('-')`. Keep changes minimal — do not refactor the existing `syntax_hint` / `resolve_subcommand_path` helpers.

### T002: Add Regression Test

**File(s)**: `tests/features/bug-fix-dialog-handle-clap-error.feature`, `tests/bdd.rs` (step definitions if missing)
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Gherkin feature file exists at `tests/features/bug-fix-dialog-handle-clap-error.feature`.
- [ ] Every scenario is tagged `@regression`.
- [ ] Scenarios cover AC1 (`--accept` hint), AC2 (`--dismiss` hint), and AC3 (valid positional usage parses successfully).
- [ ] Step definitions are wired in `tests/bdd.rs` (reuse existing CLI-invocation steps where possible).
- [ ] `cargo test --test bdd` passes with the fix applied.
- [ ] Confirm the new scenarios fail if T001's `syntax_hint` change is reverted (proves the tests catch the bug).

### T003: Verify No Regressions

**File(s)**: existing test suites — no file changes
**Type**: Verify
**Depends**: T001, T002
**Acceptance**:
- [ ] `cargo test` (full suite, including `syntax_hint_click_uid_produces_did_you_mean`, `syntax_hint_suppressed_for_unrelated_clap_errors`, `syntax_hint_ignores_non_unknown_argument_errors`) passes.
- [ ] Manual spot-check: `agentchrome dialog handle --help` still renders the positional `<ACTION>` synopsis and EXAMPLES block unchanged.
- [ ] Manual spot-check: `agentchrome dialog handle accept` against a live dialog still behaves exactly as before (per blast radius in design.md).

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
| #250 | 2026-04-23 | Initial defect tasks |
