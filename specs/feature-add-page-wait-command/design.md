# Design: Add Page Wait Command

**Issues**: #163, #195
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude

---

## Overview

This feature adds a `page wait` subcommand that blocks until a user-specified condition is met on the current page. It supports six condition types: URL glob matching (`--url`), text content search (`--text`), CSS selector presence (`--selector`), network idle detection (`--network-idle`), arbitrary JavaScript expression evaluation (`--js-expression`), and element count threshold (`--selector` with `--count`). Exactly one condition must be specified per invocation; `--count` acts as a modifier to `--selector`.

The implementation follows the established page subcommand pattern: a `src/page/wait.rs` module with a `PageWaitArgs` struct in `src/cli/mod.rs`, dispatched through `src/page/mod.rs`. For `--url`, `--text`, `--selector`, and `--js-expression`, the command polls via `Runtime.evaluate` at a configurable interval (default 100ms). For `--network-idle`, it reuses the existing event-driven `wait_for_network_idle()` infrastructure from `src/navigate.rs`. All conditions check immediately before entering the wait loop to return instantly when already satisfied.

Issue #195 adds: (1) `--js-expression` as a new condition in the existing poll-based architecture, passing the user's expression directly to `Runtime.evaluate` and checking truthiness; (2) `--count` as a modifier that changes the `--selector` check from `querySelector !== null` to `querySelectorAll.length >= n`; (3) a reliability fix for intermittent exit code 1 by improving error discrimination in the polling loop — distinguishing transient CDP failures (retry silently) from persistent JavaScript exceptions (report after consecutive failures); (4) updated help text and examples.

---

## Architecture

### Component Diagram

```
CLI Layer (src/cli/mod.rs)
    │
    │  PageWaitArgs { url, text, selector, network_idle, js_expression, count, interval }
    │
    ▼
Page Dispatcher (src/page/mod.rs)
    │
    │  PageCommand::Wait(args) → wait::execute_wait(global, args, frame)
    │
    ▼
Wait Module (src/page/wait.rs)
    │
    ├─── Poll Loop (--url, --text, --selector, --js-expression)
    │       │
    │       ▼
    │    Runtime.evaluate  ──►  Chrome (JS evaluation)
    │       │
    │       ├── --url:       glob match against location.href
    │       ├── --text:      document.body.innerText.includes(text)
    │       ├── --selector:  querySelector !== null  (or querySelectorAll.length >= count)  ◄── ENHANCED
    │       └── --js-expression:  user expression → truthy check  ◄── NEW
    │
    └─── Event-Driven (--network-idle)
            │
            ▼
         wait_for_network_idle()  ◄── reused from src/navigate.rs
            │
            ├── Network.requestWillBeSent
            ├── Network.loadingFinished
            └── Network.loadingFailed
```

### Data Flow

```
1. CLI parses PageWaitArgs, validates exactly one condition flag is set
   (--js-expression added to condition group; --count requires --selector)
2. execute_wait() calls setup_session() to connect to Chrome
3. Enables Runtime domain (always), Network domain (if --network-idle)
4. Resolves optional frame context via --frame (applies to all conditions including new ones)
5. Performs immediate condition check:
   a. If condition already met → build result JSON, print, return Ok
   b. If not met → enter wait loop
6. Wait loop:
   a. Poll conditions: sleep(interval) → Runtime.evaluate → check result
      - For --js-expression: check exceptionDetails for persistent JS errors
      - Track consecutive eval failures; after 3 consecutive JS exceptions, exit with error
   b. Network idle: subscribe to Network events → wait_for_network_idle()
7. On match: get_page_info() → build WaitResult → print_output() → return Ok
8. On timeout: return AppError with ExitCode::TimeoutError (code 4)
9. On persistent JS error: return AppError with ExitCode::GeneralError (code 1)
```

---

## API / Interface Changes

### CLI Arguments: `PageWaitArgs` (amended)

