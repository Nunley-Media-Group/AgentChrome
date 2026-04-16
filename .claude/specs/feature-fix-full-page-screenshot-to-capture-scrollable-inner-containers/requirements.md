# Requirements: Fix Full-Page Screenshot for Scrollable Inner Containers

**Issues**: #184
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude

---

## User Story

**As a** developer or AI agent taking screenshots of pages with scrollable inner containers
**I want** `page screenshot --full-page` to capture the full scrollable content of inner containers
**So that** I get a complete visual record of the page, not just the viewport, even when the page uses inner scrollable regions instead of document-level scrolling

---

## Background

The `page screenshot --full-page` command currently determines the full page size by reading `document.documentElement.scrollWidth` and `scrollHeight`, then expands the viewport to those dimensions before capture. This works well for standard pages where the document body is the scrollable element. However, many modern web applications (e.g., Salesforce Lightning, Gmail, Slack) set `overflow: hidden` on the body element and contain all scrollable content inside an inner container (such as a `<div class="main-content">` with `overflow: auto`). In these cases, `documentElement.scrollHeight` equals the viewport height, so `--full-page` produces a screenshot identical to a normal viewport capture — the inner container's overflowed content is never captured.

This feature adds a `--scroll-container` flag that lets the user specify which element's scroll dimensions should drive the full-page capture, and adds auto-detection logic that warns when full-page dimensions appear identical to the viewport.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Capture inner scrollable content with --scroll-container

**Given** a page where the scrollable content is inside an inner container (e.g., `overflow: auto` on `.main-content`) and `document.documentElement.scrollHeight` equals the viewport height
**When** I run `agentchrome page screenshot --full-page --scroll-container ".main-content"`
**Then** the screenshot captures the full scrollable content of that container
**And** the output JSON `height` is greater than the viewport height
**And** the output JSON contains `format`, `data` (or `file`), `width`, and `height` fields

**Example**:
- Given: A page with `body { overflow: hidden }` and `.main-content { overflow: auto; height: 100vh }` containing 3000px of content
- When: `agentchrome page screenshot --full-page --scroll-container ".main-content" --file /tmp/inner.png`
- Then: The screenshot file is created, JSON `height` is ~3000, and the image shows all inner content

### AC2: Default full-page behavior unchanged

**Given** a standard page where the document body is the scrollable element (no inner scrollable container)
**When** I run `agentchrome page screenshot --full-page`
**Then** the screenshot captures the full page content as it does today
**And** the `height` in the output reflects the full `document.documentElement.scrollHeight`

**Example**:
- Given: A page with 5000px of body content, no `overflow: hidden` on body
- When: `agentchrome page screenshot --full-page --file /tmp/full.png`
- Then: The screenshot height is ~5000 and captures all body content

### AC3: Auto-detect warning when full-page dimensions match viewport

**Given** a page where `document.documentElement.scrollHeight` is equal to the viewport height (indicating possible inner scrollable container)
**When** I run `agentchrome page screenshot --full-page`
**Then** stderr contains a warning message indicating the full-page capture may be incomplete
**And** the warning suggests using `--scroll-container` to target a specific scrollable element
**And** the screenshot is still captured successfully (no error exit code)

**Example**:
- Given: A page with `body { overflow: hidden }` and inner scrollable content
- When: `agentchrome page screenshot --full-page`
- Then: stderr shows `warning: full-page dimensions match viewport. Content may be inside a scrollable container. Use --scroll-container <selector> to capture it.`
- And: Exit code is 0, screenshot is captured at viewport size

### AC4: Invalid scroll container selector

**Given** a page is loaded
**When** I run `agentchrome page screenshot --full-page --scroll-container ".nonexistent"`
**Then** the command exits with a non-zero exit code
**And** stderr contains a JSON error indicating the element was not found

**Example**:
- Given: A page with no element matching `.nonexistent`
- When: `agentchrome page screenshot --full-page --scroll-container ".nonexistent"`
- Then: stderr JSON contains `"Element not found for selector: .nonexistent"`, exit code is non-zero

### AC5: --scroll-container requires --full-page

**Given** a page is loaded
**When** I run `agentchrome page screenshot --scroll-container ".main-content"` (without `--full-page`)
**Then** the command exits with a non-zero exit code
**And** stderr contains a JSON error indicating that `--scroll-container` requires `--full-page`

### AC6: --scroll-container conflicts with element targeting flags

**Given** a page is loaded
**When** I run `agentchrome page screenshot --full-page --scroll-container ".main-content" --selector "#logo"`
**Then** the command exits with a non-zero exit code
**And** stderr contains a JSON error indicating conflicting flags

**Example**:
- Also applies to `--uid` and `--clip` combined with `--scroll-container`

### AC7: Viewport restored after scroll-container capture

