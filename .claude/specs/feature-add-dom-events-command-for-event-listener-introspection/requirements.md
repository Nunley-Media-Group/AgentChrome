# Requirements: DOM Events Command for Event Listener Introspection

**Issues**: #192
**Date**: 2026-04-16
**Status**: Approved
**Author**: Claude (spec agent)

---

## User Story

**As a** browser automation engineer debugging interaction failures
**I want** to see what event listeners are attached to a DOM element
**So that** I can understand how events are handled and choose the correct interaction approach

---

## Background

Users report spending many calls trying to reverse-engineer how elements process events — whether a button uses `addEventListener` vs `onclick`, what an overlay's click handler does, and whether events bubble or are captured. Chrome DevTools exposes `getEventListeners()` in the console, but this is not available via page scripts. AgentChrome's CDP access can use `DOMDebugger.getEventListeners` to surface this information.

Currently 13 DOM subcommands exist in `src/dom.rs` (select, get-attribute, get-text, get-html, set-attribute, set-text, remove, get-style, set-style, parent, children, siblings, tree). No event listener introspection command exists and the `DOMDebugger.getEventListeners` CDP method is unused. Users must guess at event handling behavior or write complex `js exec` probes.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: List event listeners on an element via addEventListener

**Given** a DOM element identified by UID or CSS selector that has event listeners attached via `addEventListener`
**When** `dom events <target>` is run
**Then** JSON output lists all attached event listeners
**And** each listener object contains: `type` (event name), `useCapture` (boolean), `once` (boolean), `passive` (boolean)
**And** each listener object contains `handler` with `description` (source text or function name), `scriptId` (string or null), `lineNumber` (integer or null), `columnNumber` (integer or null)

**Example**:
- Given: A button with `addEventListener('click', handleClick, { capture: false, once: true })`
- When: `agentchrome dom events css:button`
- Then: Output includes `{"type":"click","useCapture":false,"once":true,"passive":false,"handler":{"description":"function handleClick()...","scriptId":"42","lineNumber":10,"columnNumber":0}}`

### AC2: Inline event handlers included

**Given** a DOM element with an inline event handler attribute (e.g., `onclick="alert('hi')"`)
**When** `dom events <target>` is run
**Then** the inline handler is included in the listeners array alongside any `addEventListener` handlers
**And** its `type` field is the event name (e.g., `"click"`)

**Example**:
- Given: `<button onclick="alert('hi')">Click</button>`
- When: `agentchrome dom events css:button`
- Then: Output includes a listener with `"type":"click"` representing the inline handler

### AC3: Frame-scoped event introspection

**Given** `--frame <index>` argument
**When** `dom events <target>` is run
**Then** the element is resolved and listeners queried within the specified frame context

### AC4: Element with no listeners

**Given** an element with no event listeners attached (neither `addEventListener` nor inline handlers)
**When** `dom events <target>` is run
**Then** an empty listeners array is returned: `{"listeners":[]}`
**And** the exit code is 0 (not an error)

### AC5: Handler source location unavailable

**Given** a DOM element with an event listener whose handler source location cannot be determined by CDP
**When** `dom events <target>` is run
**Then** the `handler.scriptId`, `handler.lineNumber`, and `handler.columnNumber` fields appear as `null`
**And** the `handler.description` field still contains the function source text or name

### AC6: Output format compliance

**Given** the `dom events` command
**When** run with `--json` flag
**Then** output is valid JSON on stdout
**When** run with `--plain` flag
**Then** output is human-readable plain text (one listener per line)
**When** run with `--pretty` flag
**Then** output is indented JSON

### AC7: Documentation updated

**Given** the new `dom events` command
**When** `examples dom` is run
**Then** `dom events` examples are included in the output

### Generated Gherkin Preview

