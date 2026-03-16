# Tasks: navigate returns before SPA email list renders (add --wait-for-selector)

**Issue**: #178
**Date**: 2026-03-15
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Add `--wait-for-selector` CLI argument and expose selector polling | [ ] |
| T002 | Add selector polling to navigate after primary wait | [ ] |
| T003 | Add regression test | [ ] |
| T004 | Verify no regressions | [ ] |

---

### T001: Add --wait-for-selector CLI Argument and Expose Selector Polling

**File(s)**: `src/cli/mod.rs`, `src/page/wait.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `NavigateUrlArgs` has a new `wait_for_selector: Option<String>` field with `#[arg(long)]`
- [ ] Help text for the field includes a description and SPA example
- [ ] `check_selector_condition` in `src/page/wait.rs` is changed to `pub(crate)` visibility
- [ ] `cargo build` compiles without errors
- [ ] `cargo clippy` passes

**Notes**: The `--wait-for-selector` argument is optional and defaults to `None`. Add it after the existing `--wait-until` field in `NavigateUrlArgs`. Make `check_selector_condition` `pub(crate)` so `navigate.rs` can call it. Also make `eval_js` `pub(crate)` since `check_selector_condition` depends on it.

### T002: Add Selector Polling to Navigate After Primary Wait

**File(s)**: `src/navigate.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] After the primary wait strategy block in `execute_url`, when `args.wait_for_selector` is `Some(selector)`, the function enables the `Runtime` domain and polls for the selector
- [ ] Polling uses `check_selector_condition` from `page/wait.rs` with 100ms interval
- [ ] Remaining timeout is computed from the navigate-level `--timeout` (or default 30s) minus time already elapsed
- [ ] If the selector is found, execution continues to output the `NavigateResult` as normal
- [ ] If the remaining timeout expires before the selector is found, the command returns `AppError` with exit code 4 (timeout) and a message identifying the unmatched selector
- [ ] When `--wait-for-selector` is not provided, the existing code path is unchanged
- [ ] `cargo build` compiles without errors
- [ ] `cargo clippy` passes
- [ ] Existing unit tests in `navigate.rs` still pass

**Notes**: Use `std::time::Instant` to track elapsed time. After the primary wait strategy completes, compute `remaining = timeout_ms - elapsed`. If remaining <= 0, immediately return a timeout error. Otherwise, poll in a loop with `tokio::time::sleep(Duration::from_millis(100))` and check `Instant::now() > deadline`.

### T003: Add Regression Test

**File(s)**: `tests/features/178-fix-navigate-wait-for-selector.feature`, `tests/bdd.rs`
**Type**: Create / Modify
**Depends**: T002
**Acceptance**:
- [ ] Gherkin feature file covers all three acceptance criteria (AC1: selector wait succeeds, AC2: default behavior unchanged, AC3: timeout on missing selector)
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions implemented in `tests/bdd.rs`
- [ ] `cargo test --test bdd` passes (BDD tests compile and non-Chrome-dependent scenarios pass)

### T004: Verify No Regressions

**File(s)**: (existing test files)
**Type**: Verify (no file changes)
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] `cargo test` passes (all unit tests)
- [ ] `cargo clippy` passes
- [ ] `cargo fmt --check` passes
- [ ] **Local SPA simulation smoke test**: Create a local HTML file that simulates delayed SPA rendering — the page load event fires immediately, but a target element (e.g., `<div id="spa-content">`) is injected via `setTimeout` after 2 seconds. Serve it with `python3 -m http.server` (or open via `file://`). Run `navigate --wait-for-selector '#spa-content' http://localhost:<port>/spa-test.html` — command should block ~2s then return successfully. Then run with `--timeout 500` — command should time out with exit code 4 before the element appears. This validates the core fix against a deterministic reproduction of the SPA timing gap.
- [ ] Manual smoke test: build debug binary, connect to headless Chrome, run `navigate --wait-for-selector 'h1' https://www.saucedemo.com/` — command returns after `<h1>` appears
- [ ] Manual smoke test: run `navigate https://www.saucedemo.com/` without `--wait-for-selector` — behavior is identical to before the change
- [ ] Manual smoke test: run `navigate --wait-for-selector '.nonexistent' --timeout 2000 https://www.saucedemo.com/` — command times out with exit code 4
- [ ] SauceDemo smoke test: navigate + snapshot baseline check passes

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T003)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
