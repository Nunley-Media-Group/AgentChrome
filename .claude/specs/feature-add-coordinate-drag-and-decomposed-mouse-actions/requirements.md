# Requirements: Coordinate-based Drag and Decomposed Mouse Actions

**Issues**: #194
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude (writing-specs)

---

## User Story

**As a** browser automation engineer working with drag-and-drop interfaces
**I want** coordinate-based drag commands and decomposed mouse actions (mousedown/mouseup)
**So that** I can automate drag-and-drop, long-press, and multi-step mouse interactions that cannot be expressed with the current atomic commands

---

## Background

The current `interact drag` command only accepts UIDs from `page snapshot` or CSS selectors, making it impossible to drag elements that are inside iframes (invisible to `page snapshot`) or that lack stable selectors. Additionally, complex interaction patterns like long-press, hover-then-click, and custom drag sequences require decomposed mouse events that the current atomic `click-at` cannot express. Users automating Storyline classification games and similar drag-and-drop interfaces are blocked by these limitations.

The existing `interact click-at X Y` command demonstrates the coordinate-based pattern using `Input.dispatchMouseEvent` (src/interact.rs), and `interact drag` already uses a 3-event sequence (press → move → release) but only accepts element targets. This feature adds `drag-at` (coordinate-based drag), `mousedown-at` (decomposed press), and `mouseup-at` (decomposed release) subcommands that follow the same CDP dispatch patterns.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Coordinate-based drag

**Given** source coordinates (100, 200) and target coordinates (300, 400)
**When** `interact drag-at 100 200 300 400` is run
**Then** a full drag sequence (mousedown at source, mousemove to target, mouseup at target) is dispatched at those viewport coordinates
**And** JSON output is returned: `{"dragged_at": {"from": {"x": 100, "y": 200}, "to": {"x": 300, "y": 400}}}`
**And** the exit code is 0

### AC2: Decomposed mousedown

**Given** coordinates (150, 250)
**When** `interact mousedown-at 150 250` is run
**Then** only a mousePressed event is dispatched (no automatic mouseup)
**And** JSON output is returned: `{"mousedown_at": {"x": 150, "y": 250}}`
**And** the exit code is 0

### AC3: Decomposed mouseup

**Given** coordinates (300, 400)
**When** `interact mouseup-at 300 400` is run
**Then** only a mouseReleased event is dispatched
**And** JSON output is returned: `{"mouseup_at": {"x": 300, "y": 400}}`
**And** the exit code is 0

### AC4: Decomposed multi-invocation drag sequence

**Given** a page with a draggable element at (100, 200) and a drop target at (300, 400)
**When** `interact mousedown-at 100 200` is run in one invocation
**And** `interact mouseup-at 300 400` is run in a subsequent invocation
**Then** the second invocation dispatches a mouseReleased event at (300, 400)
**And** each invocation exits with code 0 independently

**Example**:
- Given: a canvas-based drag interface
- When: `agentchrome interact mousedown-at 100 200` (press)
- Then: `{"mousedown_at": {"x": 100, "y": 200}}`
- When: `agentchrome interact mouseup-at 300 400` (release)
- Then: `{"mouseup_at": {"x": 300, "y": 400}}`

### AC5: Frame-scoped dispatch for drag-at

**Given** `--frame 1` argument and coordinates
**When** `interact --frame 1 drag-at 50 60 200 300` is run
**Then** events are dispatched within the specified frame context with coordinates translated by the frame's viewport offset
**And** the exit code is 0

### AC6: Frame-scoped dispatch for mousedown-at

**Given** `--frame 1` argument and coordinates
**When** `interact --frame 1 mousedown-at 50 60` is run
**Then** the mousePressed event is dispatched within the specified frame context with translated coordinates
**And** the exit code is 0

### AC7: Frame-scoped dispatch for mouseup-at

**Given** `--frame 1` argument and coordinates
**When** `interact --frame 1 mouseup-at 50 60` is run
**Then** the mouseReleased event is dispatched within the specified frame context with translated coordinates
**And** the exit code is 0

### AC8: Optional drag steps for interpolated movement

