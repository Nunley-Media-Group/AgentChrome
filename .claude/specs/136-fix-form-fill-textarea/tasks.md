# Tasks: Form fill not setting value on textarea elements

**Issue**: #136
**Date**: 2026-02-17
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Fix the defect in FILL_JS and CLEAR_JS | [ ] |
| T002 | Add regression test | [ ] |
| T003 | Run manual smoke test | [ ] |
| T004 | Verify no regressions | [ ] |

---

### T001: Fix the Defect

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `FILL_JS` uses `tagName`-based conditional to select `HTMLTextAreaElement.prototype` for textarea elements and `HTMLInputElement.prototype` for input elements
- [ ] `CLEAR_JS` has the same `tagName`-based conditional fix applied
- [ ] No unrelated changes included in the diff
- [ ] `cargo build` succeeds
- [ ] `cargo clippy` passes
- [ ] `cargo fmt --check` passes

**Notes**: Replace the `||` short-circuit in both JS constants with a conditional like:
```javascript
const proto = tag === 'textarea'
    ? window.HTMLTextAreaElement.prototype
    : window.HTMLInputElement.prototype;
const nativeSetter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
```
The `tag` variable already exists in both functions from the earlier `tag === 'select'` check.

### T002: Add Regression Test

**File(s)**: `tests/features/136-fix-form-fill-textarea.feature`, `tests/bdd.rs`
**Type**: Create / Modify
**Depends**: T001
**Acceptance**:
- [ ] Gherkin feature file covers AC1 (textarea fill), AC2 (input fill regression), and AC3 (textarea clear)
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions implemented in `tests/bdd.rs`
- [ ] `cargo test --test bdd` passes

### T003: Run Manual Smoke Test

**File(s)**: None (verification only)
**Type**: Verify
**Depends**: T001
**Acceptance**:
- [ ] Build debug binary: `cargo build`
- [ ] Launch headless Chrome: `./target/debug/chrome-cli connect --launch --headless`
- [ ] Navigate to Google: `./target/debug/chrome-cli navigate https://www.google.com`
- [ ] Take snapshot: `./target/debug/chrome-cli page snapshot`
- [ ] Fill textarea: `./target/debug/chrome-cli form fill <textarea-uid> "test query"`
- [ ] Verify value: `./target/debug/chrome-cli js exec --uid <textarea-uid> "(el) => el.value"` returns `"test query"`
- [ ] Run SauceDemo smoke test: navigate to https://www.saucedemo.com/, take snapshot, fill username input, verify value is set
- [ ] Disconnect and kill Chrome processes

### T004: Verify No Regressions

**File(s)**: Existing test files
**Type**: Verify (no file changes)
**Depends**: T001, T002
**Acceptance**:
- [ ] All existing tests pass: `cargo test`
- [ ] No side effects in related code paths (form fill on input, select, checkbox, radio are unaffected)

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T002)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
