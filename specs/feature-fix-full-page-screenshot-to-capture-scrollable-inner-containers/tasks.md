# Tasks: Fix Full-Page Screenshot for Scrollable Inner Containers

**Issues**: #184
**Date**: 2026-04-16
**Status**: Planning
**Author**: Claude

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 1 | [ ] |
| Backend | 5 | [ ] |
| Integration | 2 | [ ] |
| Testing | 5 | [ ] |
| **Total** | **13** | |

---

## Phase 1: Setup

### T001: Add --scroll-container CLI argument

**File(s)**: `src/cli/mod.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `PageScreenshotArgs` has a new `scroll_container: Option<String>` field
- [ ] Field has `#[arg(long)]` attribute with help text: "CSS selector for the inner scrollable element (requires --full-page)"
- [ ] `cargo build` compiles without errors
- [ ] `agentchrome page screenshot --help` shows `--scroll-container` in output

**Notes**: Add the field after the existing `uid` field in the struct. No `value_enum` needed — it is a plain `String`.

---

## Phase 2: Backend Implementation

### T002: Add validation for --scroll-container flag combinations

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] Error returned when `--scroll-container` is used without `--full-page`
- [ ] Error returned when `--scroll-container` is combined with `--selector`, `--uid`, or `--clip`
- [ ] Existing validation for `--full-page` vs `--selector`/`--uid` is preserved
- [ ] Error messages match the format from `AppError::screenshot_failed()`
- [ ] Unit tests verify all invalid combinations

**Notes**: Add validation checks at the top of `execute_screenshot`, immediately after the existing mutual-exclusion check for `--full-page` vs `--selector`/`--uid`.

### T003: Implement get_container_scroll_dimensions helper

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] New async function `get_container_scroll_dimensions(managed, selector) -> Result<(f64, f64), AppError>`
- [ ] Uses `DOM.querySelector` to find the element (reusing the existing `resolve_selector_clip` pattern for DOM setup)
- [ ] Uses `Runtime.evaluate` to read `element.scrollWidth` and `element.scrollHeight`
- [ ] Returns `AppError::element_not_found(selector)` if element is not found
- [ ] Unit test for parsing the JS response

**Notes**: The JS expression should query the element by selector and return `JSON.stringify({ width: el.scrollWidth, height: el.scrollHeight })`. Use `Runtime.evaluate` with `returnByValue: true`.

### T004: Implement container style override and restore helpers

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] New async function `override_container_styles(managed, selector) -> Result<String, AppError>` that returns the saved-styles token
- [ ] The override JS walks from the matched element up to `document.documentElement`, saving each element's `style.cssText`, then sets `overflow: visible; height: auto; max-height: none` on each
- [ ] New async function `restore_container_styles(managed, saved_token) -> Result<(), AppError>` that restores original styles
- [ ] The restore JS parses the saved token and restores each element's `style.cssText`
- [ ] Unit tests verify the JS string generation

**Notes**: The saved-styles token is a JSON string returned from `Runtime.evaluate` containing an array of `{ selector_or_index, original_css_text }` pairs. The override script uses `JSON.stringify` to produce the token, and the restore script uses `JSON.parse` to consume it. The selector in the JS should use `document.querySelector(selector)` with proper escaping.

### T005: Implement auto-detection warning logic

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] After `get_page_dimensions` is called in the `--full-page` path (without `--scroll-container`), compare page dimensions to viewport dimensions
- [ ] If `page_h <= viewport_h`, emit a warning to stderr: `warning: full-page dimensions match viewport ({height}px). Content may be inside a scrollable container. Use --scroll-container <selector> to capture it.`
- [ ] Warning is a plain `eprintln!` (not a JSON error) — does not affect exit code
- [ ] Screenshot capture still proceeds normally after the warning
- [ ] Unit test not needed (integration/BDD covers it)

**Notes**: Get viewport dimensions via `get_viewport_dimensions` (already available from `super`). The comparison should use the height values since that is the dimension that matters for vertical scroll.

### T006: Add error constructor for scroll-container validation

