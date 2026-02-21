# Tasks: Comprehensive Help Text

**Issue**: #26
**Date**: 2026-02-14
**Status**: Planning
**Author**: Claude (automated)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 1 | [ ] |
| Backend | 5 | [ ] |
| Integration | 1 | [ ] |
| Testing | 2 | [ ] |
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

### T001: Add top-level `after_long_help` with quick-start workflows and exit codes

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] Root `Cli` struct has `after_long_help` attribute
- [ ] Contains "QUICK START" section with 3–5 workflow examples
- [ ] Contains "EXIT CODES" section documenting codes 0–5
- [ ] Contains "ENVIRONMENT VARIABLES" section
- [ ] `cargo build` succeeds
- [ ] `agentchrome --help` renders the new sections

**Notes**: Use `after_long_help` (not `after_help`) so examples appear with `--help` but not `-h`. The string is a raw string literal in the `#[command(...)]` attribute on the `Cli` struct.

---

## Phase 2: Backend Implementation

### T002: Add `after_long_help` examples to all command group variants

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] Every variant in the `Command` enum has `after_long_help` with 2–4 usage examples
- [ ] Commands covered: Connect, Tabs, Navigate, Page, Dom, Js, Console, Network, Interact, Form, Emulate, Perf, Dialog, Config, Completions
- [ ] Examples are concrete and use realistic arguments
- [ ] `cargo build` succeeds

**Notes**: Add `after_long_help = "..."` inside each variant's `#[command(...)]` attribute. The Completions command already has installation examples in `long_about`; move those to `after_long_help` for consistency.

### T003: Add `long_about` and `after_long_help` to Tabs leaf commands

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `TabsCommand` variants (List, Create, Close, Activate) each have `long_about` describing what the command does, what it returns, and when to use it
- [ ] Each variant has `after_long_help` with 2–3 usage examples
- [ ] `cargo build` succeeds

### T004: Add `long_about` and `after_long_help` to Navigate, Page, Js, Console, Network leaf commands

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `NavigateCommand` variants (Back, Forward, Reload) each have `long_about` + `after_long_help`
- [ ] `PageCommand` variants (Text, Snapshot, Find, Screenshot, Resize) each have `long_about` + `after_long_help`
- [ ] `JsCommand::Exec` has `long_about` + `after_long_help`
- [ ] `ConsoleCommand` variants (Read, Follow) each have `long_about` + `after_long_help`
- [ ] `NetworkCommand` variants (List, Get, Follow) each have `long_about` + `after_long_help`
- [ ] `cargo build` succeeds

### T005: Add `long_about` and `after_long_help` to Interact, Form, Emulate, Perf, Dialog, Config leaf commands

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `InteractCommand` variants (Click, ClickAt, Hover, Drag, Type, Key, Scroll) each have `long_about` + `after_long_help`
- [ ] `FormCommand` variants (Fill, FillMany, Clear, Upload) each have `long_about` + `after_long_help`
- [ ] `EmulateCommand` variants (Set, Reset, Status) each have `long_about` + `after_long_help`
- [ ] `PerfCommand` variants (Start, Stop, Analyze, Vitals) each have `long_about` + `after_long_help`
- [ ] `DialogCommand` variants (Handle, Info) each have `long_about` + `after_long_help`
- [ ] `ConfigCommand` variants (Show, Init, Path) each have `long_about` + `after_long_help`
- [ ] `cargo build` succeeds

### T006: Review and enhance flag/argument help strings

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T003, T004, T005
**Acceptance**:
- [ ] All ~80 flags/arguments have complete, descriptive `help` strings (via doc comments)
- [ ] Default values are mentioned in help where applicable
- [ ] Conflicting flags mention their conflicts in help text where it aids understanding
- [ ] Consistent terminology: "UID" (not "uid" or "accessibility ID"), "CSS selector" (not "selector"), etc.
- [ ] `cargo build` succeeds
- [ ] `cargo clippy` passes

---

## Phase 3: Frontend Implementation

### T007: [Client-side model]

**File(s)**: `{presentation-layer}/models/...`
**Type**: Create
**Depends**: T002
**Acceptance**:
- [ ] Model matches API response schema
- [ ] Serialization/deserialization works
- [ ] Immutable with update method (if applicable)
- [ ] Unit tests for serialization

### T008: [Client-side service / API client]

**File(s)**: `{presentation-layer}/services/...`
**Type**: Create
**Depends**: T007
**Acceptance**:
- [ ] All API calls implemented
- [ ] Error handling with typed exceptions
- [ ] Uses project's HTTP client pattern
- [ ] Unit tests pass

### T009: [State management]

**File(s)**: `{presentation-layer}/state/...` or `{presentation-layer}/providers/...`
**Type**: Create
**Depends**: T008
**Acceptance**:
- [ ] State class defined (immutable if applicable)
- [ ] Loading/error states handled
- [ ] State transitions match design spec
- [ ] Unit tests for state transitions

### T010: [UI components]

**File(s)**: `{presentation-layer}/components/...` or `{presentation-layer}/widgets/...`
**Type**: Create
**Depends**: T009
**Acceptance**:
- [ ] Components match design specs
- [ ] Uses project's design tokens (no hardcoded values)
- [ ] Loading/error/empty states
- [ ] Component tests pass

### T011: [Screen / Page]

**File(s)**: `{presentation-layer}/screens/...` or `{presentation-layer}/pages/...`
**Type**: Create
**Depends**: T010
**Acceptance**:
- [ ] Screen layout matches design
- [ ] State management integration working
- [ ] Navigation implemented

---

## Phase 3: Integration

### T007: Style consistency review and formatting pass

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] All help text uses imperative voice ("List open tabs", not "Lists open tabs")
- [ ] All help text uses consistent capitalization (sentence case for descriptions)
- [ ] No trailing whitespace in help strings
- [ ] All examples use consistent formatting (comment + command pattern)
- [ ] `cargo fmt --check` passes
- [ ] `cargo clippy` passes

---

## Phase 4: BDD Testing

### T008: Create BDD feature file for help text verification

**File(s)**: `tests/features/help-text.feature`
**Type**: Create
**Depends**: T007
**Acceptance**:
- [ ] Feature file covers all acceptance criteria from requirements.md
- [ ] Scenarios verify top-level help content (quick-start, exit codes)
- [ ] Scenarios verify command group help content (examples sections)
- [ ] Scenarios verify leaf command help content (long descriptions, examples)
- [ ] Scenarios verify no placeholder/TODO text in any help output
- [ ] Valid Gherkin syntax

### T009: Implement BDD step definitions for help text tests

**File(s)**: `tests/bdd.rs` (or step definition files)
**Type**: Modify
**Depends**: T008
**Acceptance**:
- [ ] Step definitions for running `agentchrome --help` and capturing output
- [ ] Step definitions for verifying content presence/absence
- [ ] All scenarios pass: `cargo test --test bdd`

---

## Dependency Graph

```
T001 ──▶ T002 ──┬──▶ T003 ──┐
                │           │
                ├──▶ T004 ──┼──▶ T006 ──▶ T007 ──▶ T008 ──▶ T009
                │           │
                └──▶ T005 ──┘
```

T003, T004, T005 can be done in parallel after T002.

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included
- [x] No circular dependencies
- [x] Tasks are in logical execution order
