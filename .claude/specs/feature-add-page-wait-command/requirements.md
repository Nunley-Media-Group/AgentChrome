# Requirements: Add Page Wait Command

**Issues**: #163, #195
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude

---

## User Story

**As an** AI agent automating multi-step browser workflows
**I want** a standalone command to wait until a specified condition is met
**So that** I can reliably synchronize with page state changes without arbitrary sleeps or polling loops

---

## Background

When automating SPAs or any dynamic web content, agents need to wait for the page to reach a certain state before proceeding — after form submissions, AJAX requests, page transitions, or async content loads. Currently, agents have no built-in way to wait; the workaround is a poll loop (`page snapshot` -> check -> sleep -> repeat), which wastes commands, tokens, and time.

Issue #148 adds `--wait-until` to `interact click`, handling the "click then wait" case. This feature adds a standalone `page wait` command for waiting independently of any click — after `form submit`, after `js exec`, after `navigate`, or simply when waiting for async content.

Issue #195 extends the wait command with two additional condition types: arbitrary JavaScript expression evaluation (`--js-expression`) and element count thresholds (`--count` modifier for `--selector`). Users report using `sleep 3` constantly because existing conditions (URL match, text match, selector exists, network idle) don't cover common dynamic state changes like slide transitions, audio completion, button state changes, and dynamic content loading. Additionally, issue #195 addresses an intermittent exit code 1 reliability issue where `page wait` occasionally fails even though the page has loaded.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Wait for URL to match a glob pattern

**Given** a connected Chrome session where the current URL is `https://example.com/login`
**When** I run `agentchrome page wait --url "*/dashboard*"` and the URL changes to `https://example.com/dashboard`
**Then** the command returns successfully with structured JSON containing the matched URL and the condition that was satisfied

**Example**:
- Given: Chrome connected, page at `https://example.com/login`
- When: `agentchrome page wait --url "*/dashboard*"` and navigation occurs
- Then: JSON output `{"condition": "url", "matched": true, "url": "https://example.com/dashboard", "title": "Dashboard"}`

### AC2: Wait for text to appear on page

**Given** a connected Chrome session on a page that is loading content asynchronously
**When** I run `agentchrome page wait --text "Products"` and the text "Products" appears in the page content
**Then** the command returns successfully with structured JSON indicating the text was found

**Example**:
- Given: Chrome connected, page loading async content
- When: `agentchrome page wait --text "Products"`
- Then: JSON output `{"condition": "text", "matched": true, "text": "Products", "url": "https://example.com/products", "title": "Product Listing"}`

### AC3: Wait for network idle

**Given** a connected Chrome session on a page with active network requests
**When** I run `agentchrome page wait --network-idle`
**Then** the command returns once there have been no active network requests for 500ms, with structured JSON confirming network idle state

**Example**:
- Given: Chrome connected, page has active XHR requests
- When: `agentchrome page wait --network-idle`
- Then: JSON output `{"condition": "network-idle", "matched": true, "url": "https://example.com/data", "title": "Data Page"}`

### AC4: Wait for CSS selector to match an element in the DOM

**Given** a connected Chrome session on a page where an element does not yet exist
**When** I run `agentchrome page wait --selector "#results-table"` and the element appears in the DOM
**Then** the command returns successfully with structured JSON indicating the selector matched

**Example**:
- Given: Chrome connected, `#results-table` not yet in DOM
- When: `agentchrome page wait --selector "#results-table"` and JS creates the element
- Then: JSON output `{"condition": "selector", "matched": true, "selector": "#results-table", "url": "https://example.com/search", "title": "Search"}`

### AC5: Wait times out with descriptive error

**Given** a connected Chrome session
**When** I run `agentchrome page wait --text "never-appearing-text" --timeout 3000` and the text never appears within 3 seconds
**Then** the command exits with timeout error (exit code 4) and a structured JSON error on stderr indicating the condition was not met and the timeout duration

**Example**:
- Given: Chrome connected
- When: `agentchrome page wait --text "never-appearing-text" --timeout 3000`
- Then: Exit code 4, stderr: `{"error": "Wait timed out after 3000ms: text \"never-appearing-text\" not found", "code": 4}`

