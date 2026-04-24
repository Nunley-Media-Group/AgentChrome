# Defect Report: interact click CSS selector path fails to trigger onclick

**Issue**: #252
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley
**Severity**: High
**Related Spec**: `specs/feature-mouse-interactions/`

---

## Reproduction

### Steps to Reproduce

1. `agentchrome navigate https://the-internet.herokuapp.com/add_remove_elements/`
2. `agentchrome page snapshot` (to populate the UID map — used only for the control comparison)
3. Run the CSS-selector click: `agentchrome interact click "css:button[onclick='addElement()']"`
4. Inspect the DOM for any `.added-manually` element (e.g., `agentchrome js exec "document.querySelectorAll('.added-manually').length"`).

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS 15 (Darwin 25.3.0) |
| **Version / Commit** | 1.47.0 / branch `252-fix-interact-click-css-selector-onclick` |
| **Browser / Runtime** | Chrome via CDP |
| **Configuration** | Default session; no frame targeting |

### Frequency

Always — reproducible on every invocation against `the-internet.herokuapp.com/add_remove_elements/`.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `interact click "css:button[onclick='addElement()']"` dispatches a mouse press/release at the button's center, firing the `onclick` handler and appending a `.added-manually` div to the DOM. |
| **Actual** | Command returns `{"clicked": "...", "navigated": false}` with exit 0 and no error, but no `.added-manually` div is appended. The `onclick` handler did not fire. |

### Control Results (on the same page, same element)

- `interact click s2` (UID path) → handler fires, `.added-manually` appears.
- `interact click-at 89 113` (raw coordinates — the element's verified center) → handler fires, `.added-manually` appears.
- `interact click "css:button[onclick='addElement()']"` (CSS path) → handler does **not** fire.

Because the UID path and the raw-coordinate path at the same (x, y) both succeed, the defect is isolated to the CSS-selector resolution-and-dispatch path in `src/interact.rs`.

### Error Output

None — the command exits successfully. The bug is silent.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario, tagged `@regression`.**

### AC1: CSS selector click triggers onclick

**Given** the page `the-internet.herokuapp.com/add_remove_elements/` is loaded
**When** `agentchrome interact click "css:button[onclick='addElement()']"` runs
**Then** a new `.added-manually` element is present in the DOM
**And** the command exits 0.

### AC2: UID click behaviour unchanged

**Given** the same page is loaded and a snapshot has populated the UID map
**When** `agentchrome interact click <uid>` is run against the "Add Element" button
**Then** a new `.added-manually` element is present in the DOM (no regression from today's behaviour).

### AC3: No regression on navigation clicks via CSS selector

**Given** a page containing a standard `<a href="...">` link resolvable by a CSS selector
**When** `agentchrome interact click "css:<selector>"` runs against that link
**Then** the browser navigates to the link target
**And** the command reports `"navigated": true`.

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Audit the CSS-selector click dispatch in `src/interact.rs` and make it behaviourally equivalent to the UID path for `onclick`-driven buttons on the reference page. | Must |
| FR2 | Ensure the CSS-selector path calls `DOM.scrollIntoViewIfNeeded` before dispatching the mouse event (as the UID path does). | Must |
| FR3 | Add a `@regression` Gherkin scenario covering CSS-selector clicks on `onclick`-driven buttons so the fix is guarded. | Must |

---

## Out of Scope

- Changes to the UID click path (`resolve_target_to_backend_node_id` branch for UIDs).
- Other `interact` subcommands (drag, hover, keyboard).
- Broader refactors of mouse-event dispatch.
- Any change to the `click-at` path.

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #252 | 2026-04-23 | Initial defect report |
