# Requirements: Scroll Interactions

**Issue**: #17
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude (writing-specs)

---

## User Story

**As a** developer or automation engineer
**I want** to scroll pages and scroll to specific elements via the CLI
**So that** I can interact with content below the fold and automate full-page workflows from scripts

---

## Background

Scrolling is a fundamental browser interaction needed for accessing elements that are not currently visible in the viewport. Many automation workflows require scrolling before interacting with below-the-fold content, and full-page content capture requires scrolling to ensure all elements are rendered. This feature adds a `scroll` subcommand under the existing `interact` command group, following the established patterns for mouse interactions (click, hover, drag).

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Scroll down by default

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll`
**Then** the page scrolls down by one viewport height
**And** the output JSON contains `scrolled.x` and `scrolled.y` with the scroll delta
**And** the output JSON contains `position.x` and `position.y` with the new scroll position
**And** the exit code is 0

### AC2: Scroll in a specified direction

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --direction up`
**Then** the page scrolls up by one viewport height
**And** the output JSON contains the scroll delta and new position

**Example**:
- Given: a tall page scrolled halfway down
- When: `chrome-cli interact scroll --direction up`
- Then: `{"scrolled": {"x": 0, "y": -N}, "position": {"x": 0, "y": M}}`

### AC3: Scroll by a specific pixel amount

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --amount 300`
**Then** the page scrolls down by 300 pixels
**And** the output JSON reflects the 300-pixel scroll delta

### AC4: Scroll to top of page

**Given** Chrome is running with CDP enabled and a page scrolled partway down
**When** I run `chrome-cli interact scroll --to-top`
**Then** the page scroll position is `(0, 0)`
**And** the output JSON shows position `{"x": 0, "y": 0}`

### AC5: Scroll to bottom of page

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --to-bottom`
**Then** the page scroll position is at the maximum vertical scroll offset
**And** the output JSON shows the final position

### AC6: Scroll to a specific element by UID

**Given** Chrome is running with CDP enabled and a snapshot has been taken with UIDs assigned
**And** the page has an element with UID "s5" below the fold
**When** I run `chrome-cli interact scroll --to-element s5`
**Then** the element with UID "s5" is scrolled into the viewport
**And** the output JSON contains the new scroll position

### AC7: Scroll to a specific element by CSS selector

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --to-element "css:#footer"`
**Then** the element matching `#footer` is scrolled into the viewport
**And** the output JSON contains the new scroll position

### AC8: Scroll with smooth behavior

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --smooth`
**Then** the page scrolls with smooth scrolling behavior
**And** the command waits for the smooth scroll to complete before returning

### AC9: Scroll within a specific container by UID

**Given** Chrome is running with CDP enabled and a snapshot has been taken with UIDs assigned
**And** the page has a scrollable container with UID "s3"
**When** I run `chrome-cli interact scroll --container s3 --amount 200`
**Then** the container element scrolls down by 200 pixels (not the page)
**And** the output JSON reflects the container's scroll position

### AC10: Scroll targeting a specific tab

**Given** Chrome is running with CDP enabled and multiple tabs are open
**When** I run `chrome-cli interact scroll --tab 2`
**Then** the scroll is performed on tab 2
**And** the output reflects the scroll position of tab 2

### AC11: Include snapshot after scroll

**Given** Chrome is running with CDP enabled and a page is loaded
**When** I run `chrome-cli interact scroll --include-snapshot`
**Then** the page scrolls and the output JSON includes a `snapshot` field with the accessibility tree

### AC12: Scroll with conflicting flags errors

**Given** chrome-cli is built
**When** I run `chrome-cli interact scroll --to-top --to-bottom`
**Then** the exit code is nonzero
**And** stderr contains an error about conflicting options

### AC13: Scroll to nonexistent UID errors

**Given** Chrome is running with CDP enabled and a snapshot has been taken
**When** I run `chrome-cli interact scroll --to-element s999`
**Then** the exit code is nonzero
**And** the output contains an error that UID "s999" was not found

### AC14: Scroll with horizontal direction

**Given** Chrome is running with CDP enabled and a wide page is loaded
**When** I run `chrome-cli interact scroll --direction right --amount 200`
**Then** the page scrolls right by 200 pixels
**And** the output JSON reflects the horizontal scroll delta and position

### AC15: Scroll subcommand requires no mandatory arguments

**Given** chrome-cli is built
**When** I run `chrome-cli interact scroll`
**Then** the command succeeds with default behavior (scroll down by viewport height)
**And** the exit code is 0

### Generated Gherkin Preview

```gherkin
Feature: Scroll Interactions
  As a developer or automation engineer
  I want to scroll pages and scroll to specific elements via the CLI
  So that I can interact with content below the fold and automate full-page workflows

  Background:
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content

  Scenario: Scroll down by default
    When I run "chrome-cli interact scroll"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

  Scenario: Scroll to top of page
    When I run "chrome-cli interact scroll --to-top"
    Then the output JSON "position.y" should be 0

  Scenario: Scroll to bottom of page
    When I run "chrome-cli interact scroll --to-bottom"
    Then the scroll position should be at the page bottom

  # ... all ACs become scenarios
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | `interact scroll` command with `--direction` (down/up/left/right) | Must | Default: down |
| FR2 | `--amount <PIXELS>` to specify scroll distance | Must | Default: viewport height (vertical) or width (horizontal) |
| FR3 | `--to-top` and `--to-bottom` convenience flags | Must | Conflict with each other and with `--direction`/`--amount` |
| FR4 | `--to-element <UID>` to scroll element into view | Must | Supports UID (s1) and CSS selector (css:...) |
| FR5 | `--tab <ID>` to target a specific tab | Must | Follows existing tab targeting pattern |
| FR6 | `--include-snapshot` flag for post-scroll snapshot | Must | Follows existing snapshot pattern |
| FR7 | JSON output: `{"scrolled": {"x": N, "y": N}, "position": {"x": N, "y": N}}` | Must | |
| FR8 | `--smooth` flag for smooth scrolling | Should | Uses CSS `scroll-behavior: smooth` |
| FR9 | `--container <UID>` for scrolling within a container element | Should | Supports UID and CSS selector |
| FR10 | Plain text output mode | Must | Follows existing `--plain` flag pattern |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Scroll command should complete in < 500ms (excluding smooth scroll wait) |
| **Reliability** | Scroll position reported must match actual browser scroll position |
| **Platforms** | macOS, Linux, Windows (all platforms supported by chrome-cli) |
| **Compatibility** | Works with Chrome/Chromium versions supporting CDP |