**Given** the viewport is at its default dimensions (e.g., 1280x720)
**When** I run `agentchrome page screenshot --full-page --scroll-container ".main-content"`
**And** the screenshot is captured successfully
**Then** the viewport is restored to its original dimensions after the command completes
**And** a subsequent `page screenshot` (without `--full-page`) produces a viewport-sized screenshot matching the original dimensions

### Generated Gherkin Preview

```gherkin
Feature: Full-page screenshot with scrollable inner containers
  As a developer or AI agent
  I want full-page screenshots to capture inner scrollable content
  So that I get a complete visual record even with inner scroll containers

  Scenario: Capture inner scrollable content with --scroll-container
    Given a page with scrollable content inside ".main-content"
    When I run page screenshot with --full-page and --scroll-container ".main-content"
    Then the screenshot height is greater than the viewport height
    And the output JSON contains format, data, width, and height fields

  Scenario: Default full-page behavior unchanged
    Given a standard page with document-level scrolling
    When I run page screenshot with --full-page
    Then the screenshot captures the full document scroll height

  Scenario: Auto-detect warning when dimensions match viewport
    Given a page with inner scrollable content and body overflow hidden
    When I run page screenshot with --full-page
    Then stderr contains a warning about incomplete capture
    And the screenshot is still captured successfully

  Scenario: Invalid scroll container selector
    Given a page with no element matching ".nonexistent"
    When I run page screenshot with --full-page and --scroll-container ".nonexistent"
    Then the command fails with element not found error

  Scenario: --scroll-container requires --full-page
    When I run page screenshot with --scroll-container but without --full-page
    Then the command fails with a requires --full-page error

  Scenario: --scroll-container conflicts with element targeting
    When I run page screenshot with --full-page --scroll-container and --selector
    Then the command fails with a conflicting flags error

  Scenario: Viewport restored after scroll-container capture
    Given the viewport is at default dimensions
    When I run page screenshot with --full-page and --scroll-container
    Then the viewport is restored after capture
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Add `--scroll-container` flag accepting a CSS selector to specify the scrollable element whose dimensions drive full-page capture | Must | New CLI argument on `page screenshot` |
| FR2 | When `--scroll-container` is specified with `--full-page`, use that element's `scrollWidth`/`scrollHeight` for the capture dimensions instead of `document.documentElement` | Must | Core behavioral change |
| FR3 | When `--scroll-container` is specified, temporarily modify the target element's CSS (and its ancestors up to the document) to make overflow content visible before capture, then restore | Must | Required for CDP compositor capture to see the content |
| FR4 | Emit a warning to stderr when `--full-page` dimensions equal the viewport dimensions, suggesting `--scroll-container` | Must | Auto-detection of potential inner scroll containers |
| FR5 | `--scroll-container` requires `--full-page` — error if used without it | Must | Validation |
| FR6 | `--scroll-container` conflicts with `--selector`, `--uid`, and `--clip` — error if combined | Must | Validation |
| FR7 | Restore viewport dimensions and element styles after scroll-container capture completes or fails | Must | State cleanup |
| FR8 | JSON output structure is unchanged — same `format`, `data`/`file`, `width`, `height` fields | Must | Backward compatibility |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Auto-detection adds at most one additional `Runtime.evaluate` call; no measurable latency increase for non-full-page captures |
| **Reliability** | Style and viewport restoration must occur even if the capture step fails (cleanup in all paths) |
| **Platforms** | macOS, Linux, Windows — all platforms supported by agentchrome |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `--scroll-container` | String (CSS selector) | Must be a valid CSS selector; the element must exist on the page | No (optional, requires `--full-page`) |
| `--full-page` | Boolean flag | N/A | No (but required when `--scroll-container` is used) |

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| `format` | String | Image format (`png`, `jpeg`, `webp`) — unchanged |
| `data` | String | Base64-encoded image data (when no `--file`) — unchanged |
| `file` | String | File path (when `--file` is used) — unchanged |
| `width` | u32 | Image width in pixels — reflects container scroll width when `--scroll-container` used |
| `height` | u32 | Image height in pixels — reflects container scroll height when `--scroll-container` used |

---

## Dependencies

### Internal Dependencies
- [x] Screenshot capture (Issue #12) — existing `page screenshot` command
- [x] CDP client and session management (Issue #6)
- [x] DOM querying via `DOM.querySelector` — already used by `--selector`

### External Dependencies
- [x] Chrome DevTools Protocol — `Page.captureScreenshot`, `Emulation.setDeviceMetricsOverride`, `Runtime.evaluate`

### Blocked By
- None

---

## Out of Scope

- Stitching multiple screenshots from scrolling (compositor-based approach only)
- Capturing content from multiple scrollable containers in one shot
- Recursive auto-detection of deeply nested scrollable containers
- Shadow DOM scrollable containers (standard CSS selectors cannot reach shadow roots)
- Automatic scrolling-based capture (e.g., scroll + stitch approach)

---

## Open Questions

- None

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #184 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Edge cases and error states are specified
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
