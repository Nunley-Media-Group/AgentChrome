# Requirements: Add --wait-until Flag to Interact Click Commands

**Issues**: #148
**Date**: 2026-02-26
**Status**: Draft
**Author**: Claude

---

## User Story

**As a** AI agent or automation engineer
**I want** to wait for page content to settle after clicking an element that triggers SPA navigation
**So that** I can reliably read the updated page content without race conditions or arbitrary sleeps

---

## Background

When automating Single Page Applications (SPAs) like React or Vue apps, clicking a navigation link triggers a `history.pushState()` instead of a full page load. The current `interact click` and `interact click-at` commands return immediately after the click with a 100ms grace period that only checks for `Page.frameNavigated` — an event that never fires for same-document SPA navigations.

This leaves agents with no reliable way to know when the SPA transition is complete. The `navigate` command already supports `--wait-until` with options like `load`, `domcontentloaded`, and `networkidle`, but the `interact click` commands have no equivalent. Agents must resort to arbitrary `sleep` calls followed by snapshot polling, which is fragile and slow.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Click with wait-until networkidle — Happy Path

**Given** a connected Chrome session on an SPA page
**When** I run `agentchrome interact click <target> --wait-until networkidle`
**Then** the command waits for network activity to settle (no requests for 500ms) before returning the result with the updated URL

**Example**:
- Given: Chrome connected, page loaded at `https://spa-app.example.com/`
- When: `agentchrome interact click s12 --wait-until networkidle` (s12 is an SPA nav link)
- Then: Command returns JSON with `navigated: true` and the updated URL after network idle

### AC2: Click with wait-until load — Full-page navigation

**Given** a connected Chrome session on a page with a link to a different origin
**When** I run `agentchrome interact click <target> --wait-until load`
**Then** the command waits for the `load` event after the full-page navigation completes before returning

**Example**:
- Given: Chrome connected, page with an external link
- When: `agentchrome interact click s5 --wait-until load`
- Then: Command returns JSON with `navigated: true` after the load event fires on the new page

### AC3: Click-at with wait-until — Coordinate-based click

**Given** a connected Chrome session on an SPA page
**When** I run `agentchrome interact click-at <x> <y> --wait-until networkidle`
**Then** the command waits for network idle before returning, same as `interact click`

**Example**:
- Given: Chrome connected, SPA page loaded
- When: `agentchrome interact click-at 150 300 --wait-until networkidle`
- Then: Command returns JSON with click result after network activity settles

### AC4: Click with no wait-until — Backward compatibility

**Given** a connected Chrome session
**When** I run `agentchrome interact click <target>` without `--wait-until`
**Then** the command behaves exactly as it does today (100ms grace period, non-blocking navigation check)

**Example**:
- Given: Chrome connected, any page loaded
- When: `agentchrome interact click s5` (no --wait-until flag)
- Then: Command returns after 100ms grace period with navigation detection via `try_recv()`

### AC5: Click with wait-until timeout — Error handling

**Given** a connected Chrome session on a page where a click triggers continuous network activity
**When** I run `agentchrome interact click <target> --wait-until networkidle` and the network never settles within the timeout
**Then** the command exits with a timeout error (exit code 4) and a descriptive error message

**Example**:
- Given: Chrome connected, page with a click target that triggers infinite polling
- When: `agentchrome interact click s5 --wait-until networkidle --timeout 3000`
- Then: Command exits with code 4, stderr contains `{"error": "Timed out waiting for network idle after click", ...}`

### AC6: Cross-command state visibility after wait

**Given** a click with `--wait-until networkidle` has completed on an SPA page
**When** a subsequent `page snapshot` command is executed
**Then** the snapshot reflects the post-navigation page content, not stale pre-click content

**Example**:
- Given: `agentchrome interact click s12 --wait-until networkidle` returned successfully after SPA navigation
- When: `agentchrome page snapshot`
- Then: The accessibility tree contains elements from the new SPA route, not the previous page

### Generated Gherkin Preview

