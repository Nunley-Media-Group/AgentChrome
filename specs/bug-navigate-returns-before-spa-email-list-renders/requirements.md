# Defect Report: navigate returns before SPA email list renders (add --wait-for-selector)

**Issue**: #178
**Date**: 2026-03-15
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: specs/feature-url-navigation/

---

## Reproduction

### Steps to Reproduce

1. `agentchrome connect --launch`
2. `agentchrome tabs create "https://outlook.office365.com/mail/"` — initial load succeeds; 8 `[role="option"]` email items visible.
3. Fill search box and submit (opens a search results view or individual email).
4. `agentchrome navigate "https://outlook.office365.com/mail/"` — returns `{"status": 200}` immediately.
5. `document.querySelectorAll('[role="option"]')` returns 0 elements.
6. Waiting 3-4 seconds and rechecking — still 0 elements.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | Windows 11 Enterprise 10.0.26100 |
| **Version / Commit** | 1.12.0 |
| **Browser / Runtime** | Chrome via `agentchrome connect --launch` |
| **Configuration** | Default (no config file) |

### Frequency

Always (on SPA re-navigations where the app shell loads from cache before dynamic content renders).

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | After `agentchrome navigate` returns, the inbox email list should be populated with `[role="option"]` elements, matching the behavior on initial page load. |
| **Actual** | The navigate command returns with `status: 200` as soon as `Page.loadEventFired` fires. The React SPA app shell renders immediately from cache, but the virtualized email list items (`[role="option"]`) are never inserted into the DOM because the SPA's async data fetch + render cycle hasn't completed yet. The folder tree, heading, and filter controls render correctly, but the listbox container is empty. |

### Error Output

```
No error output — the command reports success with {"status": 200}.
The problem is a silent readiness gap: the page is "loaded" per the browser
event, but the user-visible content has not rendered.
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: navigate with --wait-for-selector succeeds for SPA content

**Given** a Chrome session connected to a page
**When** `agentchrome navigate --wait-for-selector '<CSS>' <URL>` is run where the selector matches an element that appears after async rendering
**Then** the command returns only after at least one element matching the CSS selector is present in the DOM
**And** the output JSON includes the final URL, title, and HTTP status

**Example**:
- Given: A Chrome session with Outlook Web open
- When: `agentchrome navigate --wait-for-selector '[role="option"]' "https://outlook.office365.com/mail/"`
- Then: The command blocks until `[role="option"]` elements exist, then returns `{"url": "...", "title": "...", "status": 200}`

### AC2: Default behavior is unchanged when --wait-for-selector is not provided

**Given** a standard page navigation without the `--wait-for-selector` flag
**When** `agentchrome navigate <URL>` is run
**Then** the command behaves identically to the current implementation (resolves on `Page.loadEventFired` by default)
**And** no selector polling occurs

### AC3: Timeout is respected when selector never appears

**Given** a `--wait-for-selector` value that matches no element in the DOM
**When** the navigation timeout elapses (either from `--timeout` or the default 30s)
**Then** the command exits with exit code 4 (timeout)
**And** stderr contains a JSON error with a descriptive message including the selector that was not found

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Add `--wait-for-selector <CSS>` option to the `navigate` command's `NavigateUrlArgs` struct that accepts a CSS selector string | Must |
| FR2 | After the primary wait strategy (`--wait-until`) completes, poll for the selector using `Runtime.evaluate` with `document.querySelector(selector) !== null`, reusing the same pattern as `page/wait.rs:check_selector_condition` | Must |
| FR3 | The selector polling timeout must respect the navigate-level `--timeout` flag (remaining time after the primary wait completes) | Must |
| FR4 | The selector polling interval should be 100ms (matching `page wait --selector` default) | Should |
| FR5 | Document the `--wait-for-selector` flag in the navigate command's help text with an SPA example | Should |

---

## Out of Scope

- Changing the default `--wait-until` strategy from `load`
- Automatic SPA detection heuristics
- Fixes specific to other SPA frameworks — the flag is generic
- Adding `--wait-for-selector` to `navigate back`, `navigate forward`, or `navigate reload`
- Exposing a configurable poll interval for selector polling (hardcoded at 100ms)

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

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #178 | 2026-03-15 | Initial defect spec |