### AC6: Network idle returns immediately when network is already idle

**Given** a connected Chrome session on a fully loaded page with no active network requests
**When** I run `agentchrome page wait --network-idle`
**Then** the command returns within the idle detection window (500ms) without waiting for the full timeout, confirming the network was already idle

### AC7: Condition already satisfied returns immediately

**Given** a connected Chrome session on a page where the URL already matches `*/dashboard*`
**When** I run `agentchrome page wait --url "*/dashboard*"`
**Then** the command checks the condition immediately on startup and returns without further polling, because the condition is already met

### AC8: Exactly one condition must be specified

**Given** a terminal with agentchrome available
**When** I run `agentchrome page wait` with no condition flags (no `--url`, `--text`, `--selector`, `--network-idle`, or `--js-expression`)
**Then** the command exits with a validation error (exit code 1) indicating that exactly one condition is required
**And** the error is structured JSON on stderr matching the project error contract

### AC9: Wait for JavaScript expression to evaluate to truthy

**Given** a connected Chrome session on a page with a disabled button that becomes enabled after an async operation
**When** I run `agentchrome page wait --js-expression "document.querySelector('.next-btn').disabled === false"`
**Then** the command blocks, polling the expression via `Runtime.evaluate`, until the expression evaluates to a truthy value, then returns structured JSON with the condition type and matched status

**Example**:
- Given: Chrome connected, `.next-btn` exists but is disabled
- When: `agentchrome page wait --js-expression "document.querySelector('.next-btn').disabled === false"`
- Then: JSON output `{"condition": "js-expression", "matched": true, "js_expression": "document.querySelector('.next-btn').disabled === false", "url": "https://example.com/wizard", "title": "Setup Wizard"}`

### AC10: Wait for selector count to reach minimum threshold

**Given** a connected Chrome session on a page where items are loading dynamically
**When** I run `agentchrome page wait --selector ".item" --count 3`
**Then** the command blocks until at least 3 elements match the selector `.item`, then returns structured JSON including the selector and the count threshold

**Example**:
- Given: Chrome connected, page has 1 `.item` element, more are loading
- When: `agentchrome page wait --selector ".item" --count 3`
- Then: JSON output `{"condition": "selector", "matched": true, "selector": ".item", "count": 3, "url": "https://example.com/items", "title": "Item List"}`

### AC11: Reliability fix for page load detection

**Given** a page that has finished loading (document ready state is "complete" and no pending network requests)
**When** `page wait` is run with any poll-based condition that is already satisfied
**Then** the command exits with code 0 reliably, with no intermittent exit code 1 failures due to race conditions in the polling logic

### AC12: Frame-scoped wait with new conditions

**Given** a page with an iframe containing dynamic content and `--frame 0` is specified
**When** I run `agentchrome page wait --js-expression "document.getElementById('status').textContent === 'ready'" --frame 0`
**Then** the JavaScript expression is evaluated within the specified frame context, not the main frame

### AC13: JavaScript expression evaluation error produces clear error

**Given** a connected Chrome session
**When** I run `agentchrome page wait --js-expression "this.is.not.valid.syntax((("` and the expression throws a JavaScript error on every poll attempt
**Then** the command does not silently treat the error as a falsy result forever; instead it exits with a descriptive error (exit code 1) indicating the expression failed to evaluate, including the JavaScript error message

### AC14: Documentation updated with new condition examples

**Given** the enhanced `page wait` command with `--js-expression` and `--count` support
**When** `page wait --help` is run or the CLI help text is consulted
**Then** examples for JavaScript expression waiting and selector count waiting are included alongside existing examples

### Generated Gherkin Preview