---

## UI/UX Requirements

Reference `structure.md` and `product.md` for project-specific design standards.

| Element | Requirement |
|---------|-------------|
| **Interaction** | [Touch targets, gesture requirements] |
| **Typography** | [Minimum text sizes, font requirements] |
| **Contrast** | [Accessibility contrast requirements] |
| **Loading States** | [How loading should be displayed] |
| **Error States** | [How errors should be displayed] |
| **Empty States** | [How empty data should be displayed] |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `--direction` | enum: down, up, left, right | Must be one of the valid values | No (default: down) |
| `--amount` | positive integer (pixels) | Must be > 0 | No (default: viewport dimension) |
| `--to-element` | string (UID or CSS selector) | UID must exist in snapshot; CSS must match an element | No |
| `--to-top` | boolean flag | Conflicts with `--to-bottom`, `--direction`, `--amount`, `--to-element` | No |
| `--to-bottom` | boolean flag | Conflicts with `--to-top`, `--direction`, `--amount`, `--to-element` | No |
| `--smooth` | boolean flag | None | No |
| `--container` | string (UID or CSS selector) | Must reference a scrollable element | No |
| `--tab` | string (tab ID or index) | Must be a valid tab | No |
| `--include-snapshot` | boolean flag | None | No |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| `scrolled.x` | number | Horizontal scroll delta (pixels) |
| `scrolled.y` | number | Vertical scroll delta (pixels) |
| `position.x` | number | New horizontal scroll position |
| `position.y` | number | New vertical scroll position |
| `snapshot` | object (optional) | Accessibility tree snapshot if `--include-snapshot` |

---

## Dependencies

### Internal Dependencies
- [x] Issue #4 — CDP client (implemented)
- [x] Issue #6 — Session management (implemented)
- [x] Issue #10 — UID system (implemented, used by `--to-element`)

### External Dependencies
- Chrome/Chromium with CDP support

### Blocked By
- None (all dependencies resolved)

---

## Out of Scope

- Infinite scroll detection or automation (scrolling until no new content loads)
- Scroll event listener interception
- Scroll-based screenshot stitching (full-page capture)
- Pinch-to-zoom or touch scroll gestures
- Scroll snapping awareness

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| All BDD scenarios pass | 100% | `cargo test --test bdd` |
| Scroll position accuracy | Within 1px of requested amount | Compare requested vs reported position |
| Command latency | < 500ms for non-smooth scroll | Time from invocation to output |

---

## Open Questions

- (none — all resolved from issue context)

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
