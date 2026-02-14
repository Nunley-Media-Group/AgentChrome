# Tasks: Scroll Interactions

**Issue**: #17
**Date**: 2026-02-14
**Status**: Planning
**Author**: Claude (writing-specs)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 3 | [ ] |
| Integration | 1 | [ ] |
| Testing | 3 | [ ] |
| **Total** | **9** | |

---

## Phase 1: Setup

### T001: Add ScrollArgs and ScrollDirection to CLI definitions

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ScrollDirection` enum with variants `Down`, `Up`, `Left`, `Right` derives `ValueEnum`
- [ ] `ScrollArgs` struct defined with all flags: `--direction`, `--amount`, `--to-element`, `--to-top`, `--to-bottom`, `--smooth`, `--container`, `--include-snapshot`
- [ ] Clap conflict groups enforce mutual exclusivity: `--to-top`/`--to-bottom`/`--to-element` conflict with each other and with `--direction`/`--amount`
- [ ] `--container` conflicts with `--to-element`, `--to-top`, `--to-bottom`
- [ ] `InteractCommand::Scroll(ScrollArgs)` variant added to enum
- [ ] `cargo clippy` passes with no new warnings

**Notes**: Follow the existing pattern of `ClickArgs`, `HoverArgs`, etc. Use `#[arg(long, conflicts_with_all = [...])]` for conflict groups. Default direction is `Down`.

### T002: Add ScrollResult output type and plain formatter

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ScrollResult` struct with fields: `scrolled: Coords`, `position: Coords`, optional `snapshot`
- [ ] `#[serde(skip_serializing_if = "Option::is_none")]` on `snapshot` field
- [ ] `print_scroll_plain()` function outputs human-readable text (e.g., "Scrolled down 600px to (0, 600)")
- [ ] Unit test for `ScrollResult` serialization (JSON contains `scrolled.x`, `scrolled.y`, `position.x`, `position.y`)
- [ ] Unit test for `ScrollResult` serialization with snapshot present
- [ ] Unit test for `ScrollResult` serialization with snapshot absent (field omitted)

**Notes**: Reuse existing `Coords` struct. Follow `ClickResult`/`HoverResult` pattern.

---

## Phase 2: Backend Implementation

### T003: Implement scroll helper functions

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] `get_scroll_position(session) -> Result<(f64, f64), AppError>` reads `window.scrollX`/`scrollY` via `Runtime.evaluate`
- [ ] `get_viewport_dimensions(session) -> Result<(f64, f64), AppError>` reads `window.innerWidth`/`innerHeight`
- [ ] `dispatch_page_scroll(session, dx, dy, smooth) -> Result<(), AppError>` calls `window.scrollBy()` with optional `behavior: 'smooth'`
- [ ] `dispatch_page_scroll_to(session, x, y, smooth) -> Result<(), AppError>` calls `window.scrollTo()` with optional `behavior: 'smooth'`
- [ ] `dispatch_container_scroll(session, backend_node_id, dx, dy, smooth) -> Result<(), AppError>` resolves node to Runtime objectId, then calls `element.scrollBy()` via `Runtime.callFunctionOn`
- [ ] `get_container_scroll_position(session, backend_node_id) -> Result<(f64, f64), AppError>` reads `element.scrollLeft`/`scrollTop`
- [ ] `wait_for_smooth_scroll(session, get_position_fn) -> Result<(), AppError>` polls position at 200ms intervals until stable (3s timeout)
- [ ] All helpers use `AppError::interaction_failed()` for error mapping

**Notes**: Use `DOM.resolveNode` → `Runtime.callFunctionOn` for container operations (pattern from `src/form.rs`). For smooth scroll wait, compare consecutive position readings.

### T004: Implement execute_scroll command

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] `execute_scroll(global, args) -> Result<(), AppError>` function implemented
- [ ] Session setup via `setup_session()` with auto-dismiss support
- [ ] Enables `Runtime` and `DOM` domains
- [ ] Mode selection logic:
  - `--to-element`: calls `resolve_target_to_backend_node_id()` then `scroll_into_view()` (existing helper)
  - `--to-top`: calls `dispatch_page_scroll_to(0, 0, smooth)`
  - `--to-bottom`: calls `dispatch_page_scroll_to(0, document.body.scrollHeight, smooth)`
  - Default/`--direction` + `--amount`: computes delta from direction and amount, calls `dispatch_page_scroll()`
  - `--container` + `--direction`/`--amount`: calls `dispatch_container_scroll()`
