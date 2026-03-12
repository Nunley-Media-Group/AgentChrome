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

The `form` command group provides `fill`, `fill-many`, `clear`, and `upload` for form interaction, but has no `submit` subcommand. Currently, agents must submit forms by either clicking a submit button (`interact click css:#submit-button`) or pressing Enter on a focused field (`interact key Enter`). While these workarounds are viable for most cases, a dedicated `form submit` command would be more ergonomic and reliable — especially for forms with no visible submit button, AJAX-only submissions, or cases where the submit button is dynamically rendered.

The related original form feature spec is at `.claude/specs/16-form-input-and-filling/`, which explicitly lists "Form submission" as out of scope.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Submit form by UID targeting the form element

**Given** Chrome is running with a page containing a `<form>` element with a known UID
**And** an accessibility snapshot has been taken with UIDs assigned
**When** I run `agentchrome form submit <UID>`
**Then** the form's `submit` event is dispatched
**And** JSON output is returned with `{"submitted": "<UID>"}`
**And** the exit code is 0

**Example**:
- Given: A page with `<form id="login-form">` and UID "s3"
- When: `agentchrome form submit s3`
- Then: `{"submitted": "s3"}`

### AC2: Submit form by CSS selector

**Given** Chrome is running with a page containing a `<form>` element with id "login-form"
**When** I run `agentchrome form submit css:#login-form`
**Then** the form's `submit` event is dispatched
**And** JSON output is returned with `{"submitted": "css:#login-form"}`
**And** the exit code is 0

### AC3: Submit element inside a form resolves parent form

**Given** Chrome is running with a page containing an `<input>` field inside a `<form>`
**And** an accessibility snapshot has been taken
**When** I run `agentchrome form submit <INPUT_UID>` where the UID identifies the input (not the form)
**Then** the parent `<form>` is resolved and submitted
**And** JSON output is returned with `{"submitted": "<INPUT_UID>"}`
**And** the exit code is 0

### AC4: Submit triggers navigation when form has action URL

**Given** Chrome is running with a form that has an `action` attribute pointing to a URL
**When** I run `agentchrome form submit <TARGET>`
**Then** the form submits and navigation occurs
**And** the JSON output includes a `"url"` field with the new page URL

### AC5: Submit non-navigating form (AJAX)

**Given** Chrome is running with a form that uses JavaScript to submit via AJAX (no page navigation)
**When** I run `agentchrome form submit <TARGET>`
**Then** the form's `submit` event is dispatched
**And** the JSON output includes `"submitted"` with the target identifier
**And** no navigation occurs and the command completes successfully

### AC6: Error when target is not a form or inside a form

**Given** Chrome is running with a page element that is not a `<form>` and not inside a `<form>`
**When** I run `agentchrome form submit <TARGET>`
**Then** the command returns a JSON error on stderr indicating no form was found
**And** the exit code is non-zero

### AC7: Include snapshot flag returns updated accessibility tree

**Given** Chrome is running with a page containing a form
**When** I run `agentchrome form submit <TARGET> --include-snapshot`
**Then** the JSON output includes a `"snapshot"` field with the updated accessibility tree
**And** the snapshot state file is updated with new UID mappings

### AC8: Submit respects browser validation

**Given** Chrome is running with a form containing a required field that is empty
**When** I run `agentchrome form submit <TARGET>`
**Then** the form submission is attempted via the standard browser submit mechanism
**And** the browser's built-in validation prevents submission if constraints are not met

### AC9: Submit help displays usage

**Given** agentchrome is built
**When** I run `agentchrome form submit --help`
**Then** the exit code is 0
**And** stdout contains "TARGET"
**And** stdout contains "--include-snapshot"

### AC10: Submit without required target argument

**Given** agentchrome is built
**When** I run `agentchrome form submit`
**Then** the exit code is nonzero
**And** stderr contains usage information about the required target argument

### AC11: Form help lists submit subcommand

**Given** agentchrome is built
**When** I run `agentchrome form --help`
**Then** stdout contains "submit"

