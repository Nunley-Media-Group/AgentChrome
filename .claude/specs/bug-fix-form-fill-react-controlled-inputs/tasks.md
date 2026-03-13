# Tasks: Form fill silently failing on React-controlled inputs

**Issues**: #161
**Date**: 2026-03-12
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Add element type detection helpers | [x] |
| T002 | Add keyboard-based fill and React-compatible clear functions | [x] |
| T003 | Modify fill_element and clear_element to branch by element type | [x] |
| T004 | Add regression test (Gherkin + step definitions) | [x] |
| T005 | Manual smoke test against SauceDemo | [x] |
| T006 | Verify no regressions | [x] |

---

### T001: Add element type detection helpers

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `describe_element()` async function added — takes `&mut ManagedSession` and `backendNodeId: i64`, calls `DOM.describeNode`, returns `(String, Option<String>)` for `(node_name, input_type)`
- [ ] `node_name` is lowercased (e.g., `"input"`, `"textarea"`, `"select"`)
- [ ] `input_type` is extracted from the `attributes` array by finding the `"type"` key and returning the next element as the value; returns `None` if no type attribute
- [ ] `is_text_input()` function added — takes `(node_name: &str, input_type: Option<&str>)`, returns `true` for:
  - `node_name == "textarea"`
  - `node_name == "input"` with `input_type` in `[None, "text", "password", "email", "number", "tel", "url", "search"]` (None means no type attribute, which defaults to text)
- [ ] Returns `false` for `node_name == "select"`, `input_type == "checkbox"`, `input_type == "radio"`, `input_type == "file"`, and any other non-text input type

**Notes**: `DOM.describeNode` returns `{ node: { nodeName: "INPUT", attributes: ["type", "text", "class", "form-control", ...] } }`. The attributes array is flat: `[name1, value1, name2, value2, ...]`. Parse by iterating in pairs. `describe_element` does NOT call `DOM.resolveNode`.

### T002: Add keyboard-based fill and React-compatible clear functions

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [x] `fill_element_keyboard()` async function added — takes `&mut ManagedSession`, `backend_node_id: i64`, `value: &str`
- [x] Focuses the element via `DOM.focus({ backendNodeId: backend_node_id })`
- [x] Selects all existing text via `Runtime.evaluate("document.activeElement.select()")` — cross-platform (NOTE: `Ctrl+A` modifiers=2 does NOT select all in macOS Chrome text inputs; `Meta+A` also fails; `document.activeElement.select()` is the reliable cross-platform approach)
- [x] Types each character of `value` via `Input.dispatchKeyEvent({ type: "char", text: ch })` — replaces the selection on the first character
- [x] `CLEAR_ACTIVE_ELEMENT_JS` module-level constant added — JS expression that sets `document.activeElement.value` to `""` via native setter and dispatches `new InputEvent('input', { inputType: 'deleteContentBackward' })` that React recognizes
- [x] `clear_element_keyboard()` async function added — takes `&mut ManagedSession`, `backend_node_id: i64`
- [x] Focuses the element via `DOM.focus({ backendNodeId: backend_node_id })`
- [x] Clears value via `Runtime.evaluate(CLEAR_ACTIVE_ELEMENT_JS)` (NOTE: `Backspace` keyDown/keyUp after programmatic `select()` does not reliably trigger React `onChange` — the InputEvent approach is required)
- [x] Both functions map CDP errors to `AppError::interaction_failed` with descriptive action names

**Notes**: `Ctrl+A` (modifiers=2) was the originally spec'd approach for select-all, but smoke testing revealed it does not select all text in macOS Chrome text inputs. `document.activeElement.select()` is the correct cross-platform approach. Similarly, `Backspace` keyDown/keyUp after programmatic selection doesn't fire the `input` event that React needs; `InputEvent` with `inputType: 'deleteContentBackward'` is required.

### T003: Modify fill_element and clear_element to branch by element type

