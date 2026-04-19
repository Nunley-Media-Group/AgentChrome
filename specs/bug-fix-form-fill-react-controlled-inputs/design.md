# Root Cause Analysis: Form fill silently failing on React-controlled inputs

**Issues**: #161
**Date**: 2026-03-12
**Status**: Draft
**Author**: Claude

---

## Root Cause

The `form fill` command fails on React-controlled inputs due to two independent issues in `src/form.rs`:

**Issue 1 — React state bypass**: The `FILL_JS` JavaScript function (lines 257–287) sets input values using `Object.getOwnPropertyDescriptor(proto, 'value').set` (the native DOM value setter), then dispatches synthetic `input` and `change` events via `new Event()`. This approach bypasses React's fiber-based reconciliation system because: (a) React 16+ tracks input values internally — setting via the native setter doesn't update React's tracked state, so on the next render cycle React resets the value to its own state (empty string); (b) React's synthetic event system requires events to originate from the browser's native event dispatch path, not programmatically constructed `Event` objects, so the dispatched events don't trigger React's `onChange` handlers.

**Issue 2 — Node ID invalidation**: The `fill_element()` function (line 375) calls `resolve_to_object_id()`, which calls `DOM.resolveNode` with a `backendNodeId`. This CDP call triggers DOM tree resolution that invalidates the cached backend node IDs from the accessibility snapshot, causing subsequent `interact click` calls on the same UIDs to fail with "No node found for given backend id". In contrast, `interact click` uses `DOM.scrollIntoViewIfNeeded` and `DOM.getBoxModel` with `backendNodeId` directly — these CDP methods do not trigger the same invalidation.

The working workaround (`interact click` to focus + `interact type` to simulate keyboard input) succeeds because `Input.dispatchKeyEvent` sends real `KeyDown`/`KeyPress`/`KeyUp` events that React's event system handles correctly, and neither `DOM.scrollIntoViewIfNeeded` nor `DOM.getBoxModel` invalidates cached node IDs.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/form.rs` | 257–287 | `FILL_JS` — JavaScript function that uses native setter to set value; bypasses React |
| `src/form.rs` | 290–314 | `CLEAR_JS` — JavaScript function that uses native setter to clear value; same issue |
| `src/form.rs` | 350–367 | `resolve_to_object_id()` — calls `DOM.resolveNode`, invalidating cached backend node IDs |
| `src/form.rs` | 370–388 | `fill_element()` — orchestrates fill via `resolve_to_object_id` + `Runtime.callFunctionOn` + `FILL_JS` |
| `src/form.rs` | 391–405 | `clear_element()` — orchestrates clear via `resolve_to_object_id` + `Runtime.callFunctionOn` + `CLEAR_JS` |

### Triggering Conditions

- The target element is a text-type input (`<input type="text|password|email|...">` or `<textarea>`) on a page using React (or any framework with a virtual DOM and controlled component model)
- `DOM.resolveNode` is called before the fill, invalidating cached accessibility tree backend node IDs
- The value appears set momentarily but React's reconciliation resets it on the next render cycle

---

## Fix Strategy

### Approach

Replace the JS-based value setter with CDP keyboard simulation for text-type elements. This mirrors the proven `interact click` + `interact type` workaround. The change is scoped to `fill_element()` and `clear_element()` in `src/form.rs`:

1. **Detect element type** — Call `DOM.describeNode` with `backendNodeId` to get `nodeName` and `attributes`. This CDP method is read-only and does not invalidate cached node IDs (unlike `DOM.resolveNode`).

2. **Branch by element type**:
   - **Text-type elements** (input text/password/email/number/tel/url/search, textarea): Use a hybrid approach — `DOM.focus` to focus the element, then `Runtime.evaluate` to call `document.activeElement.select()` to select all existing text (cross-platform; `Ctrl+A` does not select all in macOS Chrome), then `Input.dispatchKeyEvent` with `type: "char"` for each character of the new value. This avoids both `DOM.resolveNode` (fixing node invalidation) and the native value setter (fixing React compatibility). `char` events trigger React's synthetic event system.
   - **Select, checkbox, radio**: Continue using the existing `DOM.resolveNode` + `Runtime.callFunctionOn` + JS approach, since keyboard simulation is not applicable for these element types.