### Generated Gherkin Preview

```gherkin
Feature: Form submit subcommand
  As an AI agent automating form-based workflows
  I want a form submit subcommand to programmatically submit a form
  So that I can trigger form submission without needing to locate and click a submit button

  Scenario: Submit form by UID targeting the form element
    Given Chrome is running with a page containing a form element with UID "s3"
    And an accessibility snapshot has been taken
    When I run "agentchrome form submit s3"
    Then the exit code should be 0
    And the output JSON "submitted" should be "s3"

  Scenario: Submit form by CSS selector
    Given Chrome is running with a page containing a form with id "login-form"
    When I run "agentchrome form submit css:#login-form"
    Then the exit code should be 0
    And the output JSON "submitted" should be "css:#login-form"

  Scenario: Submit element inside a form resolves parent form
    Given Chrome is running with a page containing an input inside a form
    When I run "agentchrome form submit <INPUT_UID>"
    Then the exit code should be 0
    And the output JSON "submitted" should be "<INPUT_UID>"

  Scenario: Submit triggers navigation when form has action URL
    Given Chrome is running with a form that has an action URL
    When I run "agentchrome form submit <TARGET>"
    Then the output JSON should contain "url"

  Scenario: Error when target is not a form or inside a form
    Given Chrome is running with an element not in a form
    When I run "agentchrome form submit <TARGET>"
    Then the exit code should be nonzero
    And stderr should contain "no form found"
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | `form submit <TARGET>` accepts a UID or CSS selector targeting a form element or element within a form | Must | Core targeting, consistent with existing form subcommands |
| FR2 | The command dispatches the form's `submit` event via CDP | Must | Uses `Runtime.callFunctionOn` to call `form.submit()` or dispatch submit event |
| FR3 | If the target is inside a form (not the form itself), the parent form is resolved and submitted | Must | Walk up DOM to find enclosing `<form>` |
| FR4 | JSON output includes `submitted` key with the target identifier | Must | Consistent with `filled`/`cleared` pattern |
| FR5 | If form submission triggers navigation, output includes the new `url` | Should | Matches AC4 |
| FR6 | `--include-snapshot` option returns updated accessibility snapshot | Could | Consistent with other form subcommands |
| FR7 | Error with clear message when target is not in a form | Must | Non-zero exit code, JSON error on stderr |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Submit operation should complete in < 500ms (excluding navigation wait) |
| **Reliability** | Submit must dispatch via the standard browser mechanism so validation and event handlers fire |
| **Platforms** | macOS, Linux, Windows (all platforms Chrome supports) |
| **Error handling** | Clear JSON error messages for invalid UIDs, selectors, or elements not in a form |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| target | String | Must be valid UID format (s\d+) or css: prefix | Yes |
| --include-snapshot | Flag | Boolean flag | No |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| submitted | String | Target identifier that was submitted |
| url | String (optional) | New URL if navigation occurred after submission |
| snapshot | Object (optional) | Accessibility tree if --include-snapshot |

---

## Dependencies

### Internal Dependencies
- [x] #4 — CDP client (WebSocket communication)
- [x] #6 — Session management (connection resolution)
- [x] #10 — UID system (accessibility snapshot UIDs)
- [x] #16 — Form module (existing form command infrastructure)

### External Dependencies
- Chrome/Chromium with CDP enabled

---

## Out of Scope

- Form validation bypass (submit should respect browser validation)
- Multi-form batch submission
- Changes to existing `form fill`, `form clear`, or `form upload`
- Custom submit event data or headers
- Intercepting or modifying the form submission request

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Command execution | < 500ms | Timing from invocation to JSON output (excluding navigation) |
| Agent ergonomics | Single command replaces multi-step workaround | Compared to `interact click` or `interact key Enter` |

---

## Open Questions

None — all requirements are clear from the issue specification.

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
- [x] Edge cases and error states specified
- [x] Dependencies identified
- [x] Out of scope defined
