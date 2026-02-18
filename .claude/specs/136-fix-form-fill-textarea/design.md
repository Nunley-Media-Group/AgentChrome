# Root Cause Analysis: Form fill not setting value on textarea elements

**Issue**: #136
**Date**: 2026-02-17
**Status**: Draft
**Author**: Claude

---

## Root Cause

In `src/form.rs`, the `FILL_JS` and `CLEAR_JS` JavaScript constants use `Object.getOwnPropertyDescriptor` to obtain the native `value` setter from element prototypes, then call it on the target element. The two prototypes are combined with `||`:

```javascript
const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
)?.set || Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, 'value'
)?.set;
```

The `||` operator short-circuits: `HTMLInputElement.prototype.value.set` is always a valid function (truthy), so the `HTMLTextAreaElement.prototype.value.set` branch is **never evaluated**. When `nativeInputValueSetter.call(el, value)` is called on a `<textarea>` element, the `HTMLInputElement` setter silently has no effect — it doesn't throw, but it also doesn't set the value, because the element is not an `HTMLInputElement` instance.

The fix is to check the element's tag name at runtime and select the correct prototype setter accordingly.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/form.rs` | 240–271 | `FILL_JS` — JavaScript function for setting form field values |
| `src/form.rs` | 274–299 | `CLEAR_JS` — JavaScript function for clearing form field values |

### Triggering Conditions

- The target element is a `<textarea>` (not an `<input>`)
- `HTMLInputElement.prototype.value.set` exists (always true in Chrome)
- The `||` short-circuit prevents `HTMLTextAreaElement.prototype.value.set` from being used

---

## Fix Strategy

### Approach

Replace the `||` short-circuit with a conditional that inspects `el.tagName` to select the correct prototype. If the element is a `<textarea>`, use `HTMLTextAreaElement.prototype`; otherwise use `HTMLInputElement.prototype`. This is the minimal correct fix — it uses the same native setter approach but picks the right one based on element type.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/form.rs` (`FILL_JS`) | Replace `||` chain with `tagName`-based conditional to select the correct prototype for `getOwnPropertyDescriptor` | Ensures textarea elements get the `HTMLTextAreaElement` setter |
| `src/form.rs` (`CLEAR_JS`) | Same fix — replace `||` chain with `tagName`-based conditional | Identical bug pattern, same fix |

### Blast Radius

- **Direct impact**: `FILL_JS` and `CLEAR_JS` constants in `src/form.rs`
- **Indirect impact**: `fill_element()` and `clear_element()` functions call these JS constants via `Runtime.callFunctionOn`. All callers (`execute_fill`, `execute_fill_many`, `execute_clear`) are affected, but the change is behavioral-only within the JS — no Rust code changes.
- **Risk level**: Low — the fix narrows the scope of each setter to its correct element type, which is strictly more correct than the current behavior. Input elements continue to use `HTMLInputElement.prototype` as before. Select elements and checkboxes are handled by separate branches and are unaffected.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Input elements stop working after the fix | Low | AC2 explicitly tests that `<input type="text">` fill still works. The `HTMLInputElement` setter path is unchanged for input elements. |
| Select/checkbox/radio elements affected | None | These element types are handled by separate `if` branches before the native setter code path is reached. |
| `form fill-many` breaks | Low | `fill-many` calls the same `fill_element()` → `FILL_JS` path. The fix applies uniformly. AC2 regression test covers this. |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