3. **Clear via React-compatible JS** — For `clear_element()` on text-type elements, use `DOM.focus` + `Runtime.evaluate` with a JS snippet that:
   - Sets the native value to `""` via the native property setter
   - Dispatches `new InputEvent('input', { inputType: 'deleteContentBackward' })` which React's event system recognizes as a deletion

   **Note on keyboard clear approach**: `Backspace` `keyDown`/`keyUp` events do not reliably trigger React `onChange` when the selection was set programmatically (via `document.activeElement.select()`). Chrome does not dispatch a synthetic `input` event in response to CDP `keyDown` for Backspace in this context. The InputEvent approach avoids this problem and is verified to work on React-controlled inputs.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/form.rs` | Add `describe_element()` helper — calls `DOM.describeNode` with `backendNodeId`, returns `(nodeName, input_type)` | Detect element type without calling `DOM.resolveNode` |
| `src/form.rs` | Add `is_text_input()` helper — returns true for input text/password/email/number/tel/url/search and textarea | Centralize element type classification logic |
| `src/form.rs` | Add `CLEAR_ACTIVE_ELEMENT_JS` constant — JS expression that clears `document.activeElement` value and dispatches a React-compatible `InputEvent` | Module-level constant for the clear expression |
| `src/form.rs` | Add `fill_element_keyboard()` — focuses element via `DOM.focus`, selects all via `Runtime.evaluate("document.activeElement.select()")`, types value via `char` key events | Cross-platform keyboard-based fill for text elements |
| `src/form.rs` | Add `clear_element_keyboard()` — focuses element via `DOM.focus`, clears via `Runtime.evaluate(CLEAR_ACTIVE_ELEMENT_JS)` | React-compatible clear for text elements |
| `src/form.rs` | Modify `fill_element()` — detect element type first; if text-type, call `fill_element_keyboard()`; otherwise, fall through to existing `DOM.resolveNode` + `Runtime.callFunctionOn` + `FILL_JS` path | Route text inputs to keyboard approach, keep JS for non-text |
| `src/form.rs` | Modify `clear_element()` — same branching: text-type uses `clear_element_keyboard()`; non-text uses existing `DOM.resolveNode` + `CLEAR_JS` path | Same fix applied to clear |
| `src/form.rs` | `FILL_JS` and `CLEAR_JS` constants — no changes | Still used for select/checkbox/radio via the non-text path |

### CDP Call Flow (Text Input Fill — New)

```
1. resolve_target_to_backend_node_id(target) → backendNodeId
   (from snapshot UID map or CSS selector — no change)

2. DOM.describeNode({ backendNodeId }) → { node: { nodeName, attributes } }
   (read-only, does NOT invalidate cached node IDs)

3. is_text_input(nodeName, attributes) → true

4. DOM.focus({ backendNodeId })
   (focuses element — does NOT use DOM.resolveNode)

5. Runtime.evaluate({ expression: "document.activeElement.select()" })
   (Selects all existing text — cross-platform, works on macOS/Linux/Windows Chrome)
   (NOTE: Ctrl+A does NOT select all in text inputs on macOS Chrome — Meta+A and
    Ctrl+A both fail. document.activeElement.select() is the reliable cross-platform approach.)

6. For each char in value:
     Input.dispatchKeyEvent({ type: "char", text: char })
   (Types the value — replaces selection on first char, then appends. React handles these
    as real keyboard events and updates its internal state.)
```

### CDP Call Flow (Text Input Clear — New)

```
1. resolve_target_to_backend_node_id(target) → backendNodeId

2. DOM.describeNode({ backendNodeId }) → text-type

3. DOM.focus({ backendNodeId })

