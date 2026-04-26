# Tasks: Coordinate-based Drag and Decomposed Mouse Actions

**Issues**: #194
**Date**: 2026-04-16
**Status**: Planning
**Author**: Claude (writing-specs)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 4 | [ ] |
| Frontend | 0 | [ ] |
| Integration | 2 | [ ] |
| Testing | 3 | [ ] |
| **Total** | **11** | |

---

## Task Format

Each task follows this structure:

```
### T[NNN]: [Task Title]

**File(s)**: `{layer}/path/to/file`
**Type**: Create | Modify | Delete
**Depends**: T[NNN], T[NNN] (or None)
**Acceptance**:
- [ ] [Verifiable criterion 1]
- [ ] [Verifiable criterion 2]

**Notes**: [Optional implementation hints]
```

Map `{layer}/` placeholders to actual project paths using `structure.md`.

---

## Phase 1: Setup

### T001: Define CLI argument types for new subcommands

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `MouseButton` value enum defined with variants `Left`, `Middle`, `Right`
- [ ] `DragAtArgs` struct defined with `from_x`, `from_y`, `to_x`, `to_y` (all f64), `steps` (Option<u32>), `include_snapshot` (bool), `compact` (bool)
- [ ] `MouseDownAtArgs` struct defined with `x`, `y` (f64), `button` (Option<MouseButton>), `include_snapshot` (bool), `compact` (bool)
- [ ] `MouseUpAtArgs` struct defined with `x`, `y` (f64), `button` (Option<MouseButton>), `include_snapshot` (bool), `compact` (bool)
- [ ] `InteractCommand` enum extended with `DragAt(DragAtArgs)`, `MouseDownAt(MouseDownAtArgs)`, `MouseUpAt(MouseUpAtArgs)` variants
- [ ] Each variant has `long_about` help text and `after_long_help` examples consistent with existing subcommands
- [ ] `DragAtArgs`, `MouseDownAtArgs`, `MouseUpAtArgs` are re-exported in the `use crate::cli::` import block of `src/interact.rs`

**Notes**: Follow the pattern of `ClickAtArgs` for coordinate-based args. `MouseButton` enum uses `#[derive(Clone, ValueEnum)]` for clap integration. Place the `MouseButton` enum near the existing `WaitUntil` enum.

### T002: Define output types for new commands

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `DragAtCoords` struct defined with `from: Coords`, `to: Coords` (reuses existing `Coords`)
- [ ] `DragAtResult` struct defined with `dragged_at: DragAtCoords`, optional `steps: Option<u32>`, optional `snapshot: Option<Value>`
- [ ] `MouseDownAtResult` struct defined with `mousedown_at: Coords`, optional `button: Option<String>`, optional `snapshot: Option<Value>`
- [ ] `MouseUpAtResult` struct defined with `mouseup_at: Coords`, optional `button: Option<String>`, optional `snapshot: Option<Value>`
- [ ] All structs derive `Serialize`
- [ ] Optional fields use `#[serde(skip_serializing_if = "Option::is_none")]`
- [ ] Plain text formatters added: `print_drag_at_plain`, `print_mousedown_at_plain`, `print_mouseup_at_plain`

**Notes**: Place output types near existing `DragResult`. Plain text formats: `Dragged from (X, Y) to (X, Y)`, `Mousedown at (X, Y)`, `Mouseup at (X, Y)`.

---

## Phase 2: Backend Implementation

### T003: Implement dispatch_mousedown helper

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `dispatch_mousedown(session, x, y, button)` async function dispatches a single `mousePressed` event via `Input.dispatchMouseEvent`
- [ ] Uses CDP JSON params: `{"type": "mousePressed", "x": x, "y": y, "button": button, "clickCount": 1}`
- [ ] Returns `Result<(), AppError>` with `interaction_failed` error on CDP failure
- [ ] No `mouseReleased` event is dispatched

**Notes**: Extract from the first half of the existing `dispatch_click` function. Place near existing `dispatch_hover`.

### T004: Implement dispatch_mouseup helper

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `dispatch_mouseup(session, x, y, button)` async function dispatches a single `mouseReleased` event via `Input.dispatchMouseEvent`
- [ ] Uses CDP JSON params: `{"type": "mouseReleased", "x": x, "y": y, "button": button, "clickCount": 1}`
- [ ] Returns `Result<(), AppError>` with `interaction_failed` error on CDP failure
- [ ] No `mousePressed` event is dispatched

**Notes**: Extract from the second half of the existing `dispatch_click` function. Place near `dispatch_mousedown`.

### T005: Implement dispatch_drag_interpolated helper

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T003, T004
**Acceptance**:
- [ ] `dispatch_drag_interpolated(session, from_x, from_y, to_x, to_y, steps)` async function dispatches a full drag sequence with interpolated intermediate moves
- [ ] Dispatches `mousePressed` at (from_x, from_y) with button "left"
- [ ] When `steps == 1`: dispatches single `mouseMoved` to (to_x, to_y) (matches existing `dispatch_drag` behavior)
- [ ] When `steps > 1`: linearly interpolates N evenly-spaced points and dispatches `mouseMoved` at each
- [ ] Dispatches `mouseReleased` at (to_x, to_y) with button "left"
- [ ] Interpolation formula: for step i in 1..=steps: x = from_x + (to_x - from_x) * i / steps, y = from_y + (to_y - from_y) * i / steps
- [ ] Returns `Result<(), AppError>`