**File(s)**: `src/form.rs`
**Type**: Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] `fill_element()` modified:
  1. Resolves target to `backend_node_id` via `resolve_target_to_backend_node_id()` (existing)
  2. Calls `describe_element()` to get `(node_name, input_type)`
  3. If `is_text_input(node_name, input_type)`: calls `fill_element_keyboard(session, backend_node_id, value)` — no `DOM.resolveNode` involved
  4. Else: calls `resolve_to_object_id()` + `Runtime.callFunctionOn` with `FILL_JS` (existing path, unchanged)
- [ ] `clear_element()` modified with the same branching:
  1. Resolves target to `backend_node_id`
  2. Calls `describe_element()` to get element type
  3. If text-type: calls `clear_element_keyboard(session, backend_node_id)`
  4. Else: calls `resolve_to_object_id()` + `Runtime.callFunctionOn` with `CLEAR_JS` (existing path)
- [ ] `resolve_to_object_id()` function signature unchanged — still used by the non-text path and by `execute_upload`/`execute_submit`
- [ ] No changes to `FILL_JS`, `CLEAR_JS`, or any other existing constants
- [ ] No changes to `execute_fill`, `execute_fill_many`, `execute_clear`, `execute_upload`, `execute_submit` — they call `fill_element`/`clear_element` which handle branching internally
- [ ] `cargo build` succeeds with no warnings
- [ ] `cargo clippy` passes (all=deny, pedantic=warn)
- [ ] `cargo fmt --check` passes

**Notes**: The key insight is that `fill_element` and `clear_element` now need `backend_node_id` for both branches. Extract the `resolve_target_to_backend_node_id` call to the top of both functions (it's already the first step in `resolve_to_object_id`). For the text path, pass `backend_node_id` directly to the keyboard functions. For the non-text path, pass the target string to `resolve_to_object_id` which re-resolves it (minor redundancy but keeps `resolve_to_object_id` unchanged for other callers).

### T004: Add regression test (Gherkin + step definitions)

**File(s)**: `tests/features/161-fix-form-fill-react-controlled-inputs.feature`, `tests/bdd.rs`
**Type**: Create / Modify
**Depends**: T003
**Acceptance**:
- [ ] Gherkin feature file created at `tests/features/161-fix-form-fill-react-controlled-inputs.feature`
- [ ] All 7 acceptance criteria from requirements.md have corresponding `@regression` scenarios
- [ ] Step definitions added to `tests/bdd.rs` for any new steps not already defined
- [ ] `cargo test --test bdd` compiles and passes (Chrome-dependent scenarios may be skipped in CI)

### T005: Manual smoke test against SauceDemo

**File(s)**: N/A (manual verification)
**Type**: Verify
**Depends**: T003
**Acceptance**:
- [ ] Build: `cargo build`
- [ ] Launch: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate: `./target/debug/agentchrome navigate https://www.saucedemo.com/`
- [ ] Snapshot: `./target/debug/agentchrome page snapshot`
- [ ] Fill username: `./target/debug/agentchrome form fill <username-uid> "standard_user"`
- [ ] Verify username: `./target/debug/agentchrome js exec "document.getElementById('user-name').value"` → returns `"standard_user"`
- [ ] Fill password: `./target/debug/agentchrome form fill <password-uid> "secret_sauce"`
- [ ] Verify password: `./target/debug/agentchrome js exec "document.getElementById('password').value"` → returns `"secret_sauce"`
- [ ] Click login (same snapshot UIDs still work): `./target/debug/agentchrome interact click <login-uid>` → succeeds (no "No node found" error)
- [ ] Verify navigation occurred (logged in successfully)
- [ ] Disconnect: `./target/debug/agentchrome connect disconnect`
- [ ] Kill orphaned Chrome: `pkill -f 'chrome.*--remote-debugging' || true`

### T006: Verify no regressions

**File(s)**: N/A (existing test files)
**Type**: Verify (no file changes)
**Depends**: T003, T004
**Acceptance**:
- [ ] `cargo test --lib` passes (unit tests)
- [ ] `cargo test --test bdd` passes (BDD tests)
- [ ] `cargo clippy` passes
- [ ] `cargo fmt --check` passes
- [ ] No side effects in related code paths per blast radius from design.md

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #161 | 2026-03-12 | Initial defect spec |

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T004)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Manual smoke test task included (T005) with SauceDemo coverage