4. Runtime.evaluate({ expression: CLEAR_ACTIVE_ELEMENT_JS })
   (Sets native value to "" AND dispatches InputEvent with inputType='deleteContentBackward'.
    React's event system recognizes deleteContentBackward and updates its state to "".)
```

### CDP Call Flow (Select/Checkbox/Radio — Unchanged)

```
1. resolve_target_to_backend_node_id(target) → backendNodeId
2. DOM.describeNode({ backendNodeId }) → not text-type
3. DOM.resolveNode({ backendNodeId }) → objectId      ← still used
4. Runtime.callFunctionOn({ objectId, FILL_JS, [value] })
```

### Blast Radius

- **Direct impact**: `fill_element()` and `clear_element()` in `src/form.rs` — logic branching added; new helper functions added
- **Indirect impact**: All callers of `fill_element` and `clear_element`:
  - `execute_fill()` — single fill, no changes needed
  - `execute_fill_many()` — iterates `fill_element`, inherits fix automatically
  - `execute_clear()` — single clear, no changes needed
- **Unaffected**: `execute_upload()`, `execute_submit()` — different code paths, no shared state with the changed functions
- **Unaffected**: `FILL_JS`, `CLEAR_JS` constants — still used for select/checkbox/radio
- **Risk level**: Low — the keyboard simulation approach is proven (identical to `interact click` + `interact type`), and the select/checkbox/radio path is completely unchanged

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Vanilla HTML text inputs stop working with keyboard approach | Low | AC3 explicitly tests vanilla HTML inputs. `Input.dispatchKeyEvent` works identically on vanilla and framework inputs — it's the same CDP mechanism used by `interact type`. |
| Select/checkbox/radio elements break | None | These still use the existing JS path (unchanged code). AC4 regression test covers this. |
| Textarea elements break | Low | AC5 tests textarea specifically. Textarea has `nodeName == "TEXTAREA"`, classified as text-type, uses keyboard approach. |
| `fill-many` breaks | Low | Uses the same `fill_element()` path. AC6 covers this. |
| `form clear` breaks | Low | Same branching logic applied. AC7 covers this. |
| `DOM.describeNode` invalidates node IDs like `DOM.resolveNode` | Very Low | `DOM.describeNode` is read-only and is already used elsewhere (`interact.rs` CSS selector resolution) without causing node invalidation. AC2 validates this. |
| Ctrl+A doesn't select all on some element types | Low | Standard browser behavior for text inputs/textareas. CDP keyboard events are dispatched to the focused element, and Ctrl+A is the universal select-all shortcut in text fields across all platforms in Chrome. |
| Existing text not fully cleared before typing new value | Low | The Ctrl+A + type approach replaces any selection. If the field is empty, Ctrl+A is a no-op and typing proceeds normally. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Fix `FILL_JS` to use `InputEvent` instead of `Event` | Use `new InputEvent('input', { bubbles: true, inputType: 'insertText', data: value })` which React recognizes | Only fixes React event handling (Issue 1), does not fix `DOM.resolveNode` invalidation (Issue 2). Also fragile — depends on React's internal event detection logic which may change across versions. |
| Use `DOM.setAttributeValue` to set the value attribute | Set the HTML attribute directly via CDP | Does not trigger any framework event handlers. The `value` property and `value` attribute are different things in the DOM — setting the attribute doesn't update the property for inputs that have been interacted with. |
| Use `Runtime.evaluate` with `document.querySelector` instead of `DOM.resolveNode` | Avoid `DOM.resolveNode` but still use JS setter | Fixes Issue 2 (node invalidation) but not Issue 1 (React state bypass). Also requires mapping UIDs to CSS selectors, which is not straightforward. |
| **Selected: Keyboard simulation** | `DOM.focus` + `Input.dispatchKeyEvent` for text inputs | Fixes both issues simultaneously. Proven approach (identical to `interact type`). Framework-agnostic — works with React, Vue, Angular, vanilla HTML. Does not call `DOM.resolveNode` for text inputs. |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
- [x] CDP call flows documented for both text and non-text paths
- [x] Alternatives considered with clear rationale for selection