**Notes**: When steps is 1, this is functionally equivalent to the existing `dispatch_drag`. The last interpolated point always lands exactly on (to_x, to_y).

### T006: Implement execute functions for new subcommands

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T002, T003, T004, T005
**Acceptance**:
- [ ] `execute_drag_at(global, args, frame)` follows the `execute_click_at` pattern: setup_session → resolve frame offset → translate coordinates → dispatch_drag_interpolated → optional snapshot → build DragAtResult → print
- [ ] `execute_mousedown_at(global, args, frame)` follows the same pattern: setup_session → resolve frame offset → translate coordinates → dispatch_mousedown → optional snapshot → build MouseDownAtResult → print
- [ ] `execute_mouseup_at(global, args, frame)` follows the same pattern: setup_session → resolve frame offset → translate coordinates → dispatch_mouseup → optional snapshot → build MouseUpAtResult → print
- [ ] `MouseButton` to CDP string conversion: `Left` → "left", `Middle` → "middle", `Right` → "right"; default to "left" when `--button` is `None`
- [ ] `DragAtResult.steps` is `Some(n)` when `args.steps` is `Some(n)` and n > 1, else `None`
- [ ] Button field in output: `Some("right")` or `Some("middle")` when non-default button is used, `None` for left (default)
- [ ] All three functions handle `auto_dismiss_dialogs` consistently with existing commands
- [ ] All three functions support `--include-snapshot` and `--compact` flags
- [ ] Plain text output is used when `global.output.plain` is true

**Notes**: The `frame` parameter comes from `InteractArgs.frame` and is already passed by the `execute_interact` dispatcher. Each function should call `crate::output::resolve_optional_frame` with `None` for the target (since these are coordinate-based, not element-based).

---

## Phase 3: Frontend Implementation

(No frontend — this is a CLI-only feature)

---

## Phase 4: Integration

### T007: Wire new subcommands into the dispatcher

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] `execute_interact` match block extended with `InteractCommand::DragAt(args) => execute_drag_at(global, args, frame).await`
- [ ] `InteractCommand::MouseDownAt(args) => execute_mousedown_at(global, args, frame).await`
- [ ] `InteractCommand::MouseUpAt(args) => execute_mouseup_at(global, args, frame).await`
- [ ] `cargo build` succeeds
- [ ] `cargo clippy --all-targets` passes

**Notes**: Add the three new arms after the existing `InteractCommand::Drag` arm in the match block.

### T008: Update built-in examples

**File(s)**: `src/examples.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] Three new `ExampleEntry` items added to the `interact` command group
- [ ] `drag-at` example: `agentchrome interact drag-at 100 200 300 400` — "Drag from coordinates to coordinates"
- [ ] `mousedown-at` example: `agentchrome interact mousedown-at 100 200` — "Press mouse button at coordinates (no release)"
- [ ] `mouseup-at` example: `agentchrome interact mouseup-at 300 400` — "Release mouse button at coordinates"
- [ ] Existing examples preserved unchanged

---

## Phase 5: BDD Testing (Required)

### T009: Create BDD feature file

**File(s)**: `tests/features/coordinate-drag-decomposed-mouse.feature`
**Type**: Create
**Depends**: T007
**Acceptance**:
- [ ] All 18 acceptance criteria from requirements.md are Gherkin scenarios
- [ ] Uses Given/When/Then format
- [ ] Background sets up CLI binary path
- [ ] Scenarios cover: drag-at (AC1), mousedown-at (AC2), mouseup-at (AC3), multi-invocation (AC4), frame-scoped (AC5-7), steps (AC8-9), button (AC10-11), plain text (AC12-14), include-snapshot (AC15-17), examples (AC18)
- [ ] Feature file is valid Gherkin syntax

### T010: Implement step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T009
**Acceptance**:
- [ ] Step definitions added for new scenarios that require custom matchers
- [ ] Existing generic steps (CLI execution, JSON field assertions, exit code checks) are reused where possible
- [ ] All BDD scenarios pass with `cargo test --test bdd`

### T011: Manual smoke test against real Chrome

**File(s)**: `tests/fixtures/coordinate-drag-decomposed-mouse.html`
**Type**: Create
**Depends**: T007
**Acceptance**:
- [ ] HTML fixture created with drag-and-drop elements and JavaScript event listeners that log mouse events
- [ ] Fixture covers: draggable div, drop target area, event log display
- [ ] Smoke test procedure:
  1. `cargo build`
  2. `./target/debug/agentchrome connect --launch --headless`
  3. Navigate to fixture file
  4. Test `drag-at` between coordinates
  5. Test `mousedown-at` + `mouseup-at` sequence
  6. Test `--steps` interpolation
  7. Verify JSON output structure
  8. `./target/debug/agentchrome connect disconnect`
- [ ] All ACs verified against real Chrome instance

---

## Dependency Graph

```
T001 ──┬──▶ T002 ──────────────────────┐
       │                                │
       ├──▶ T003 ──┐                    │
       │           │                    │
       ├──▶ T004 ──┼──▶ T005 ──┐       │
       │           │            │       │
       │           │            ▼       ▼
       │           └──────────▶ T006 ──▶ T007 ──┬──▶ T008
       │                                        │
       │                                        ├──▶ T009 ──▶ T010
       │                                        │
       └────────────────────────────────────────┴──▶ T011
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #194 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included for each layer
- [x] No circular dependencies
- [x] Tasks are in logical execution order
