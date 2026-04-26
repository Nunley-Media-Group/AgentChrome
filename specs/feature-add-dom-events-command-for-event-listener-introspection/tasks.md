# Tasks: DOM Events Command for Event Listener Introspection

**Issues**: #192
**Date**: 2026-04-16
**Status**: Planning
**Author**: Claude (spec agent)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 2 | [ ] |
| Frontend | 0 | [ ] |
| Integration | 2 | [ ] |
| Testing | 3 | [ ] |
| **Total** | **9** | |

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

### T001: Add Events variant and DomNodeIdArgs to DomCommand enum

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `DomCommand::Events(DomNodeIdArgs)` variant exists in the enum
- [ ] Variant has `#[command(name = "events")]` attribute
- [ ] `long_about` describes event listener introspection
- [ ] `after_long_help` includes usage examples (UID, CSS selector, frame)
- [ ] `cargo check` passes with the new variant

**Notes**: Reuse existing `DomNodeIdArgs` struct — no new args struct needed. The `--frame` flag is inherited from `DomArgs`. Follow the pattern of other DOM subcommand variants (e.g., `GetText`, `Parent`).

### T002: Add output types for event listener data

**File(s)**: `src/dom.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `EventHandler` struct defined with `description: String`, `script_id: Option<String>`, `line_number: Option<i64>`, `column_number: Option<i64>`
- [ ] `EventListenerInfo` struct defined with `event_type: String`, `use_capture: bool`, `once: bool`, `passive: bool`, `handler: EventHandler`
- [ ] `EventListenersResult` struct defined with `listeners: Vec<EventListenerInfo>`
- [ ] All structs derive `Serialize`
- [ ] Serde rename attributes applied: `type`, `useCapture`, `scriptId`, `lineNumber`, `columnNumber`
- [ ] Unit tests pass for serialization of all three types

---

## Phase 2: Backend Implementation

### T003: Implement execute_events function

**File(s)**: `src/dom.rs`
**Type**: Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] `execute_events` function follows the pattern of `execute_get_text` (session setup, frame resolution, domain enable, node resolution)
- [ ] Enables `DOM` and `Runtime` domains on the effective session
- [ ] Calls `resolve_node()` to get session-scoped `node_id`
- [ ] Calls `DOM.resolveNode({ nodeId })` to obtain `Runtime.RemoteObjectId`
- [ ] Calls `DOMDebugger.getEventListeners({ objectId })` with the resolved objectId
- [ ] Maps CDP response to `EventListenersResult`:
  - `type` from `listener.type`
  - `useCapture` from `listener.useCapture`
  - `once` from `listener.once`
  - `passive` from `listener.passive`
  - `handler.description` from `listener.handler.description`
  - `handler.scriptId` from `listener.scriptId` (null if absent)
  - `handler.lineNumber` from `listener.lineNumber` (null if absent)
  - `handler.columnNumber` from `listener.columnNumber` (null if absent)
- [ ] Returns empty `listeners: []` when CDP returns no listeners (not an error)
- [ ] Plain text output (`--plain`): one line per listener with format `<type>  capture:<bool>  once:<bool>  passive:<bool>  handler:<description>`
- [ ] JSON output via `print_output()` for default/--json/--pretty modes
- [ ] Error handling: descriptive error message if CDP call fails

### T004: Wire up Events variant in execute_dom dispatcher

**File(s)**: `src/dom.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] `DomCommand::Events(node_args)` match arm added in `execute_dom()`
- [ ] Dispatches to `execute_events(global, node_args, frame).await`
- [ ] `cargo build` succeeds with no warnings

---

## Phase 3: Frontend Implementation

No frontend tasks — this is a CLI-only feature with no UI components.

---

## Phase 4: Integration

### T005: Add dom events entry to built-in examples

**File(s)**: `src/examples.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] New `ExampleEntry` added to the `dom` `CommandGroupSummary` examples vector
- [ ] Example command: `agentchrome dom events css:button`
- [ ] Example description: `List event listeners on an element`
- [ ] Appears in `agentchrome examples dom` output
- [ ] `cargo test --lib` passes (examples test still passes)

### T006: Create test fixture HTML file

**File(s)**: `tests/fixtures/dom-events.html`
**Type**: Create
**Depends**: None
**Acceptance**:
- [ ] Self-contained HTML with no external dependencies
- [ ] Contains elements exercising all ACs:
  - Button with `addEventListener('click', ...)` (AC1)
  - Button with `onclick="..."` inline handler (AC2)
  - Element inside an iframe (AC3)
  - Element with no listeners (AC4)
  - Elements with multiple listener types for --plain format testing (AC6)
- [ ] HTML comment at top documents which ACs the fixture covers
- [ ] File is committed to the repo

---

## Phase 5: BDD Testing (Required)

**Every acceptance criterion MUST have a Gherkin test.**

### T007: Create BDD feature file

**File(s)**: `tests/features/dom-events.feature`
**Type**: Create
**Depends**: T003
**Acceptance**:
- [ ] All 7 acceptance criteria have corresponding scenarios
- [ ] Uses Given/When/Then format consistent with existing feature files
- [ ] Background includes `Given agentchrome is built`
- [ ] Feature description matches user story
- [ ] Valid Gherkin syntax

### T008: Implement BDD step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] Step definitions implement all scenarios from the feature file
- [ ] Steps follow existing patterns in `tests/bdd.rs`
- [ ] `cargo test --test bdd` passes for the dom-events feature
- [ ] Tests use the `dom-events.html` fixture

### T009: Smoke test against real Chrome

**File(s)**: (no file changes — manual verification)
**Type**: Verify
**Depends**: T003, T006
**Acceptance**:
- [ ] Build from source: `cargo build`
- [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to test fixture: `./target/debug/agentchrome navigate file://<path>/tests/fixtures/dom-events.html`
- [ ] AC1: `dom events css:#btn-addeventlistener` returns listeners array with click handler, correct fields
- [ ] AC2: `dom events css:#btn-inline` returns listener for inline onclick handler
- [ ] AC4: `dom events css:#no-listeners` returns `{"listeners":[]}`
- [ ] AC6: `dom events css:#btn-addeventlistener --plain` returns human-readable text
- [ ] AC7: `examples dom` output includes `dom events` example
- [ ] Disconnect and kill Chrome: `./target/debug/agentchrome connect disconnect`

---

## Dependency Graph

```
T001 (CLI variant) ──┬──▶ T003 (execute_events) ──▶ T004 (dispatcher wiring)
                     │                                      │
T002 (output types) ─┘                                      │
                                                            ▼
T006 (test fixture) ──────────────────────────────▶ T007 (BDD feature file)
                                                            │
T005 (examples.rs) ◀── T001                                 ▼
                                                    T008 (step definitions)
                                                            │
                                                            ▼
                                                    T009 (smoke test)
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #192 | 2026-04-16 | Initial feature spec |

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