**File(s)**: `src/error.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] No new error constructor needed if existing `screenshot_failed()` covers all error messages
- [ ] Verify that `AppError::screenshot_failed("--scroll-container requires --full-page")` and `AppError::element_not_found(selector)` produce correct error messages
- [ ] If a new constructor is warranted, add it with unit test

**Notes**: This task may result in no changes if existing constructors suffice. Review `src/error.rs` and confirm. The existing `screenshot_failed` and `element_not_found` constructors should be adequate.

---

## Phase 3: Integration

### T007: Integrate scroll-container capture path into execute_screenshot

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T002, T003, T004, T005
**Acceptance**:
- [ ] New branch in the capture strategy block: when `args.full_page && args.scroll_container.is_some()`
- [ ] Branch calls `get_container_scroll_dimensions` to get dimensions
- [ ] Branch calls `override_container_styles` before viewport expansion
- [ ] Branch calls `set_viewport_size` with container dimensions
- [ ] After capture, calls `restore_container_styles` then `clear_viewport_override` (in that order)
- [ ] Restoration runs even if capture fails (use a pattern that ensures cleanup)
- [ ] The `dimensions` tuple is set to the container scroll dimensions

**Notes**: Insert the new branch before the existing `args.full_page` branch in the if/else chain. The auto-detection warning (T005) belongs in the existing `args.full_page` branch (the else case when no `--scroll-container` is provided).

### T008: Wire up auto-detection warning in existing full-page path

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T005, T007
**Acceptance**:
- [ ] In the existing `args.full_page` branch (no `--scroll-container`), after `get_page_dimensions`, call `get_viewport_dimensions` and compare
- [ ] If dimensions match, emit the warning via `eprintln!`
- [ ] The warning does not alter the capture flow
- [ ] Enable `DOM` domain in the scroll-container path (needed for `DOM.querySelector`)

---

## Phase 4: Testing

### T009: Create test fixture HTML

**File(s)**: `tests/fixtures/full-page-screenshot-scrollable-containers.html`
**Type**: Create
**Depends**: None
**Acceptance**:
- [ ] HTML file with two test scenarios embedded:
  - Section 1: `body { overflow: hidden }` with `.main-content { overflow: auto; height: 100vh }` containing ~3000px of content (for AC1, AC3, AC7)
  - Section 2: Standard document-level scrolling with ~5000px of body content (for AC2)
- [ ] File is self-contained — no external dependencies, CDNs, or network requests
- [ ] HTML comment at top documents which ACs it covers
- [ ] Content includes visible markers (e.g., "TOP", "MIDDLE", "BOTTOM") for visual verification

**Notes**: The fixture may need to be two separate files or use URL hash navigation to switch between scenarios. Consider creating `tests/fixtures/full-page-screenshot-inner-scroll.html` for AC1/AC3/AC7 and reusing an existing standard page fixture for AC2.

### T010: Create BDD feature file

**File(s)**: `tests/features/full-page-screenshot-scrollable-containers.feature`
**Type**: Create
**Depends**: T007, T008
**Acceptance**:
- [ ] All 7 acceptance criteria from requirements.md are Gherkin scenarios
- [ ] Uses Given/When/Then format
- [ ] Feature description matches user story
- [ ] Valid Gherkin syntax
- [ ] Scenarios are independent (no shared mutable state)

### T011: Implement BDD step definitions

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T010
**Acceptance**:
- [ ] Step definitions added for all new Gherkin steps
- [ ] Steps follow existing cucumber-rs patterns in the file
- [ ] CLI invocation steps use the binary under test
- [ ] Assertion steps check stdout JSON and stderr content
- [ ] `cargo test --test bdd` passes (including new scenarios)

### T012: Add unit tests for new helper functions

**File(s)**: `src/page/screenshot.rs`
**Type**: Modify
**Depends**: T002, T003, T004
**Acceptance**:
- [ ] Unit tests for validation logic (T002): all invalid flag combinations
- [ ] Unit tests for JS response parsing in `get_container_scroll_dimensions` (T003)
- [ ] Unit tests for style override/restore JS string generation (T004)
- [ ] `cargo test --lib` passes

### T013: Manual smoke test against headless Chrome

**File(s)**: None (verification only)
**Type**: Verify
**Depends**: T007, T008, T009
**Acceptance**:
- [ ] Build: `cargo build` succeeds
- [ ] Launch: `./target/debug/agentchrome connect --launch --headless` succeeds
- [ ] Navigate to test fixture: `./target/debug/agentchrome navigate file://<path-to-fixture>`
- [ ] AC1 verified: `page screenshot --full-page --scroll-container ".main-content" --file /tmp/inner.png` produces a tall screenshot
- [ ] AC2 verified: `page screenshot --full-page --file /tmp/full.png` on standard page produces expected result
- [ ] AC3 verified: `page screenshot --full-page` on inner-scroll page emits warning to stderr
- [ ] AC4 verified: `page screenshot --full-page --scroll-container ".nonexistent"` fails with element not found
- [ ] AC5 verified: `page screenshot --scroll-container ".main-content"` fails with requires --full-page
- [ ] AC7 verified: viewport dimensions restored after scroll-container capture
- [ ] Cleanup: `./target/debug/agentchrome connect disconnect` and `pkill -f 'chrome.*--remote-debugging' || true`

---

## Dependency Graph

```
T001 ──┬──▶ T002 ──┐
       │           │
       └──▶ T003 ──┤
                   │
           T004 ──┤
                   │
           T005 ──┤
                   ├──▶ T007 ──▶ T008 ──┬──▶ T010 ──▶ T011
           T006 ──┘                     │
                                        ├──▶ T012
                                        │
                               T009 ──┬─┤
                                      │ │
                                      │ └──▶ T013
                                      │
                                      └──────────────
```

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #184 | 2026-04-16 | Initial feature spec |

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
