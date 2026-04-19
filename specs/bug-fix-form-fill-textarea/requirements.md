# Defect Report: Form fill not setting value on textarea elements

**Issue**: #136
**Date**: 2026-02-17
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/16-form-input-and-filling/`

---

## Reproduction

### Steps to Reproduce

1. `agentchrome connect --launch --headless`
2. `agentchrome navigate https://www.google.com`
3. `agentchrome page snapshot`
4. `agentchrome form fill s9 "test query"` — reports success
5. `agentchrome js exec --uid s9 "(el) => el.value"` — returns `""`

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS Darwin 25.3.0 |
| **Version / Commit** | 1.0.0 (commit e50f7b3) |
| **Browser / Runtime** | HeadlessChrome/144.0.0.0 |
| **Configuration** | Default |

### Frequency

Always

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | After `form fill <uid> "value"`, the textarea's value is set to `"value"` and subsequent reads via `js exec --uid <uid> "(el) => el.value"` return `"value"` |
| **Actual** | `form fill` returns `{"filled": "s9", "value": "test query"}` (appears successful), but the element's actual value is empty string `""` |

### Error Output

No error output — the command silently succeeds without actually setting the value. The `HTMLInputElement.prototype.value` setter is called on a `<textarea>` element via `nativeInputValueSetter.call(el, value)`, which has no effect but does not throw.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Form fill sets textarea value

**Given** a page with a `<textarea>` element
**When** I run `form fill <uid> "test value"`
**Then** the textarea's value is set to `"test value"`
**And** `js exec --uid <uid> "(el) => el.value"` returns `"test value"`

**Example**:
- Given: Google search page with textarea element at UID s9
- When: `form fill s9 "test query"`
- Then: `js exec --uid s9 "(el) => el.value"` returns `"test query"`

### AC2: Form fill still works on input elements

**Given** a page with an `<input type="text">` element
**When** I run `form fill <uid> "test value"`
**Then** the input's value is set to `"test value"`
**And** `js exec --uid <uid> "(el) => el.value"` returns `"test value"`

### AC3: Form clear works on textarea elements

**Given** a `<textarea>` element with an existing value
**When** I run `form clear <uid>`
**Then** the textarea's value is set to `""`
**And** `js exec --uid <uid> "(el) => el.value"` returns `""`

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | In `FILL_JS`, select the correct native setter prototype based on element type — use `HTMLTextAreaElement.prototype.value.set` for textarea elements and `HTMLInputElement.prototype.value.set` for input elements, instead of short-circuiting with `\|\|` | Must |
| FR2 | Apply the same fix to `CLEAR_JS`, which has the identical `\|\|` short-circuit bug | Must |

---

## Out of Scope

- Changes to `interact type` (works correctly via keyboard events)
- Changes to `form fill-many` beyond inheriting the shared `FILL_JS` fix (it already calls `fill_element` which uses `FILL_JS`)
- Support for `contenteditable` elements
- Refactoring beyond the minimal fix to `FILL_JS` and `CLEAR_JS`

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC2)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
