# Requirements: Form Submit Subcommand

**Issues**: #147
**Date**: 2026-02-26
**Status**: Draft
**Author**: Claude (nmg-sdlc)

---

## User Story

**As an** AI agent automating form-based workflows
**I want** a `form submit` subcommand to programmatically submit a form
**So that** I can trigger form submission without needing to locate and click a submit button

---

## Background

The `form` command group provides `fill`, `fill-many`, `clear`, and `upload` for form interaction, but has no `submit` subcommand. Currently, agents must submit forms by either clicking a submit button (`interact click css:#submit-button`) or pressing Enter on a focused field (`interact key Enter`). While these workarounds are viable for most cases, a dedicated `form submit` command would be more ergonomic and reliable -- especially for forms with no visible submit button, AJAX-only submissions, or cases where the submit button is dynamically rendered.

Related spec: `.claude/specs/16-form-input-and-filling/` -- original form feature spec, which explicitly lists "Form submission" as out of scope.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Submit form by targeting the form element directly

**Given** a page with a `<form>` element identifiable by UID or CSS selector
**When** I run `agentchrome form submit <TARGET>` where TARGET identifies the form element
**Then** the form's `submit` event is dispatched via JavaScript
**And** JSON output is returned: `{"submitted": "<TARGET>"}`
**And** the exit code is 0

**Example**:
- Given: A page with `<form id="login-form">` and UID "s3" assigned to it
- When: `agentchrome form submit s3`
- Then: `{"submitted": "s3"}`

### AC2: Submit form by targeting an element within the form

**Given** a page with a form containing an input field with UID "s5"
**And** the input field is inside a `<form>` element
**When** I run `agentchrome form submit s5`
**Then** the parent form of the target element is resolved
**And** the parent form's `submit` event is dispatched
**And** JSON output is returned: `{"submitted": "s5"}`
**And** the exit code is 0

### AC3: Submit form by CSS selector

**Given** a page with a form element matching `css:#login-form`
**When** I run `agentchrome form submit css:#login-form`
**Then** the form's `submit` event is dispatched
**And** JSON output is returned: `{"submitted": "css:#login-form"}`
**And** the exit code is 0

### AC4: Submit triggers navigation when form has action attribute

**Given** a form with an `action` attribute pointing to a URL
**When** I run `agentchrome form submit <TARGET>`
**Then** the form submits and navigation occurs
**And** the output includes a `url` field with the new page URL
**And** the exit code is 0

### AC5: Submit with --include-snapshot flag

**Given** a page with a form element
**When** I run `agentchrome form submit <TARGET> --include-snapshot`
**Then** the JSON output includes a `snapshot` field with the updated accessibility tree
**And** the snapshot state file is updated with new UID mappings

### AC6: Error when target is not a form and not inside a form

**Given** a page element that is not a `<form>` and is not a descendant of a `<form>`
**When** I run `agentchrome form submit <TARGET>`
**Then** the command returns a clear error message indicating no form was found
**And** the exit code is non-zero

### AC7: Error when target element does not exist

**Given** Chrome is running with a snapshot taken
**When** I run `agentchrome form submit s999`
**Then** the exit code is nonzero
**And** stderr contains an error about the UID not being found

### AC8: Submit without required arguments

**Given** agentchrome is built
**When** I run `agentchrome form submit`
**Then** the exit code is nonzero
**And** stderr contains usage information about required arguments

### AC9: Submit help displays usage information

**Given** agentchrome is built
**When** I run `agentchrome form submit --help`
**Then** the exit code is 0
**And** stdout contains "TARGET"
**And** stdout contains "--include-snapshot"

### AC10: Form help lists submit subcommand

**Given** agentchrome is built
**When** I run `agentchrome form --help`
**Then** stdout contains "submit"

### AC11: Submit cross-validates via independent read after mutation

**Given** a form with `action` attribute that navigates to a new page
**When** I run `agentchrome form submit <TARGET>`
**And** I subsequently run `agentchrome navigate current`
**Then** the URL returned matches the form's action destination

