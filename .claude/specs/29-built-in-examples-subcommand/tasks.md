# Tasks: Built-in Examples Subcommand

**Issue**: #29
**Date**: 2026-02-14
**Status**: Planning
**Author**: Claude (spec generation)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 2 | [ ] |
| Integration | 1 | [ ] |
| Testing | 2 | [ ] |
| **Total** | **7** | |

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

### T001: Add ExamplesArgs struct and Command::Examples variant

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ExamplesArgs` struct with optional `command: Option<String>` field
- [ ] `Command::Examples(ExamplesArgs)` variant added to `Command` enum
- [ ] Help text includes `long_about` and `after_long_help` with examples
- [ ] `ExamplesArgs` imported in `src/main.rs` use statement
- [ ] `cargo check` passes

**Notes**: Follow the pattern of `ManArgs` — a simple struct with one optional positional arg. Add the variant between `Man` and `Completions` (or at the end) in the enum.

### T002: Define output types for examples data

**File(s)**: `src/examples.rs` (create)
**Type**: Create
**Depends**: None
**Acceptance**:
- [ ] `CommandGroupSummary` struct with `command: String`, `description: String`, `examples: Vec<ExampleEntry>`
- [ ] `ExampleEntry` struct with `cmd: String`, `description: String`, `flags: Option<Vec<String>>`
- [ ] Both structs derive `Serialize`
- [ ] `flags` field uses `#[serde(skip_serializing_if = "Option::is_none")]`
- [ ] `cargo check` passes

---

## Phase 2: Backend Implementation

### T003: Implement static example data

**File(s)**: `src/examples.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `fn all_examples() -> Vec<CommandGroupSummary>` returns data for all 13 command groups: connect, tabs, navigate, page, dom, js, console, network, interact, form, emulate, perf, dialog, config
- [ ] Each command group has 3–5 examples
- [ ] Each example `cmd` is a syntactically valid agentchrome invocation
- [ ] Examples cover common use cases per the existing `after_long_help` text in cli/mod.rs
- [ ] `flags` field populated where relevant

### T004: Implement execute_examples dispatcher and formatting

**File(s)**: `src/examples.rs`
**Type**: Modify
**Depends**: T001, T003
**Acceptance**:
- [ ] `pub fn execute_examples(global: &GlobalOpts, args: &ExamplesArgs) -> Result<(), AppError>` implemented
- [ ] Without command arg: prints all groups (summary view)
- [ ] With command arg: prints detailed examples for that group
- [ ] Unknown command arg returns `AppError` with `ExitCode::GeneralError`
- [ ] Plain text output: uses `# description` comment style, indented commands
- [ ] JSON output: compact JSON via `serde_json::to_string`
- [ ] Pretty output: indented JSON via `serde_json::to_string_pretty`
- [ ] Default (no output flags): plain text
- [ ] `print_output` helper follows `tabs.rs` pattern

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

### T005: Wire examples command into main dispatcher

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [ ] `mod examples;` added to module declarations
- [ ] `ExamplesArgs` imported from `cli` module
- [ ] `Command::Examples(args) => examples::execute_examples(&global, args)` added to match in `run()`
- [ ] No `async` — this is a sync call (same as `execute_completions`, `execute_man`)
- [ ] `cargo build` succeeds
- [ ] Running `agentchrome examples` prints expected output
- [ ] Running `agentchrome examples navigate` prints navigate examples
- [ ] Running `agentchrome examples --json` prints valid JSON
- [ ] Running `agentchrome examples nonexistent` exits non-zero with error

---

## Phase 4: Testing

### T006: Create BDD feature file for examples command

**File(s)**: `tests/features/examples.feature`
**Type**: Create
**Depends**: T005
**Acceptance**:
- [ ] All 8 acceptance criteria from requirements.md have corresponding scenarios
- [ ] Uses Given/When/Then format
- [ ] Includes error handling scenarios (unknown command)
- [ ] Feature file is valid Gherkin syntax
- [ ] Includes data-driven scenarios for per-group coverage

### T007: Add unit tests for examples module

**File(s)**: `src/examples.rs` (inline `#[cfg(test)]` module)
**Type**: Modify
**Depends**: T003, T004
**Acceptance**:
- [ ] Test: `all_examples()` returns expected number of command groups (13+)
- [ ] Test: each group has at least 3 examples
- [ ] Test: no empty `cmd` or `description` fields
- [ ] Test: `execute_examples` with `None` command succeeds
- [ ] Test: `execute_examples` with valid command name succeeds
- [ ] Test: `execute_examples` with unknown command returns error
- [ ] Test: plain text formatting produces expected structure
- [ ] `cargo test` passes

---

## Dependency Graph

```
T001 (CLI args) ──┐
                  ├──▶ T004 (dispatcher) ──▶ T005 (wire into main) ──▶ T006 (BDD)
T002 (types) ─┬──┘
              │
              └──▶ T003 (data) ──▶ T004
                                    │
                                    └──▶ T007 (unit tests)
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