```gherkin
Feature: Wait-until flag for interact click commands
  As a AI agent or automation engineer
  I want to wait for page content to settle after clicking
  So that I can reliably read the updated page content

  Scenario: Click with wait-until networkidle on SPA page
    Given a Chrome session connected to an SPA page
    When I run interact click with --wait-until networkidle
    Then the command waits for network idle before returning

  Scenario: Click with wait-until load on full-page navigation
    Given a Chrome session connected to a page with external links
    When I run interact click with --wait-until load
    Then the command waits for the load event before returning

  Scenario: Click-at with wait-until networkidle
    Given a Chrome session connected to an SPA page
    When I run interact click-at with --wait-until networkidle
    Then the command waits for network idle before returning

  Scenario: Click without wait-until preserves existing behavior
    Given a Chrome session connected to any page
    When I run interact click without --wait-until
    Then the command uses the 100ms grace period

  Scenario: Click with wait-until times out
    Given a Chrome session on a page with continuous network activity
    When I run interact click with --wait-until networkidle and the timeout elapses
    Then the command exits with code 4 and a timeout error message

  Scenario: Page state is visible to subsequent commands after wait
    Given a click with --wait-until networkidle completed on an SPA page
    When I run page snapshot
    Then the snapshot reflects the post-navigation content
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Add `--wait-until` flag to `interact click` accepting the existing `WaitUntil` enum values (`load`, `domcontentloaded`, `networkidle`, `none`) | Must | Reuses `WaitUntil` from `cli/mod.rs` |
| FR2 | Add `--wait-until` flag to `interact click-at` with identical behavior | Must | Same enum, same wait logic |
| FR3 | Default behavior when `--wait-until` is not provided must remain unchanged (100ms grace period for click, no navigation check for click-at) | Must | Backward compatibility |
| FR4 | Reuse existing `wait_for_network_idle()` and `wait_for_event()` helpers from `navigate.rs` | Should | Avoid duplicating wait logic |
| FR5 | Respect the global `--timeout` flag when waiting | Should | Uses existing timeout infrastructure |
| FR6 | JSON output structure is preserved when `--wait-until` is used | Must | Same fields as current click output |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | No additional overhead when `--wait-until` is not provided; wait strategies add only the time needed for the page to settle |
| **Reliability** | Network idle detection must handle both SPA pushState transitions and full-page navigations |
| **Platforms** | Works on macOS, Linux, and Windows (same as existing click commands) |
| **Compatibility** | Existing scripts using `interact click` without `--wait-until` must continue to work identically |

---

## UI/UX Requirements

| Element | Requirement |
|---------|-------------|
| **CLI flag** | `--wait-until <strategy>` with value enum: `load`, `domcontentloaded`, `networkidle`, `none` |
| **Help text** | Flag description explains SPA-aware waiting behavior |
| **Error messages** | Timeout errors include the wait strategy name and elapsed time in the JSON error object |
| **Exit codes** | Timeout exits with code 4 (consistent with existing timeout behavior) |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `--wait-until` | `WaitUntil` enum | Must be one of: `load`, `domcontentloaded`, `networkidle`, `none` | No (optional flag) |
| `target` (click) | String | Accessibility UID or CSS selector | Yes (positional) |
| `x`, `y` (click-at) | f64 | Valid numeric coordinates | Yes (positional) |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| `x` | f64 | X coordinate of click |
| `y` | f64 | Y coordinate of click |
| `navigated` | bool | Whether navigation was detected |
| `url` | String | Current page URL after click (and wait, if applicable) |
| `snapshot` | Object | Optional accessibility tree snapshot (if `--include-snapshot`) |

---

## Dependencies

### Internal Dependencies
- [x] `WaitUntil` enum already defined in `src/cli/mod.rs`
- [x] `wait_for_network_idle()` helper already implemented in `src/navigate.rs`
- [x] `wait_for_event()` helper already implemented in `src/navigate.rs`

### External Dependencies
- [x] Chrome DevTools Protocol events: `Network.requestWillBeSent`, `Network.loadingFinished`, `Network.loadingFailed`, `Page.loadEventFired`, `Page.domContentEventFired`

### Blocked By
- None

---

## Out of Scope

- Adding `--wait-until` to other interact subcommands (hover, scroll, key, type, drag)
- SPA-specific navigation detection via `Page.navigatedWithinDocument` — covered by issue #144
- Custom idle thresholds (uses the existing 500ms constant from `navigate.rs`)
- Adding `--wait-until` as a default in configuration files

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Backward compatibility | 0 regressions | All existing interact BDD tests pass without modification |
| Wait accuracy | Network idle detected within 600ms of last request completing | Manual smoke test against SauceDemo SPA |
| Agent reliability | Eliminates need for arbitrary sleeps after SPA clicks | Agent workflows use `--wait-until networkidle` instead of `sleep + poll` |

---

## Open Questions

- None (all questions resolved in issue discussion)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #148 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified (AC5 timeout, AC4 backward compat)
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