### Generated Gherkin Preview

```gherkin
Feature: Form submit subcommand
  As an AI agent automating form-based workflows
  I want a form submit subcommand to programmatically submit a form
  So that I can trigger form submission without needing to locate and click a submit button

  Scenario: Submit form by targeting the form element directly
    Given a page with a form element identifiable by UID
    When I run "agentchrome form submit s3"
    Then the form submit event is dispatched
    And the output JSON "submitted" should be "s3"

  Scenario: Submit form by targeting an element within the form
    Given a page with an input inside a form
    When I run "agentchrome form submit s5"
    Then the parent form is resolved and submitted
    And the output JSON "submitted" should be "s5"

  Scenario: Error when target is not in a form
    Given a page element not inside any form
    When I run "agentchrome form submit s10"
    Then the exit code should be nonzero
    And stderr should contain "no form found"
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | `form submit <TARGET>` accepts a UID or CSS selector targeting a form element or element within a form | Must | Core submit targeting |
| FR2 | If the target is a `<form>` element, dispatch `requestSubmit()` on it directly | Must | Direct form submission |
| FR3 | If the target is inside a form (not the form itself), resolve the parent `<form>` and dispatch `requestSubmit()` on it | Must | Parent form resolution |
| FR4 | The command returns JSON output with `submitted` key containing the target identifier | Must | Structured output |
| FR5 | If form submission triggers navigation, include the new URL in the `url` output field | Should | Navigation awareness |
| FR6 | `--include-snapshot` option includes updated accessibility snapshot in output | Should | Snapshot integration |
| FR7 | Return a clear error when the target is not a form and not inside any form | Must | Error handling |
| FR8 | `--tab <ID>` targets a specific tab (via global flag) | Must | Tab targeting |
| FR9 | Plain text output mode (`--plain`) prints human-readable confirmation | Should | Human-readable output |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Submit operation should complete in < 500ms (excluding navigation wait) |
| **Reliability** | Must dispatch proper submit event so browser validation and handlers fire |
| **Platforms** | macOS, Linux, Windows (all platforms Chrome supports) |
| **Error handling** | Clear error messages for invalid UIDs, selectors, or elements not in a form |

---

## UI/UX Requirements

| Element | Requirement |
|---------|-------------|
| **CLI output** | JSON on stdout with `submitted` key; optional `url` and `snapshot` fields |
| **Error output** | JSON on stderr with descriptive `error` message |
| **Plain mode** | `Submitted <target>` for plain text output |
| **Help text** | Long help with examples showing UID and CSS selector usage |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| target | String | Must be valid UID format (s\d+) or css: prefix | Yes |
| --include-snapshot | bool | Flag | No |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| submitted | String | Target identifier that was submitted |
| url | String (optional) | New URL if form submission triggered navigation |
| snapshot | Object (optional) | Accessibility tree if --include-snapshot |

---

## Dependencies

### Internal Dependencies
- [x] #4 -- CDP client (WebSocket communication)
- [x] #6 -- Session management (connection resolution)
- [x] #10 -- UID system (accessibility snapshot UIDs)
- [x] #16 -- Form input and filling (shared form module infrastructure)

### External Dependencies
- Chrome/Chromium with CDP enabled

### Blocked By
- None

---

## Out of Scope

- Form validation bypass (submit should respect browser validation via `requestSubmit()`)
- Multi-form batch submission
- Changes to existing `form fill`, `form clear`, or `form upload`
- Intercepting or modifying form data before submission
- Waiting for AJAX responses after form submission

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| CLI argument validation | All arg-validation BDD scenarios pass | `cargo test --test bdd` |
| Submit dispatches correctly | Smoke test against real form confirms submission | Manual verification |

---

## Open Questions

None -- all requirements are clear from the issue specification.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #147 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Edge cases and error states specified (AC6, AC7, AC8)
- [x] Dependencies identified
- [x] Out of scope defined
- [x] Cross-invocation state validation included (AC11 -- per retrospective learning)