**Given** `--steps 5` argument
**When** `interact drag-at 0 0 100 100 --steps 5` is run
**Then** the mousemove is interpolated across 5 intermediate points between source and target (e.g., (20,20), (40,40), (60,60), (80,80), (100,100))
**And** the JSON output includes `"steps": 5`
**And** the exit code is 0

### AC9: Drag-at default single-step movement

**Given** no `--steps` argument
**When** `interact drag-at 0 0 100 100` is run
**Then** a single mousemove from source to target is dispatched (equivalent to `--steps 1`)
**And** the exit code is 0

### AC10: Button option on mousedown-at

**Given** `--button right` argument
**When** `interact mousedown-at 100 200 --button right` is run
**Then** a right-button mousePressed event is dispatched
**And** JSON output includes `"button": "right"`

### AC11: Button option on mouseup-at

**Given** `--button right` argument
**When** `interact mouseup-at 100 200 --button right` is run
**Then** a right-button mouseReleased event is dispatched
**And** JSON output includes `"button": "right"`

### AC12: Plain text output for drag-at

**Given** a page is loaded
**When** `interact drag-at 100 200 300 400 --plain` is run (via global --plain flag)
**Then** plain text output is returned: `Dragged from (100, 200) to (300, 400)`

### AC13: Plain text output for mousedown-at

**Given** a page is loaded
**When** `interact mousedown-at 100 200 --plain` is run
**Then** plain text output is returned: `Mousedown at (100, 200)`

### AC14: Plain text output for mouseup-at

**Given** a page is loaded
**When** `interact mouseup-at 100 200 --plain` is run
**Then** plain text output is returned: `Mouseup at (100, 200)`

### AC15: Include-snapshot on drag-at

**Given** a page is loaded
**When** `interact drag-at 100 200 300 400 --include-snapshot` is run
**Then** the JSON output includes an updated accessibility snapshot in the `snapshot` field

### AC16: Include-snapshot on mousedown-at

**Given** a page is loaded
**When** `interact mousedown-at 100 200 --include-snapshot` is run
**Then** the JSON output includes an updated accessibility snapshot in the `snapshot` field

### AC17: Include-snapshot on mouseup-at

**Given** a page is loaded
**When** `interact mouseup-at 100 200 --include-snapshot` is run
**Then** the JSON output includes an updated accessibility snapshot in the `snapshot` field

### AC18: Documentation updated

**Given** the new interact commands
**When** `examples interact` is run
**Then** `drag-at`, `mousedown-at`, and `mouseup-at` examples are included in the output

### Generated Gherkin Preview

```gherkin
Feature: Coordinate-based Drag and Decomposed Mouse Actions
  As a browser automation engineer
  I want coordinate-based drag and decomposed mouse actions
  So that I can automate drag-and-drop, long-press, and multi-step mouse interactions

  Background:
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements

  Scenario: Coordinate-based drag
    When I run "agentchrome interact drag-at 100 200 300 400"
    Then the output JSON "dragged_at.from.x" should be 100
    And the output JSON "dragged_at.from.y" should be 200
    And the output JSON "dragged_at.to.x" should be 300
    And the output JSON "dragged_at.to.y" should be 400
    And the exit code should be 0

  Scenario: Decomposed mousedown
    When I run "agentchrome interact mousedown-at 150 250"
    Then the output JSON "mousedown_at.x" should be 150
    And the output JSON "mousedown_at.y" should be 250
    And the exit code should be 0

  Scenario: Decomposed mouseup
    When I run "agentchrome interact mouseup-at 300 400"
    Then the output JSON "mouseup_at.x" should be 300
    And the output JSON "mouseup_at.y" should be 400
    And the exit code should be 0

  Scenario: Decomposed multi-invocation drag sequence
    When I run "agentchrome interact mousedown-at 100 200"
    Then the exit code should be 0
    When I run "agentchrome interact mouseup-at 300 400"
    Then the exit code should be 0

  Scenario: Frame-scoped drag-at
    When I run "agentchrome interact --frame 1 drag-at 50 60 200 300"
    Then the exit code should be 0

  Scenario: Frame-scoped mousedown-at
    When I run "agentchrome interact --frame 1 mousedown-at 50 60"
    Then the exit code should be 0

  Scenario: Frame-scoped mouseup-at
    When I run "agentchrome interact --frame 1 mouseup-at 50 60"
    Then the exit code should be 0

  Scenario: Interpolated drag steps
    When I run "agentchrome interact drag-at 0 0 100 100 --steps 5"
    Then the output JSON "steps" should be 5
    And the exit code should be 0

  Scenario: Default single-step drag
    When I run "agentchrome interact drag-at 0 0 100 100"
    Then the exit code should be 0

  Scenario: Right-button mousedown
    When I run "agentchrome interact mousedown-at 100 200 --button right"
    Then the output JSON "button" should be "right"

  Scenario: Right-button mouseup
    When I run "agentchrome interact mouseup-at 100 200 --button right"
    Then the output JSON "button" should be "right"

  Scenario: Plain text output for drag-at
    When I run "agentchrome interact drag-at 100 200 300 400" with --plain
    Then the output should be "Dragged from (100, 200) to (300, 400)"

  Scenario: Plain text output for mousedown-at
    When I run "agentchrome interact mousedown-at 100 200" with --plain
    Then the output should be "Mousedown at (100, 200)"

  Scenario: Plain text output for mouseup-at
    When I run "agentchrome interact mouseup-at 100 200" with --plain
    Then the output should be "Mouseup at (100, 200)"

  Scenario: Include-snapshot on drag-at
    When I run "agentchrome interact drag-at 100 200 300 400 --include-snapshot"
    Then the output JSON should contain a "snapshot" field

  Scenario: Include-snapshot on mousedown-at
    When I run "agentchrome interact mousedown-at 100 200 --include-snapshot"
    Then the output JSON should contain a "snapshot" field

  Scenario: Include-snapshot on mouseup-at
    When I run "agentchrome interact mouseup-at 100 200 --include-snapshot"
    Then the output JSON should contain a "snapshot" field

  Scenario: Examples include new commands
    When I run "agentchrome examples interact"
    Then the output should contain "drag-at"
    And the output should contain "mousedown-at"
    And the output should contain "mouseup-at"
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | `interact drag-at <fromX> <fromY> <toX> <toY>` subcommand dispatches a full drag sequence at viewport coordinates | Must | Reuses 3-event CDP pattern from `dispatch_drag` |
| FR2 | `interact mousedown-at <X> <Y>` subcommand dispatches only a mousePressed event | Must | No automatic mouseup |
| FR3 | `interact mouseup-at <X> <Y>` subcommand dispatches only a mouseReleased event | Must | No automatic mousedown |
| FR4 | `--steps <N>` flag on `drag-at` interpolates mousemove across N intermediate points | Should | Linear interpolation between source and target |
| FR5 | `--frame` support on all three new commands via existing `InteractArgs.frame` | Should | Same frame resolution as `click-at` |
| FR6 | `--button` option (left/middle/right) on `mousedown-at` and `mouseup-at` | Could | Default: left |
| FR7 | `--include-snapshot` and `--compact` flags on all three new commands | Must | Consistent with existing interact commands |
| FR8 | JSON, pretty-JSON, and plain text output formats for all three commands | Must | Consistent with all other commands |
| FR9 | Help documentation and built-in examples updated in `examples.rs` | Must | |
| FR10 | BDD test scenarios covering all new commands | Must | |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Coordinate-based commands should complete within the command timeout (default 30s); CDP event dispatch < 100ms per event |
| **Reliability** | Frame offset calculation must handle missing frames gracefully (return error, not panic) |
| **Error handling** | Clear JSON error on stderr for: invalid frame index, CDP dispatch failure. No argument name collisions with existing global flags |
| **Platforms** | macOS, Linux, Windows (consistent with all other commands) |

---

## UI/UX Requirements

Reference `structure.md` and `product.md` for project-specific design standards.

| Element | Requirement |
|---------|-------------|
| **Interaction** | N/A (CLI tool — no GUI) |
| **Typography** | N/A |
| **Contrast** | N/A |
| **Loading States** | N/A |
| **Error States** | JSON error on stderr with structured `{"error": "...", "code": N}` format |
| **Empty States** | N/A |

---

## Data Requirements

### Input Data — `interact drag-at`

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| fromX | f64 | Finite number | Yes |
| fromY | f64 | Finite number | Yes |
| toX | f64 | Finite number | Yes |
| toY | f64 | Finite number | Yes |
| --steps | u32 | Positive integer >= 1 | No (default: 1) |
| --include-snapshot | Boolean flag | N/A | No |
| --compact | Boolean flag | N/A | No |

### Input Data — `interact mousedown-at`

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| x | f64 | Finite number | Yes |
| y | f64 | Finite number | Yes |
| --button | String enum | left, middle, right | No (default: left) |
| --include-snapshot | Boolean flag | N/A | No |
| --compact | Boolean flag | N/A | No |

### Input Data — `interact mouseup-at`

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| x | f64 | Finite number | Yes |
| y | f64 | Finite number | Yes |
| --button | String enum | left, middle, right | No (default: left) |
| --include-snapshot | Boolean flag | N/A | No |
| --compact | Boolean flag | N/A | No |

### Output Data — `interact drag-at`

| Field | Type | Description |
|-------|------|-------------|
| dragged_at | Object | `{"from": {"x": N, "y": N}, "to": {"x": N, "y": N}}` with the drag coordinates |
| steps | u32 (optional) | Present when `--steps` was provided and > 1 |
| snapshot | Object (optional) | Updated accessibility snapshot (when `--include-snapshot`) |

### Output Data — `interact mousedown-at`

| Field | Type | Description |
|-------|------|-------------|
| mousedown_at | Object | `{"x": N, "y": N}` with the mousedown coordinates |
| button | String (optional) | Present when `--button` was provided and not "left" |
| snapshot | Object (optional) | Updated accessibility snapshot (when `--include-snapshot`) |

### Output Data — `interact mouseup-at`

| Field | Type | Description |
|-------|------|-------------|
| mouseup_at | Object | `{"x": N, "y": N}` with the mouseup coordinates |
| button | String (optional) | Present when `--button` was provided and not "left" |
| snapshot | Object (optional) | Updated accessibility snapshot (when `--include-snapshot`) |

---

## Dependencies

### Internal Dependencies
- [x] CDP client (`src/cdp/`) — WebSocket communication, `Input.dispatchMouseEvent`
- [x] Connection resolution (`src/connection.rs`) — target selection, session management
- [x] Frame support (`src/frame.rs`, `get_frame_viewport_offset` in `src/interact.rs`) — frame-scoped coordinate translation
- [x] Output formatting (`src/output.rs`) — JSON/pretty/plain output patterns
- [x] Snapshot system (`src/snapshot.rs`) — for `--include-snapshot` support

### External Dependencies
- [x] Chrome DevTools Protocol — `Input.dispatchMouseEvent` (mousePressed, mouseMoved, mouseReleased)

### Blocked By
- None — all infrastructure is in place

---

## Out of Scope

- Touch/gesture events (pinch, swipe)
- Drag-and-drop file upload (use `form upload`)
- HTML5 drag-and-drop API events (dragstart, dragover, drop) — this is mouse-level dispatch
- `--button` on `drag-at` (drag is always left-button)
- Bezier/curved interpolation for `--steps` (linear interpolation only)
- Mouse move without press/release semantics (raw mouseMoved) — use `interact hover` for that

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| All new commands work | 3/3 (drag-at, mousedown-at, mouseup-at) | BDD tests pass |
| Frame-scoped dispatch | Coordinates translated correctly for all 3 commands | BDD tests with frame scenarios |
| Interpolated drag | N intermediate mousemove events dispatched | BDD test with `--steps` flag |
| Response time | < 200ms for coordinate-based commands (no element resolution needed) | Manual timing |

---

## Open Questions

- (None — all requirements are clear from the issue and CDP documentation)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #194 | 2026-04-16 | Initial feature spec |

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
