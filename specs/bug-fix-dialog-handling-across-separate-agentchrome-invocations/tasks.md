# Tasks: Dialog handling fails across separate agentchrome invocations

**Issue**: #225
**Date**: 2026-04-21
**Status**: Planning
**Author**: Rich Nunley

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Install dialog interceptors on `interact` sessions and add the `--auto-dismiss-dialogs` settle | [ ] |
| T002 | Add `@regression` Gherkin scenarios covering AC1–AC3 | [ ] |
| T003 | Run the Feature Exercise Gate smoke test against a purpose-built fixture | [ ] |
| T004 | Verify no regressions — build, unit, clippy, fmt, bdd | [ ] |

---

### T001: Install dialog interceptors on `interact` sessions and add the `--auto-dismiss-dialogs` settle

**File(s)**: `src/interact.rs`, and if encapsulation requires it `src/connection.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] Every `execute_*` entry point in `src/interact.rs` that can trigger a JavaScript dialog (click, click_at, mouse_down/up, key, type, scroll, drag — every site currently calling `setup_session` for user-visible interaction) uses `setup_session_with_interceptors` instead.
- [ ] The import in `src/interact.rs` is updated accordingly.
- [ ] When `global.auto_dismiss_dialogs` is true on click / click_at, the command awaits a bounded post-dispatch settle (≤ `PAGE_ENABLE_TIMEOUT_MS`) that resolves when either a dialog event is observed-and-handled or the timeout elapses. When the flag is false, behavior is unchanged.
- [ ] No changes to the `dialog` subcommand contract (`dialog info` / `dialog handle` JSON shape, plain-text output, exit codes).
- [ ] Root cause from `design.md` is addressed: Process 1 now writes the `__agentchrome_dialog` cookie before exiting.

**Notes**: Reuse the existing `setup_session_with_interceptors` helper in `src/output.rs:199`. Do not introduce a new interception mechanism. Keep the diff tight to the interact entry points and (if needed) one helper on `ManagedSession` for the settle wait.

### T002: Add regression Gherkin scenarios

**File(s)**: `tests/features/bug-fix-dialog-handling-across-separate-agentchrome-invocations.feature`, `tests/bdd.rs` (step definitions if not already covered by existing dialog steps)
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Feature file exists with `@regression` tag on the feature and every scenario.
- [ ] Three scenarios map 1:1 to AC1 (cross-process prompt accept), AC2 (cross-process alert auto-dismiss), AC3 (no regression in single-process flow).
- [ ] Scenarios use concrete data (e.g. `"Hello agentchrome"`, prompt type, alert type) from the reproduction steps.
- [ ] Step definitions compile and scenarios run under `cargo test --test bdd` (Chrome-dependent scenarios may skip in CI per existing convention in `steering/tech.md`).
- [ ] With T001 reverted, the AC1 scenario fails; with T001 applied, all three scenarios pass.

### T003: Feature Exercise Gate smoke test

**File(s)**: `tests/fixtures/dialog-cross-invocation.html`
**Type**: Create (fixture) + Verify (manual smoke test per `steering/tech.md`)
**Depends**: T001
**Acceptance**:
- [ ] Fixture is self-contained, no external network, and has three triggers: alert (`s2`-analog), confirm, prompt (`s4`-analog).
- [ ] HTML comment at the top enumerates which ACs the fixture covers.
- [ ] Smoke test executed per `steering/tech.md` Feature Exercise Gate procedure:
  1. `cargo build`
  2. `./target/debug/agentchrome connect --launch --headless`
  3. Navigate to `file://<absolute-path>/tests/fixtures/dialog-cross-invocation.html`
  4. Run AC1's two-process sequence; verify `#result` reflects `"Hello agentchrome"`.
  5. Run AC2's single-process `--auto-dismiss-dialogs` sequence; verify `#result` reflects the alert acknowledgement.
  6. Run AC3's single-process same-process flow; verify JSON shape and exit codes are unchanged from a pre-fix baseline (record baseline from main before T001).
  7. Disconnect; kill any orphaned Chrome processes.
- [ ] Each AC's pass/fail is recorded for `/verify-code`.

### T004: Verify no regressions

**File(s)**: none
**Type**: Verify
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] `cargo build` exits 0.
- [ ] `cargo test --lib` exits 0.
- [ ] `cargo clippy --all-targets` exits 0.
- [ ] `cargo fmt --check` exits 0.
- [ ] `cargo test --test bdd` exits 0 (or documents skips as pre-existing).
- [ ] No side effects in adjacent `interact` / `dialog` / `js` paths per the blast-radius list in `design.md`.

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #225 | 2026-04-21 | Initial defect tasks |