```gherkin
Feature: DOM Events Command
  As a browser automation engineer debugging interaction failures
  I want to see what event listeners are attached to a DOM element
  So that I can understand how events are handled and choose the correct interaction approach

  Scenario: List event listeners on an element via addEventListener
    Given a DOM element with addEventListener listeners
    When I run "agentchrome dom events <target>"
    Then the output JSON contains a "listeners" array
    And each listener has "type", "useCapture", "once", "passive" fields
    And each listener has a "handler" object with source details

  Scenario: Inline event handlers included
    Given a DOM element with an onclick attribute
    When I run "agentchrome dom events <target>"
    Then the output includes the inline handler in the listeners array

  Scenario: Frame-scoped event introspection
    Given a connected session with an iframe
    When I run "agentchrome dom --frame 0 events <target>"
    Then the listeners are queried within the frame context

  Scenario: Element with no listeners
    Given a DOM element with no event listeners
    When I run "agentchrome dom events <target>"
    Then the output JSON contains an empty "listeners" array
    And the exit code should be 0

  Scenario: Handler source location unavailable
    Given a DOM element with a listener whose source is unavailable
    When I run "agentchrome dom events <target>"
    Then handler.scriptId, handler.lineNumber, handler.columnNumber are null
    And handler.description still contains function text

  Scenario: Output format compliance
    Given a DOM element with event listeners
    When I run "agentchrome dom events <target> --plain"
    Then the output is human-readable plain text

  Scenario: Documentation updated
    When I run "agentchrome examples dom"
    Then the output includes "dom events" examples
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | New `dom events <target>` subcommand with structured JSON output | Must | Target supports UID, CSS selector (`css:`), and integer backendNodeId |
| FR2 | CDP `DOMDebugger.getEventListeners` integration | Must | Requires `Runtime.RemoteObjectId` for the target element |
| FR3 | Support UID and CSS selector targeting (same as other dom subcommands) | Must | Reuse `resolve_node()` helper |
| FR4 | Frame-scoped targeting with `--frame` flag | Should | Inherited from `DomArgs.frame` |
| FR5 | Include both `addEventListener` and inline attribute handlers in output | Must | CDP returns both handler types |
| FR6 | Handler source location fields (`scriptId`, `lineNumber`, `columnNumber`) nullable when unavailable | Must | Use `null` for absent, not omit |
| FR7 | Plain text output mode for `--plain` flag | Must | One listener per line: `type: <event> capture:<bool> once:<bool> passive:<bool>` |
| FR8 | Help documentation and `after_long_help` examples on the subcommand | Must | Consistent with other dom subcommands |
| FR9 | Built-in examples updated in `examples.rs` | Must | Add `dom events` entry to dom command group |
| FR10 | BDD test scenarios covering `dom events` | Must | One scenario per AC |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Response time comparable to other dom subcommands (< 500ms for typical elements) |
| **Reliability** | Graceful handling when CDP returns unexpected data; empty array not error for no listeners |
| **Platforms** | macOS, Linux, Windows (same as all agentchrome commands) |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `target` | String | UID (e.g., `s1`), CSS selector (e.g., `css:button`), or integer backendNodeId | Yes |
| `--frame` | String | Frame index, path, or `auto` | No (inherited from DomArgs) |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| `listeners` | Array | Array of event listener objects |
| `listeners[].type` | String | Event type name (e.g., `"click"`, `"keydown"`) |
| `listeners[].useCapture` | Boolean | Whether the listener is in the capture phase |
| `listeners[].once` | Boolean | Whether the listener fires only once |
| `listeners[].passive` | Boolean | Whether the listener is passive |
| `listeners[].handler.description` | String | Function source text or name |
| `listeners[].handler.scriptId` | String or null | Script ID where the handler is defined; `null` when unavailable |
| `listeners[].handler.lineNumber` | Integer or null | Line number in the source script; `null` when unavailable |
| `listeners[].handler.columnNumber` | Integer or null | Column number in the source script; `null` when unavailable |

---

## Dependencies

### Internal Dependencies
- [x] DOM command group (`src/dom.rs`) — existing infrastructure
- [x] `resolve_node()` helper — resolves UID/CSS/integer to CDP nodeId
- [x] `setup_session_with_interceptors` — session management
- [x] Frame targeting (`resolve_optional_frame`) — existing infrastructure

### External Dependencies
- [x] Chrome CDP `DOMDebugger.getEventListeners` method

### Blocked By
- None

---

## Out of Scope

- Firing custom events (use `js exec` for that)
- Modifying or removing event listeners
- Event breakpoints or stepping
- Filtering listeners by event type (future enhancement)
- Showing delegated/jQuery event handler internals

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| All ACs pass BDD tests | 7/7 scenarios green | `cargo test --test bdd` |
| Smoke test against real Chrome | Pass | Manual verification during `/verifying-specs` |

---

## Open Questions

- None

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #192 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
