# Tasks: Add --wait-until Flag to Interact Click Commands

**Issues**: #148
**Date**: 2026-02-26
**Status**: Planning
**Author**: Claude

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Implementation | 3 | [ ] |
| Integration | 1 | [ ] |
| Testing | 4 | [ ] |
| **Total** | **10** | |

---

## Phase 1: Setup

### T001: Make navigate.rs wait helpers public

**File(s)**: `src/navigate.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `wait_for_event()` is `pub async fn`
- [ ] `wait_for_network_idle()` is `pub async fn`
- [ ] `NETWORK_IDLE_MS` is `pub const`
- [ ] `DEFAULT_NAVIGATE_TIMEOUT_MS` is `pub const`
- [ ] All existing navigate tests still pass
- [ ] No other code changes in navigate.rs

**Notes**: Only change visibility modifiers. These functions have clean signatures accepting generic `Receiver<CdpEvent>` and `u64` timeout — no navigate-specific dependencies leak.

### T002: Add wait_until field to ClickArgs and ClickAtArgs

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ClickArgs` has field `pub wait_until: Option<WaitUntil>` with `#[arg(long, value_enum)]`
- [ ] `ClickAtArgs` has field `pub wait_until: Option<WaitUntil>` with `#[arg(long, value_enum)]`
- [ ] `WaitUntil` is imported in the `ClickArgs`/`ClickAtArgs` scope (already available)
- [ ] `agentchrome interact click --help` shows `--wait-until` option
- [ ] `agentchrome interact click-at --help` shows `--wait-until` option
- [ ] Existing flags (`--double`, `--right`, `--include-snapshot`) are unaffected

**Notes**: Use `Option<WaitUntil>` (not `WaitUntil` with a default) to distinguish "flag omitted" from "explicit strategy." This preserves backward compatibility — `None` means legacy behavior.

---

## Phase 2: Implementation

### T003: Add url and navigated optional fields to ClickAtResult

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ClickAtResult` has `#[serde(skip_serializing_if = "Option::is_none")] url: Option<String>`
- [ ] `ClickAtResult` has `#[serde(skip_serializing_if = "Option::is_none")] navigated: Option<bool>`
- [ ] When `--wait-until` is not provided, `url` and `navigated` are `None` (not serialized)
- [ ] Existing `click-at` output structure is unchanged when flag is omitted
- [ ] `print_click_at_plain()` handles the new optional fields

### T004: Implement wait-until logic in execute_click()

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] When `args.wait_until` is `Some(strategy)`:
  - `Network` domain is enabled (for `networkidle`)
  - Appropriate CDP events are subscribed before dispatching the click
  - After click dispatch, delegates to `navigate::wait_for_event()` or `navigate::wait_for_network_idle()`
  - Timeout uses `global.timeout.unwrap_or(DEFAULT_NAVIGATE_TIMEOUT_MS)`
- [ ] When `args.wait_until` is `None`:
  - Legacy 100ms grace period behavior is preserved exactly
  - No extra CDP subscriptions are created
- [ ] When `args.wait_until` is `Some(WaitUntil::None)`:
  - Click dispatches and returns immediately (no grace period, no navigation check)
- [ ] URL is fetched after wait completes (not before)
- [ ] `navigated` field is set based on URL change or event receipt
- [ ] Timeout error returns exit code 4 with descriptive JSON error

**Notes**: The key branching point is after `dispatch_click()`. If `wait_until` is `Some`, skip the 100ms sleep and `try_recv()` and instead run the wait strategy. Import `WaitUntil` and wait helpers via `use crate::navigate::{...}`.

### T005: Implement wait-until logic in execute_click_at()

**File(s)**: `src/interact.rs`
**Type**: Modify
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] When `args.wait_until` is `Some(strategy)`:
  - `DOM`, `Page`, and `Network` domains are enabled as needed
  - Appropriate CDP events are subscribed before dispatching the click
  - After click dispatch, delegates to wait helpers (same as T004)
  - `url` and `navigated` fields are populated in `ClickAtResult`
  - Timeout uses `global.timeout.unwrap_or(DEFAULT_NAVIGATE_TIMEOUT_MS)`
- [ ] When `args.wait_until` is `None`:
  - Legacy behavior preserved (dispatch click, optional snapshot, return)
  - `url` and `navigated` fields are `None` in output
- [ ] Timeout error returns exit code 4 with descriptive JSON error

**Notes**: `execute_click_at()` currently doesn't enable `Page` or subscribe to any events. When `--wait-until` is provided, it needs the same domain/event setup as `execute_click()`.

---

## Phase 3: Integration

### T006: Update examples.rs with --wait-until click examples

**File(s)**: `src/examples.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] At least one example shows `interact click <target> --wait-until networkidle`
- [ ] Example description explains SPA-aware waiting
- [ ] `agentchrome examples` output includes the new example
- [ ] Existing examples are unmodified

---

## Phase 4: Testing

### T008: Create BDD feature file

**File(s)**: `tests/features/wait-until-click.feature`
**Type**: Create
**Depends**: T004, T005
**Acceptance**:
- [ ] All 6 acceptance criteria from requirements.md are Gherkin scenarios
- [ ] Feature file uses same step patterns as existing `tests/features/interact.feature`
- [ ] Scenarios cover: networkidle happy path, load full-page, click-at, backward compat, timeout, cross-command state
- [ ] Feature file is valid Gherkin syntax
- [ ] Feature file header references spec and issue number

### T009: Implement step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T008
**Acceptance**:
- [ ] All scenarios in `wait-until-click.feature` have matching step definitions
- [ ] Step definitions follow existing patterns in `bdd.rs`
- [ ] `cargo test --test bdd` passes (including any new Chrome-dependent steps tagged appropriately)
- [ ] No existing step definitions are broken

### T010: Manual smoke test against SauceDemo

**File(s)**: (no file changes — verification task)
**Type**: Verify
**Depends**: T004, T005
**Acceptance**:
- [ ] Build: `cargo build` succeeds
- [ ] Launch headless Chrome: `./target/debug/agentchrome connect --launch --headless`
- [ ] Navigate to SauceDemo: `./target/debug/agentchrome navigate https://www.saucedemo.com/`
- [ ] Login and exercise SPA navigation with `--wait-until networkidle`
- [ ] Verify command waits for network idle and returns updated URL
- [ ] Verify `page snapshot` after click+wait shows post-navigation content
- [ ] Disconnect and kill Chrome processes

### T011: Verify no regressions

**File(s)**: (no file changes — verification task)
**Type**: Verify
**Depends**: T004, T005, T009
**Acceptance**:
- [ ] `cargo test --lib` passes (all unit tests)
- [ ] `cargo test --test bdd` passes (all BDD tests)
- [ ] `cargo clippy` passes with no new warnings
- [ ] `cargo fmt --check` passes
- [ ] Existing interact click/click-at scenarios in `tests/features/interact.feature` still pass

---

## Dependency Graph

```
T001 (make helpers public) ──┐
                              ├──▶ T004 (implement click wait) ──┬──▶ T008 (BDD feature file)
T002 (add CLI args) ─────────┤                                   │         │
                              ├──▶ T005 (implement click-at wait)│    T009 (step definitions)
T003 (ClickAtResult fields) ─┘                                   │         │
                                                                  ├──▶ T010 (smoke test)
T006 (update examples) ◀── T002                                  │
                                                                  └──▶ T011 (verify no regressions)
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #148 | 2026-02-26 | Initial feature spec |

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
