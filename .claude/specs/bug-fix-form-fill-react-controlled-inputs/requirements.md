# Defect Report: Form fill silently failing on React-controlled inputs

**Issues**: #161
**Date**: 2026-03-12
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/16-form-input-and-filling/`

---

## Reproduction

### Steps to Reproduce

1. `agentchrome connect --launch`
2. `agentchrome navigate https://www.saucedemo.com/`
3. `agentchrome page snapshot` (note s1=Username textbox)
4. `agentchrome form fill s1 "standard_user"` → returns `{"filled":"s1","value":"standard_user"}`
5. `agentchrome js exec "document.getElementById('user-name').value"` → returns `{"result":"","type":"string"}` (EMPTY!)
6. `agentchrome interact click s1` → fails with `{"error":"Interaction failed (scroll_into_view): CDP protocol error (-32000): No node found for given backend id","code":5}`

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS Darwin 25.3.0 |
| **Version / Commit** | 1.10.0 |
| **Browser / Runtime** | Chrome 145 via CDP |
| **Test Site** | https://www.saucedemo.com/ (React-based) |

### Frequency

Always

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `form fill s1 "standard_user"` sets the DOM value to "standard_user", the value persists visually and across React render cycles, and subsequent `interact click` on the same UIDs still works |
| **Actual** | `form fill` returns success JSON but the DOM value is empty; React's internal state is not updated; backend node IDs from the accessibility snapshot become stale, breaking subsequent `interact click` calls |

### Error Output

```
Step 5 (value verification):
{"result":"","type":"string"}

Step 6 (subsequent interact click):
{"error":"Interaction failed (scroll_into_view): CDP protocol error (-32000): No node found for given backend id","code":5}
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Bug Is Fixed — Form fill sets value on React-controlled inputs

**Given** a connected Chrome session on a React-based page with controlled input elements (e.g., SauceDemo login)
**When** I run `agentchrome form fill <uid> "value"`
**Then** the DOM value is set to "value" AND the value persists visually and in `js exec` verification

**Example**:
- Given: SauceDemo login page with Username textbox at UID s1
- When: `form fill s1 "standard_user"`
- Then: `js exec "document.getElementById('user-name').value"` returns `"standard_user"`

### AC2: Form fill does not invalidate node references

**Given** a connected Chrome session with a fresh accessibility snapshot
**When** I run `agentchrome form fill <uid> "value"` on a text input element
**Then** subsequent `interact click <uid>` on the same or other UIDs from the same snapshot still works correctly without requiring a new snapshot

### AC3: No Regression — Form fill still works on vanilla HTML inputs

**Given** a connected Chrome session on a page with standard (non-framework) HTML `<input type="text">` elements
**When** I run `agentchrome form fill <uid> "value"`
**Then** the field value is set correctly AND `js exec` verification confirms the value

### AC4: No Regression — Form fill still works on select, checkbox, radio elements

**Given** a connected Chrome session on a page with select dropdowns, checkboxes, and radio buttons
**When** I run `agentchrome form fill <uid> "value"` on each element type
**Then** the element state is updated correctly for each type (select option changes, checkbox/radio checked state changes)

### AC5: No Regression — Form fill still works on textarea elements

**Given** a connected Chrome session on a page with `<textarea>` elements
**When** I run `agentchrome form fill <uid> "multiline text"`
**Then** the textarea value is set correctly AND `js exec` verification confirms the value

### AC6: No Regression — form fill-many inherits the fix

**Given** a connected Chrome session on a React-based page with multiple controlled input elements
**When** I run `agentchrome form fill-many '[{"uid":"s1","value":"user"},{"uid":"s2","value":"pass"}]'`
**Then** both fields have their values set correctly AND `js exec` verification confirms both values

### AC7: No Regression — form clear still works

**Given** a connected Chrome session with a text input that has a value set
**When** I run `agentchrome form clear <uid>`
**Then** the field value is cleared to empty string AND `js exec` verification confirms the value is empty

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `form fill` must use keyboard simulation (`Input.dispatchKeyEvent`) for text-type inputs (input text/password/email/number/tel/url/search, textarea) to ensure framework compatibility | Must |
| FR2 | `form fill` for text inputs must focus the element via `DOM.focus` using `backendNodeId` (not `DOM.resolveNode`) to avoid invalidating cached accessibility tree node references | Must |
| FR3 | `form fill` for text inputs must clear existing content before typing the new value (select-all + type replacement) | Must |
| FR4 | `form fill` must continue using the existing JS-based approach (`Runtime.callFunctionOn`) for select, checkbox, and radio elements where keyboard simulation is not applicable | Must |
| FR5 | `form clear` for text inputs must use the same keyboard-based approach (focus + select-all + delete) | Must |
| FR6 | `form fill-many` must inherit the same keyboard-based fill for text inputs via the shared `fill_element` path | Must |

---

## Out of Scope

- Changing the `interact type` command (already works correctly)
- Supporting other frameworks beyond React (Vue, Angular) explicitly — though the keyboard simulation approach should work for all
- Adding a `--strategy` flag to choose between programmatic and keyboard-based fill
- Eliminating `DOM.resolveNode` from the select/checkbox/radio code path (these still need `Runtime.callFunctionOn`)
- Refactoring beyond the minimal fix to `fill_element`, `clear_element`, and their supporting code

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #161 | 2026-03-12 | Initial defect spec |

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3, AC4, AC5, AC6, AC7)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
- [x] Cross-validation via independent read command included (retrospective learning: AC1 verifies via `js exec`, not just command output)
- [x] Path audit performed: `form fill-many` (FR6) and `form clear` (FR5, AC7) share the same code path and are explicitly covered