- [ ] Default amount: viewport height for vertical, viewport width for horizontal
- [ ] Reads scroll position before and after to compute delta
- [ ] For `--to-element`: reads position before and after `scroll_into_view()` call
- [ ] Smooth scroll wait when `--smooth` is set
- [ ] Takes snapshot if `--include-snapshot`
- [ ] Outputs `ScrollResult` via `print_output()` or `print_scroll_plain()`
- [ ] Handles container scroll position reads when `--container` is used

**Notes**: Follow the exact pattern of `execute_click()` — setup, enable domains, perform action, optional snapshot, output.

### T005: Wire Scroll variant into dispatcher and imports

**File(s)**: `src/interact.rs`, `src/cli/mod.rs`
**Type**: Modify
**Depends**: T001, T004
**Acceptance**:
- [ ] `InteractCommand::Scroll(scroll_args) => execute_scroll(global, scroll_args).await` added to `execute_interact()` match
- [ ] `ScrollArgs` imported in `src/interact.rs` use statement
- [ ] `cargo build` succeeds
- [ ] `cargo clippy` passes

---

## Phase 3: Integration

### T006: Verify CLI integration and help text

**File(s)**: (no file changes — verification only)
**Type**: Verify
**Depends**: T005
**Acceptance**:
- [ ] `chrome-cli interact --help` lists `scroll` subcommand
- [ ] `chrome-cli interact scroll --help` shows all flags: `--direction`, `--amount`, `--to-element`, `--to-top`, `--to-bottom`, `--smooth`, `--container`, `--include-snapshot`
- [ ] `chrome-cli interact scroll --to-top --to-bottom` produces a clap conflict error
- [ ] `chrome-cli interact scroll` (no args) is accepted (uses defaults)

---

## Phase 4: BDD Testing

### T007: Create BDD feature file for scroll interactions

**File(s)**: `tests/features/scroll.feature`
**Type**: Create
**Depends**: T005
**Acceptance**:
- [ ] Feature file contains scenarios for all 15 acceptance criteria from requirements.md
- [ ] CLI argument validation scenarios (no Chrome required)
- [ ] Chrome-required scenarios use established Background/Given patterns
- [ ] Valid Gherkin syntax
- [ ] Covers: default scroll, directional scroll, pixel amount, to-top, to-bottom, to-element (UID and CSS), smooth, container, tab targeting, include-snapshot, conflicting flags, UID not found, horizontal scroll, no mandatory arguments

### T008: Add scroll step definitions and wire into BDD runner

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] Scroll feature file registered in BDD test runner
- [ ] Existing step definitions (e.g., `I run {string}`, `the exit code should be {int}`) cover scroll scenarios
- [ ] Any new scroll-specific steps defined if needed (e.g., scroll position assertions)
- [ ] `cargo test --test bdd` includes scroll scenarios

### T009: Add unit tests for scroll output types and direction logic

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] Unit test: `ScrollResult` serialization produces correct JSON structure
- [ ] Unit test: `ScrollResult` with snapshot omits field when None
- [ ] Unit test: `ScrollResult` with snapshot includes field when Some
- [ ] All unit tests pass: `cargo test --lib`

---

## Dependency Graph

```
T001 (CLI args) ──┬──▶ T003 (helpers) ──▶ T004 (execute_scroll) ──▶ T005 (wire dispatcher)
                  │                                                         │
T002 (output types) ──────────────────────────────────────────────────────┘
                  │                                                         │
                  └──▶ T009 (unit tests)                                    │
                                                                            ▼
                                                                     T006 (verify CLI)
                                                                            │
                                                                            ▼
                                                                     T007 (feature file)
                                                                            │
                                                                            ▼
                                                                     T008 (BDD wiring)
```

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