```rust
/// Wait until a condition is met on the current page
#[derive(Args)]
#[command(arg_required_else_help = true)]
pub struct PageWaitArgs {
    /// Wait for the page URL to match a glob pattern
    #[arg(long, group = "condition")]
    pub url: Option<String>,

    /// Wait for text to appear in the page content
    #[arg(long, group = "condition")]
    pub text: Option<String>,

    /// Wait for a CSS selector to match an element in the DOM
    #[arg(long, group = "condition")]
    pub selector: Option<String>,

    /// Wait for network activity to settle (no requests for 500ms)
    #[arg(long, group = "condition")]
    pub network_idle: bool,

    /// Wait for a JavaScript expression to evaluate to a truthy value
    #[arg(long, group = "condition")]
    pub js_expression: Option<String>,

    /// Minimum number of elements that must match the selector (requires --selector)
    #[arg(long, requires = "selector", default_value = "1")]
    pub count: u64,

    /// Poll interval in milliseconds (for --url, --text, --selector, --js-expression)
    #[arg(long, default_value = "100")]
    pub interval: u64,
}
```

Changes from #163:
- Added `js_expression: Option<String>` with `group = "condition"` — new condition type
- Added `count: u64` with `requires = "selector"` and `default_value = "1"` — modifier for selector waits
- `--count` defaults to 1 (preserving existing presence-check behavior when omitted)

### Output Schema (amended)

**Success (stdout):**

```json
{
  "condition": "js-expression",
  "matched": true,
  "url": "https://example.com/wizard",
  "title": "Setup Wizard",
  "js_expression": "document.querySelector('.next-btn').disabled === false"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `condition` | `"url"` \| `"text"` \| `"selector"` \| `"network-idle"` \| `"js-expression"` | Which condition was checked |
| `matched` | `true` | Always true on success |
| `url` | String | Current page URL at time of match |
| `title` | String | Current page title at time of match |
| `pattern` | String (omitted if absent) | Glob pattern (for `--url`) |
| `text` | String (omitted if absent) | Search text (for `--text`) |
| `selector` | String (omitted if absent) | CSS selector (for `--selector`) |
| `js_expression` | String (omitted if absent) | JavaScript expression (for `--js-expression`) |
| `count` | u64 (omitted if absent) | Count threshold (present when `--count > 1` with `--selector`) |

**Expression Error (stderr) — NEW:**

```json
{"error": "JavaScript expression evaluation failed: SyntaxError: Unexpected token '('", "code": 1}
```

Uses existing `AppError` serialization. A new `js_eval_error()` constructor will be added.

---

## New Condition: `--js-expression` (src/page/wait.rs)

### Design

The `--js-expression` condition passes the user's expression string directly to `Runtime.evaluate` without any wrapping or encoding. The CDP `Runtime.evaluate` returns the expression's result, which is checked for truthiness.

**Truthiness check**: The returned value from `Runtime.evaluate` is truthy if:
- It is a boolean `true`
- It is a non-zero number
- It is a non-empty string
- It is a non-null object

This matches JavaScript truthiness semantics naturally since `Runtime.evaluate` returns the actual JS value.

### Error Handling for JS Expressions

The existing `eval_js()` function returns `None` on any failure, which is treated as "condition not met" by the poll loop. This is correct for transient CDP failures (page navigating) but incorrect for persistent JavaScript errors (syntax errors, reference errors). For `--js-expression`, we need to distinguish these cases.

**Approach**: Create a new `eval_js_checked()` function that returns richer error information:

```rust
enum EvalOutcome {
    /// Expression evaluated successfully, result value returned
    Value(serde_json::Value),
    /// Expression threw a JavaScript exception (SyntaxError, TypeError, etc.)
    JsException(String),
    /// CDP communication failed (page navigating, context destroyed, etc.)
    TransientError,
}
```

**Poll loop behavior for `--js-expression`**:
1. Call `eval_js_checked()` with the user's expression
2. On `Value(v)`: check truthiness. If truthy → success. If falsy → continue polling.
3. On `JsException(msg)`: increment consecutive error counter. If counter >= 3 → exit with `AppError::js_eval_error(msg)`.
4. On `TransientError`: reset error counter (transient failures are expected during navigation). Continue polling.
5. On `Value(_)` (any success, truthy or not): reset error counter.

The threshold of 3 consecutive JS exceptions ensures:
- A single transient evaluation failure doesn't immediately abort the wait
- A persistent syntax error or reference error is caught quickly (~300ms at default interval)
- The counter resets on any successful evaluation, handling intermittent errors gracefully

### Implementation

```
async fn poll_js_expression(global, managed, expression, timeout_ms, interval_ms):
    deadline = now() + timeout_ms
    consecutive_errors = 0

    // Immediate pre-check
    match eval_js_checked(managed, expression):
        Value(v) if is_truthy(v) → return success(expression)
        JsException(msg) → consecutive_errors += 1
        _ → ()

    loop:
        sleep(interval)
        if now() > deadline → return timeout_error(expression)
        match eval_js_checked(managed, expression):
            Value(v) if is_truthy(v):
                return success(expression)
            Value(_):
                consecutive_errors = 0  // falsy but valid — reset
            JsException(msg):
                consecutive_errors += 1
                if consecutive_errors >= 3:
                    return AppError::js_eval_error(msg)
            TransientError:
                consecutive_errors = 0  // transient — reset and retry
```

### Truthiness Helper

```rust
fn is_truthy(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Bool(b) => *b,
        serde_json::Value::Number(n) => n.as_f64().map_or(false, |f| f != 0.0),
        serde_json::Value::String(s) => !s.is_empty(),
        serde_json::Value::Null => false,
        serde_json::Value::Array(_) | serde_json::Value::Object(_) => true,
    }
}
```

---

## Enhanced Condition: `--selector` with `--count` (src/page/wait.rs)

### Design

When `--count` is provided (and > 1), the selector check changes from:
- **Current**: `document.querySelector(sel) !== null` (presence check)
- **Enhanced**: `document.querySelectorAll(sel).length >= count` (count threshold)

When `--count` is 1 (the default), behavior is identical to the existing presence check, maintaining backward compatibility.

### Implementation

The existing `check_selector_condition()` function is modified to accept an optional count parameter:

```rust
pub(crate) async fn check_selector_condition(
    managed: &ManagedSession,
    selector: &str,
    count: u64,
) -> bool {
    let encoded = serde_json::to_string(selector).unwrap_or_default();
    let expr = if count <= 1 {
        format!("document.querySelector({encoded}) !== null")
    } else {
        format!("document.querySelectorAll({encoded}).length >= {count}")
    };
    let Some(val) = eval_js(managed, &expr).await else {
        return false;
    };
    val.as_bool().unwrap_or(false)
}
```

The `poll_selector` function is updated to pass `args.count` through and to include `count` in the `WaitResult` output when count > 1.

---

## Reliability Fix (AC11/FR15)

### Root Cause Analysis

The intermittent exit code 1 issue is suspected to be caused by `eval_js()` returning `None` during transient CDP states (e.g., page context switches during polling). When `None` is returned, the condition check returns `false`, and the poll loop continues. If this happens on the first check (immediate pre-check) AND the page is in a transient state at that exact moment, the condition may never be re-evaluated as satisfied before timeout.

However, exit code 1 (GeneralError) is not a timeout — timeout would be exit code 4. Exit code 1 suggests an error is being thrown and caught somewhere in the setup path (session setup, domain enablement) rather than in the poll loop itself.

### Fix Strategy

1. **Investigate**: Check if the error originates from `setup_session()`, `ensure_domain()`, or the poll loop itself
2. **Guard session setup**: Add retry logic around domain enablement calls that can fail during page transitions
3. **Guard poll loop**: Ensure that transient `eval_js` failures in the immediate pre-check don't short-circuit to an error — they should fall through to the poll loop
4. **Add error context**: If an error does occur in setup, include diagnostic information about the page state

This fix will be investigated during implementation. The design reserves space for a setup retry mechanism if the root cause is in session/domain setup.

---

## Updated Output Types

### WaitResult (amended)

```rust
#[derive(Serialize)]
struct WaitResult {
    condition: String,
    matched: bool,
    url: String,
    title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pattern: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    selector: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    js_expression: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    count: Option<u64>,
}
```

Changes from #163:
- Added `js_expression: Option<String>` — present for `--js-expression` condition
- Added `count: Option<u64>` — present when `--count > 1` with `--selector`

### Plain text output (amended)

```
fn print_wait_plain(result: &WaitResult) {
    // ... existing fields ...
    if let Some(ref expr) = result.js_expression {
        println!("Expression: {expr}");
    }
    if let Some(count) = result.count {
        println!("Count:     {count}");
    }
}
```

---

## New Error Constructor

```rust
impl AppError {
    pub fn js_eval_error(js_message: &str) -> Self {
        Self {
            message: format!("JavaScript expression evaluation failed: {js_message}"),
            code: ExitCode::GeneralError,
            custom_json: None,
        }
    }
}
```

---

## Error Handling (amended)

### Error Cases

| Scenario | Error Message | Exit Code |
|----------|---------------|-----------|
| Timeout waiting for URL | `Wait timed out after 30000ms: url "*/dashboard*" not matched` | 4 |
| Timeout waiting for text | `Wait timed out after 3000ms: text "Products" not found` | 4 |
| Timeout waiting for selector | `Wait timed out after 30000ms: selector "#results-table" not found` | 4 |
| Timeout waiting for selector count | `Wait timed out after 30000ms: selector ".item" count >= 3 not reached` | 4 |
| Timeout waiting for network idle | `Wait timed out after 30000ms: network-idle` | 4 |
| Timeout waiting for JS expression | `Wait timed out after 30000ms: js-expression not truthy` | 4 |
| JS expression persistent error | `JavaScript expression evaluation failed: SyntaxError: Unexpected token '('` | 1 |
| Invalid glob pattern | `Invalid glob pattern: ...` | 1 |
| No condition specified | Clap validation error (structured JSON via existing interceptor) | 1 |
| Connection failure | Existing connection error path | 2 |

---

## Updated CLI Help Text

The `after_long_help` in the `Wait` variant's clap derive is updated:

```
EXAMPLES:
  # Wait for URL to match a glob pattern
  agentchrome page wait --url "*/dashboard*"

  # Wait for text to appear
  agentchrome page wait --text "Products"

  # Wait for a CSS selector to match
  agentchrome page wait --selector "#results-table"

  # Wait for at least 5 elements to match a selector
  agentchrome page wait --selector ".item" --count 5

  # Wait for network to settle
  agentchrome page wait --network-idle

  # Wait for a JavaScript expression to become truthy
  agentchrome page wait --js-expression "document.querySelector('.btn').disabled === false"

  # Wait for audio element to finish playing
  agentchrome page wait --js-expression "document.querySelector('audio').ended"

  # Custom timeout and poll interval
  agentchrome page wait --text "loaded" --timeout 5000 --interval 200
```

---

## External Dependencies

No new external dependencies. The `globset` crate (added in #163) continues to be used for URL matching. The `--js-expression` condition uses only `Runtime.evaluate` from CDP, which is already available.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: JS-only evaluation (existing)** | Run all condition checks entirely in JS, including glob matching | No new Rust dependency | No standard glob in JS; would need to inject a glob implementation or use regex | Retained from #163 |
| **B: `globset` crate for glob (existing)** | Use `globset` for URL pattern matching in Rust | Well-maintained, general-purpose, correct semantics for URLs | New dependency | **Selected** in #163 |
| **C: Wrap user expression in try-catch** | For `--js-expression`, wrap in `try { (expr) } catch(e) { null }` to catch errors in JS | Simpler Rust-side error handling | Masks all JS errors as falsy; user never learns expression is broken | Rejected — AC13 requires error reporting |
| **D: Return JS exception details via CDP** | Check `Runtime.evaluate` response for `exceptionDetails` field | Precise error discrimination; distinguishes syntax errors from falsy results | Slightly more complex `eval_js` variant needed | **Selected** for #195 |
| **E: Separate `--count` flag only** | `--count` as standalone condition (wait for N elements of any type) | Simpler argument model | Meaningless without a selector; would require its own CSS selector parameter | Rejected — `--count` modifies `--selector` |

---

## Security Considerations

- [x] **Input Validation**: `--url` glob pattern validated at parse time by `globset`; invalid patterns produce a clear error before any CDP interaction
- [x] **Input Validation**: `--text` and `--selector` are passed to `Runtime.evaluate` — text is embedded in a JS string literal and must be properly escaped to prevent injection. Use `serde_json::to_string()` to JSON-encode the text value before embedding in the JS expression
- [x] **Input Validation**: `--js-expression` is passed directly to `Runtime.evaluate` — this is intentional and equivalent to `js exec` which already allows arbitrary JS execution. No injection concern since the user controls the expression.
- [x] **Input Validation**: `--selector` is passed to `document.querySelector()` — CSS selectors are not an injection vector in this context, but malformed selectors will cause a JS exception that must be caught and reported
- [x] **No sensitive data**: The command only reads page state; it does not modify anything

---

## Performance Considerations

- [x] **Poll interval**: Default 100ms keeps CDP overhead low (10 calls/second) while providing responsive detection
- [x] **Immediate check**: Checking condition before entering the poll loop avoids a wasted 100ms sleep when the condition is already met
- [x] **Event-driven network idle**: No polling overhead for `--network-idle`; purely event-driven via CDP subscriptions
- [x] **Single JS evaluation**: Each poll iteration makes exactly one `Runtime.evaluate` call (for poll-based conditions)
- [x] **JS expression overhead**: `--js-expression` has the same poll overhead as other conditions; no additional wrapping or preprocessing of the expression

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI argument parsing | BDD | Validates condition group enforcement, default values, help text, `--count` requires `--selector` |
| Poll-based wait (--url, --text, --selector) | BDD | Condition match, timeout, immediate return when pre-satisfied |
| JS expression wait (--js-expression) | BDD | Truthy evaluation, timeout, immediate return, persistent error detection |
| Selector count (--selector --count) | BDD | Count threshold met, timeout, default count=1 backward compat |
| Event-driven wait (--network-idle) | BDD | Network settles, already idle, timeout |
| Error handling | BDD | Timeout messages, invalid glob, JS expression errors, no condition specified |
| Output format | BDD | JSON structure, field presence/absence, exit codes |
| Glob matching | Unit | Pattern edge cases (wildcard, literal, empty) |
| Truthiness check | Unit | All JS value types: bool, number, string, null, array, object |
| WaitResult serialization | Unit | New fields (js_expression, count) serialize correctly |

BDD scenarios will be defined in `tests/features/page-wait.feature` with step definitions in `tests/bdd.rs`.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `Runtime.evaluate` fails during polling (page navigating) | Medium | Low | Catch JS evaluation errors in poll loop; retry on next interval rather than failing immediately |
| Glob pattern semantics surprise users (e.g., `*` vs `**`) | Low | Low | Document that `*` matches across `/` in URLs; `literal_separator(false)` ensures intuitive behavior |
| High-frequency polling causes CDP backpressure | Low | Medium | Default 100ms interval is conservative; `--interval` allows tuning |
| `--text` check misses text in iframes | Low | Low | Documented as checking `document.body.innerText` (main frame only); iframe support via `--frame` |
| User JS expression has side effects | Low | Low | Documented: `--js-expression` evaluates the expression in page context. Same risk as `js exec`. |
| `--count` with very high values causes slow querySelectorAll | Low | Low | User controls the count value; large DOM queries are inherently slow regardless of agentchrome |
| Consecutive error threshold (3) too aggressive for slow pages | Low | Medium | Threshold only applies to JS *exceptions* (syntax/reference errors), not to transient CDP failures which reset the counter |

---

## Open Questions

- [x] Should `--network-idle` reuse `wait_for_network_idle()` directly? → Yes, direct reuse with no modifications needed
- [x] Which glob crate? → `globset` for URL-appropriate matching
- [x] Error threshold for `--js-expression`? → 3 consecutive JS exceptions triggers immediate error
- [x] Should `--count` default to 1 or be optional? → Default to 1 (backward compatible with existing presence check)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #163 | 2026-03-12 | Initial technical design |
| #195 | 2026-04-16 | Add `--js-expression` condition with error discrimination, `--count` modifier for `--selector`, reliability fix strategy, updated output schema and help text |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Architecture follows existing project patterns (page subcommand pattern per `structure.md`)
- [x] All API/interface changes documented with schemas (CLI args, output JSON)
- [x] Database/storage changes planned with migrations (N/A — no storage)
- [x] State management approach is clear (stateless command; poll or event-driven)
- [x] UI components and hierarchy defined (N/A — CLI only)
- [x] Security considerations addressed (JS injection prevention, input validation)
- [x] Performance impact analyzed (poll interval, immediate check, event-driven network idle)
- [x] Testing strategy defined (BDD + unit for glob, truthiness, serialization)
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
