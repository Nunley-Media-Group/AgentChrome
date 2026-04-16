# Design: Coordinate-based Drag and Decomposed Mouse Actions

**Issues**: #194
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude (writing-specs)

---

## Overview

This feature adds three new subcommands to the `interact` command group: `drag-at` (coordinate-based drag), `mousedown-at` (decomposed mouse press), and `mouseup-at` (decomposed mouse release). All three follow the existing `click-at` pattern — they accept viewport coordinates, translate them through frame offsets when `--frame` is specified, and dispatch `Input.dispatchMouseEvent` CDP calls.

The implementation touches two files for core logic (`src/cli/mod.rs` for argument definitions, `src/interact.rs` for execution), plus `src/examples.rs` for documentation and `tests/` for BDD coverage. The design reuses existing infrastructure: `get_frame_viewport_offset` for frame translation, `setup_session`/`print_output` for session and output management, and the `dispatch_drag` pattern for the 3-event drag sequence. A new `MouseButton` enum is introduced for the `--button` flag on decomposed commands, and a new `dispatch_drag_interpolated` function handles the `--steps` flag's multi-move behavior.

---

## Architecture

### Component Diagram

Reference `structure.md` for the project's layer architecture.

```
┌──────────────────────────────────────────────────────────────────┐
│                         CLI Layer (cli/mod.rs)                    │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────┐    │
│  │ DragAtArgs   │  │ MouseDownAtArgs  │  │ MouseUpAtArgs    │    │
│  └─────────────┘  └──────────────────┘  └──────────────────┘    │
│  ┌──────────────────┐                                            │
│  │ MouseButton enum │  (left | middle | right)                   │
│  └──────────────────┘                                            │
│  InteractCommand::DragAt | MouseDownAt | MouseUpAt               │
└────────────────────────────────┬─────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Command Module (interact.rs)                    │
│  ┌──────────────────┐  ┌───────────────────┐  ┌───────────────┐ │
│  │ execute_drag_at  │  │execute_mousedown_at│  │execute_mouseup│ │
│  └────────┬─────────┘  └─────────┬─────────┘  └──────┬────────┘ │
│           │                      │                     │          │
│           ▼                      ▼                     ▼          │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  get_frame_viewport_offset (existing)                        ││
│  │  dispatch_drag / dispatch_drag_interpolated (new)            ││
│  │  dispatch_mousedown / dispatch_mouseup (new helpers)         ││
│  └──────────────────────────┬───────────────────────────────────┘│
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                      CDP Client (cdp/)                            │
│  Input.dispatchMouseEvent (mousePressed, mouseMoved, mouseRel.)  │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User runs: agentchrome interact drag-at 100 200 300 400 --steps 3
2. CLI layer parses args into DragAtArgs { from_x: 100, from_y: 200, to_x: 300, to_y: 400, steps: 3 }
3. execute_interact dispatches to execute_drag_at
4. Session is established via setup_session
5. Frame offset is resolved (0,0 for main frame, or iframe offset)
6. Coordinates are translated: from_x + offset_x, from_y + offset_y, etc.
7. dispatch_drag_interpolated sends: mousePressed → N mouseMoved → mouseReleased
8. Optional snapshot is taken
9. DragAtResult is serialized to JSON and printed to stdout
```

---

## API / Interface Changes

### New CLI Subcommands

| Subcommand | Args | Purpose |
|------------|------|---------|
| `interact drag-at <fromX> <fromY> <toX> <toY>` | `--steps`, `--include-snapshot`, `--compact` | Coordinate-based drag |
| `interact mousedown-at <X> <Y>` | `--button`, `--include-snapshot`, `--compact` | Decomposed mouse press |
| `interact mouseup-at <X> <Y>` | `--button`, `--include-snapshot`, `--compact` | Decomposed mouse release |

### New Types (cli/mod.rs)

#### `MouseButton` enum

```rust
#[derive(Clone, ValueEnum)]
pub enum MouseButton {
    Left,
    Middle,
    Right,
}
```

Maps to CDP `Input.dispatchMouseEvent` button parameter: `"left"`, `"middle"`, `"right"`.

#### `DragAtArgs`

```rust
pub struct DragAtArgs {
    pub from_x: f64,     // Source X coordinate
    pub from_y: f64,     // Source Y coordinate
    pub to_x: f64,       // Target X coordinate
    pub to_y: f64,       // Target Y coordinate
    pub steps: Option<u32>,       // Interpolation steps (default: 1)
    pub include_snapshot: bool,
    pub compact: bool,
}
```

#### `MouseDownAtArgs`

```rust
pub struct MouseDownAtArgs {
    pub x: f64,
    pub y: f64,
    pub button: Option<MouseButton>,  // Default: left
    pub include_snapshot: bool,
    pub compact: bool,
}
```

#### `MouseUpAtArgs`

```rust
pub struct MouseUpAtArgs {
    pub x: f64,
    pub y: f64,
    pub button: Option<MouseButton>,  // Default: left
    pub include_snapshot: bool,
    pub compact: bool,
}
```

### New Output Types (interact.rs)

#### `DragAtResult`

```rust
struct DragAtResult {
    dragged_at: DragAtCoords,      // { from: Coords, to: Coords }
    #[serde(skip_serializing_if = "Option::is_none")]
    steps: Option<u32>,            // Present when --steps > 1
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<Value>,
}

struct DragAtCoords {
    from: Coords,  // reuse existing Coords { x, y }
    to: Coords,
}
```

#### `MouseDownAtResult`

```rust
struct MouseDownAtResult {
    mousedown_at: Coords,
    #[serde(skip_serializing_if = "Option::is_none")]
    button: Option<String>,        // Present when not "left"
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<Value>,
}
```

#### `MouseUpAtResult`

```rust
struct MouseUpAtResult {
    mouseup_at: Coords,
    #[serde(skip_serializing_if = "Option::is_none")]
    button: Option<String>,        // Present when not "left"
    #[serde(skip_serializing_if = "Option::is_none")]
    snapshot: Option<Value>,
}
```

### Response Schemas

#### `interact drag-at` (JSON)

```json
{
  "dragged_at": {
    "from": { "x": 100.0, "y": 200.0 },
    "to": { "x": 300.0, "y": 400.0 }
  },
  "steps": 5,
  "snapshot": null
}
```

#### `interact mousedown-at` (JSON)

```json
{
  "mousedown_at": { "x": 150.0, "y": 250.0 },
  "button": "right",
  "snapshot": null
}
```

#### `interact mouseup-at` (JSON)

```json
{
  "mouseup_at": { "x": 300.0, "y": 400.0 },
  "button": "right",
  "snapshot": null
}
```

### Errors

| Code / Type | Condition |
|-------------|-----------|
| Exit 1 (General) | CDP dispatch failure |
| Exit 2 (Connection) | No active session / connection failure |
| Exit 3 (Target) | Invalid frame index |

---

## Database / Storage Changes

None — no persistent storage needed.

---

## State Management

No new state management. These commands are stateless coordinate dispatchers. The decomposed mousedown/mouseup commands intentionally do not track press state across invocations — the Chrome browser itself maintains the mouse button state via CDP.

---

## New Functions (interact.rs)

### `dispatch_mousedown`

Dispatches a single `mousePressed` event. Similar to the first half of `dispatch_click` but without the corresponding release.

```rust
async fn dispatch_mousedown(
    session: &mut ManagedSession,
    x: f64, y: f64,
    button: &str,
) -> Result<(), AppError>
```

### `dispatch_mouseup`

Dispatches a single `mouseReleased` event.

```rust
async fn dispatch_mouseup(
    session: &mut ManagedSession,
    x: f64, y: f64,
    button: &str,
) -> Result<(), AppError>
```

### `dispatch_drag_interpolated`

Dispatches a drag with N intermediate mousemove steps via linear interpolation.

```rust
async fn dispatch_drag_interpolated(
    session: &mut ManagedSession,
    from_x: f64, from_y: f64,
    to_x: f64, to_y: f64,
    steps: u32,
) -> Result<(), AppError>
```

When `steps == 1`, this degenerates to the existing `dispatch_drag` behavior (press → single move → release). When `steps > 1`, the function linearly interpolates N evenly-spaced points between source and target, dispatching a `mouseMoved` event at each point before the final `mouseReleased`.

### `execute_drag_at`

Entry point for the `drag-at` subcommand. Pattern mirrors `execute_click_at`:

1. Setup session
2. Resolve frame offset
3. Translate coordinates
4. Call `dispatch_drag_interpolated`
5. Optional snapshot
6. Build result, output

### `execute_mousedown_at`

Entry point for `mousedown-at`. Simplest of the three:

1. Setup session
2. Resolve frame offset
3. Translate coordinates
4. Call `dispatch_mousedown`
5. Optional snapshot
6. Build result, output

### `execute_mouseup_at`

Entry point for `mouseup-at`. Same pattern as mousedown:

1. Setup session
2. Resolve frame offset
3. Translate coordinates
4. Call `dispatch_mouseup`
5. Optional snapshot
6. Build result, output

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: Extend existing `drag` with coordinate mode** | Add `--coords` flag to existing `drag` command | Fewer new subcommands | Mixes two distinct input modes (element vs coordinate) in one command; confusing API | Rejected — separate `drag-at` is cleaner, consistent with `click` vs `click-at` split |
| **B: Separate subcommands (selected)** | `drag-at`, `mousedown-at`, `mouseup-at` as new InteractCommand variants | Consistent with `click` / `click-at` pattern; clear separation of element-based vs coordinate-based; composable decomposed events | Three new subcommands | **Selected** |
| **C: Single `mouse` subcommand with action flag** | `interact mouse --action press --x 100 --y 200` | Single entry point | Verbose; inconsistent with existing CLI patterns | Rejected — doesn't match CLI ergonomics |

---

## Security Considerations

- [x] **Authentication**: N/A — local CDP connection
- [x] **Authorization**: N/A — operates on user's own browser
- [x] **Input Validation**: Coordinate values validated by clap as f64; steps validated as u32 >= 1
- [x] **Data Sanitization**: N/A — no user data stored
- [x] **Sensitive Data**: N/A — no secrets involved

---

## Performance Considerations

- [x] **No element resolution**: Coordinate-based commands skip DOM queries, making them faster than element-targeted equivalents (~10ms vs ~100ms)
- [x] **Linear interpolation**: `--steps N` adds N-1 extra CDP round-trips. At ~5ms per event, `--steps 20` adds ~100ms. Acceptable for the use case.
- [x] **No caching needed**: Each command is a one-shot operation
- [x] **No indexing needed**: No data storage

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI argument parsing | Unit | DragAtArgs, MouseDownAtArgs, MouseUpAtArgs parse correctly |
| Output formatting | Unit | Plain text formatters produce correct output |
| CDP dispatch | BDD/Integration | All 18 ACs as Gherkin scenarios |
| Frame translation | BDD/Integration | Frame-scoped dispatch for all 3 commands |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CDP `Input.dispatchMouseEvent` behavior differs between Chrome versions for decomposed events | Low | Medium | Test against current Chrome stable; decomposed events are well-established CDP primitives |
| `--steps` interpolation produces rounding artifacts at non-integer coordinates | Low | Low | Use f64 arithmetic throughout; round only for display |
| Argument name `--button` could conflict with future global flags | Low | Low | Name verified against current global flags; no collision. Retrospective learning applied. |

---

## Open Questions

- (None)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #194 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] Database/storage changes planned with migrations (N/A)
- [x] State management approach is clear (stateless)
- [x] UI components and hierarchy defined (N/A — CLI)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