```gherkin
Feature: Page Wait Command
  As an AI agent automating multi-step browser workflows
  I want a standalone command to wait until a specified condition is met
  So that I can reliably synchronize with page state changes

  Scenario: Wait for URL to match a glob pattern
    Given a connected Chrome session at "https://example.com/login"
    When I run page wait with --url "*/dashboard*"
    And the URL changes to "https://example.com/dashboard"
    Then the command succeeds with JSON containing "condition" "url" and "matched" true

  Scenario: Wait for text to appear on page
    Given a connected Chrome session with async loading content
    When I run page wait with --text "Products"
    And the text "Products" appears on the page
    Then the command succeeds with JSON containing "condition" "text" and "matched" true

  Scenario: Wait for network idle
    Given a connected Chrome session with active network requests
    When I run page wait with --network-idle
    And network requests complete and remain idle for 500ms
    Then the command succeeds with JSON containing "condition" "network-idle" and "matched" true

  Scenario: Wait for CSS selector to match
    Given a connected Chrome session where "#results-table" does not exist
    When I run page wait with --selector "#results-table"
    And the element "#results-table" appears in the DOM
    Then the command succeeds with JSON containing "condition" "selector" and "matched" true

  Scenario: Wait times out
    Given a connected Chrome session
    When I run page wait with --text "never-appearing-text" --timeout 3000
    And the text never appears within 3000ms
    Then the command fails with exit code 4
    And stderr contains a timeout error mentioning "never-appearing-text"

  Scenario: Network idle returns immediately when already idle
    Given a connected Chrome session on a fully loaded page
    When I run page wait with --network-idle
    Then the command returns within 1000ms

  Scenario: Condition already satisfied returns immediately
    Given a connected Chrome session at "https://example.com/dashboard"
    When I run page wait with --url "*/dashboard*"
    Then the command returns immediately with the matched URL

  Scenario: No condition specified
    Given a terminal with agentchrome available
    When I run page wait with no condition flags
    Then the command fails with exit code 1
    And stderr contains a structured JSON error

  Scenario: Wait for JavaScript expression to evaluate to truthy
    Given a connected Chrome session on a page with a disabled button ".next-btn"
    When I run page wait with --js-expression "document.querySelector('.next-btn').disabled === false"
    And the button becomes enabled
    Then the command succeeds with JSON containing "condition" "js-expression" and "matched" true
    And the JSON has "js_expression" containing the original expression

  Scenario: Wait for selector count to reach minimum threshold
    Given a connected Chrome session on a page with 1 element matching ".item"
    When I run page wait with --selector ".item" --count 3
    And 2 more ".item" elements are added to the DOM
    Then the command succeeds with JSON containing "condition" "selector" and "matched" true
    And the JSON has "count" equal to 3

  Scenario: Page wait exits reliably when condition is met
    Given a connected Chrome session on a fully loaded page with text "Welcome"
    When I run page wait with --text "Welcome"
    Then the command exits with code 0
    And the command does not intermittently return exit code 1

  Scenario: Frame-scoped wait with JavaScript expression
    Given a connected Chrome session on a page with an iframe
    When I run page wait with --js-expression "document.getElementById('status').textContent === 'ready'" --frame 0
    Then the expression is evaluated in the iframe context

  Scenario: JavaScript expression evaluation error
    Given a connected Chrome session
    When I run page wait with --js-expression "this.is.not.valid.syntax(((" --timeout 3000
    Then the command fails with a descriptive error about expression evaluation failure
    And the error includes the JavaScript error message

  Scenario: Help text includes new condition examples
    Given a terminal with agentchrome available
    When I run page wait --help
    Then the help text includes an example for --js-expression
    And the help text includes an example for --count
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Add `Wait` variant to `PageCommand` enum with `PageWaitArgs` struct | Must | Follows existing page subcommand pattern |
| FR2 | Add `--url <glob>` condition flag for URL glob pattern matching | Must | Use glob matching (e.g., `*/dashboard*`) |
| FR3 | Add `--text <string>` condition flag for page text content matching | Must | Poll via `Runtime.evaluate` with `document.body.innerText.includes(text)` |
| FR4 | Add `--network-idle` boolean flag reusing existing `wait_for_network_idle()` infrastructure | Must | Same 500ms idle threshold as navigate |
| FR5 | Add `--selector <css>` condition flag for DOM element existence | Should | Poll via `Runtime.evaluate` with `document.querySelector(selector) !== null` |
| FR6 | Respect `--timeout` global option for maximum wait duration (default: 30000ms) | Must | Matching navigate timeout default |
| FR7 | Return structured JSON output with condition type, match status, current URL, and title | Must | Follow project JSON output contract on stdout |
| FR8 | Exit with code 4 (TimeoutError) when condition is not met within timeout | Must | Reuse existing `AppError` timeout pattern |
| FR9 | Check condition immediately before entering poll loop; return instantly if already satisfied | Must | Avoids unnecessary waiting when condition is pre-met |
| FR10 | Require exactly one condition flag via clap argument group validation | Must | Error output must be structured JSON per project error contract |
| FR11 | Add `--interval <ms>` option for configurable poll interval (default: 100ms) | Could | Applies to --url, --text, --selector, --js-expression polling; --network-idle is event-driven |
| FR12 | Output structured JSON error on stderr for all error conditions | Must | Single JSON error object per invocation |
| FR13 | Add `--js-expression <string>` condition flag for arbitrary JavaScript expression evaluation | Must | Poll via `Runtime.evaluate`; condition met when expression evaluates to truthy value |
| FR14 | Add `--count <n>` modifier for `--selector` that waits for at least N matching elements | Must | Only valid with `--selector`; poll via `document.querySelectorAll(sel).length >= n` |
| FR15 | Fix intermittent exit code 1 on loaded pages in poll-based wait conditions | Must | Investigate and resolve race condition in polling logic that causes spurious failures |
| FR16 | Extend `--frame` support to `--js-expression` and `--count` conditions | Should | Uses existing frame resolution infrastructure via `PageArgs.frame` |
| FR17 | Composable conditions: allow multiple conditions to be combined (e.g., wait for expression AND selector) | Could | Deferred — noted as potential follow-up |
| FR18 | Update `page wait --help` text and built-in examples to include `--js-expression` and `--count` examples | Must | Inline help via `after_long_help` in clap derive |
| FR19 | BDD test scenarios covering `--js-expression`, `--count`, reliability fix, and frame-scoped new conditions | Must | In `tests/features/page-wait.feature` |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Polling conditions (--url, --text, --selector, --js-expression) must use configurable interval (default 100ms); --network-idle is event-driven with no polling overhead |
| **Reliability** | Each polling probe must complete within the CDP command timeout; a stuck probe must not consume the entire wait timeout. JS expression evaluation errors must be detected and reported after consistent failure, not masked as falsy |
| **Platforms** | macOS, Linux, Windows (same as all agentchrome commands) |
| **Output contract** | JSON on stdout for success, JSON on stderr for errors, exit codes per project convention |

---

## UI/UX Requirements

| Element | Requirement |
|---------|-------------|
| **CLI help** | `agentchrome page wait --help` displays all condition flags with descriptions and defaults, including `--js-expression` and `--count` |
| **Error messages** | Timeout errors include the condition type and value that was being waited for; JS expression errors include the JavaScript error message |
| **Flag naming** | `--url`, `--text`, `--selector`, `--network-idle`, `--js-expression`, `--count`, `--interval` — verified no collision with global flags (`--timeout`, `--port`, `--host`, `--config`, `--pretty`, `--no-color`) |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `--url` | String (glob pattern) | Non-empty string; valid glob syntax | One of --url/--text/--selector/--network-idle/--js-expression required |
| `--text` | String | Non-empty string | One of --url/--text/--selector/--network-idle/--js-expression required |
| `--selector` | String (CSS selector) | Non-empty string | One of --url/--text/--selector/--network-idle/--js-expression required |
| `--network-idle` | Boolean flag | Presence-based | One of --url/--text/--selector/--network-idle/--js-expression required |
| `--js-expression` | String (JavaScript) | Non-empty string; must be a valid JS expression | One of --url/--text/--selector/--network-idle/--js-expression required |
| `--count` | u64 | > 0; only valid when `--selector` is also provided | No (default: 1, meaning presence check) |
| `--interval` | u64 (milliseconds) | > 0 | No (default: 100) |
| `--timeout` | u64 (milliseconds) | > 0 (global option) | No (default: 30000) |

### Output Data (Success -- stdout)

| Field | Type | Description |
|-------|------|-------------|
| `condition` | String | The condition type: `"url"`, `"text"`, `"selector"`, `"network-idle"`, or `"js-expression"` |
| `matched` | Boolean | Always `true` on success |
| `url` | String | Current page URL at time of match |
| `title` | String | Current page title at time of match |
| `pattern` | String (omitted if absent) | The glob pattern (present for --url) |
| `text` | String (omitted if absent) | The search text (present for --text) |
| `selector` | String (omitted if absent) | The CSS selector (present for --selector) |
| `js_expression` | String (omitted if absent) | The JavaScript expression (present for --js-expression) |
| `count` | u64 (omitted if absent) | The count threshold (present when --count is used with --selector) |

### Output Data (Timeout Error -- stderr)

| Field | Type | Description |
|-------|------|-------------|
| `error` | String | Descriptive message including condition type, value, and timeout duration |
| `code` | Integer | Exit code 4 (TimeoutError) |

### Output Data (Expression Error -- stderr)

| Field | Type | Description |
|-------|------|-------------|
| `error` | String | Descriptive message including the JavaScript error message from the failed evaluation |
| `code` | Integer | Exit code 1 (GeneralError) |

---

## Dependencies

### Internal Dependencies
- [x] `wait_for_network_idle()` helper in `src/navigate.rs` — reuse for `--network-idle`
- [x] `setup_session()` / `cdp_config()` in `src/page/mod.rs` — reuse session setup pattern
- [x] `get_page_info()` in `src/page/mod.rs` — reuse for URL/title in output
- [x] `AppError` / `ExitCode` in `src/error.rs` — reuse error types
- [x] `print_output()` in `src/page/mod.rs` — reuse JSON output helper
- [x] `eval_js()` in `src/page/wait.rs` — reuse for `--js-expression` evaluation
- [x] Frame resolution in `agentchrome::frame` — reuse for `--frame` with new conditions

### External Dependencies
- [x] `globset` crate for URL pattern matching (added in #163)

### Blocked By
- None — all infrastructure exists

---

## Out of Scope

- Combining multiple conditions with AND/OR logic (tracked as FR17 Could-priority for potential follow-up)
- Waiting for element visibility or interactability beyond DOM presence/count
- Replacing `--wait-until` on `navigate` or `interact click`
- Waiting for specific network request URL patterns
- Custom polling interval configuration beyond existing `--interval` flag
- Wait for visual change detection (screenshot diffing)
- `--count` with conditions other than `--selector` (count only applies to selector matching)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Command latency overhead | < 10ms beyond actual wait time | Time between condition match and command exit |
| Poll efficiency | <= 10 CDP calls/second at default interval | Count `Runtime.evaluate` calls per second during polling |
| Reliability | 0 intermittent failures on pre-satisfied conditions | Run 100 sequential waits on a loaded page; all must exit code 0 |

---

## Open Questions

- [x] Use glob for URL matching? -> Yes, per issue recommendation
- [x] Should `--network-idle` reuse `wait_for_network_idle()` directly? -> Yes, direct reuse
- [x] How should `--count` interact with `--selector`? -> `--count` is a modifier flag; only valid with `--selector`; defaults to 1 (existing presence behavior)
- [x] Should JS expression errors be treated as timeout or immediate error? -> Consecutive evaluation failures (e.g., 3+ in a row) produce an immediate error (exit code 1), not a timeout. Transient errors during page navigation are retried.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #163 | 2026-03-11 | Initial feature spec |
| #195 | 2026-04-16 | Add JS expression condition (AC9), selector count (AC10), reliability fix (AC11), frame-scoped new conditions (AC12), expression error handling (AC13), documentation (AC14), and corresponding FRs (FR13-FR19) |

---

## Validation Checklist

Before moving to PLAN phase:

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified (AC5: timeout, AC6: already idle, AC7: already satisfied, AC8: no condition, AC11: reliability, AC13: expression error)
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented
