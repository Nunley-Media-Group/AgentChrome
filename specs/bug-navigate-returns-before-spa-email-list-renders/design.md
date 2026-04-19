# Root Cause Analysis: navigate returns before SPA email list renders (add --wait-for-selector)

**Issue**: #178
**Date**: 2026-03-15
**Status**: Draft
**Author**: Claude

---

## Root Cause

The `navigate` command's `execute_url` function (`src/navigate.rs:115`) uses `WaitUntil::Load` as its default wait strategy, which resolves when Chrome fires `Page.loadEventFired`. For SPA sites like Outlook Web, this event fires as soon as the cached application shell is delivered — well before the React framework's async data fetch and virtual DOM rendering cycle populates dynamic content such as the email list (`[role="option"]` elements).

There is no mechanism to combine a navigation with a post-navigation DOM readiness check. The `page wait --selector` command (`src/page/wait.rs:100-110`) already implements CSS selector polling via `Runtime.evaluate`, but it requires a separate invocation — which means a separate CDP session connection — and cannot share the navigation's session or timeout context. This forces users into a two-command workflow (`navigate` then `page wait --selector`) with no guarantee that the timeout budget is coordinated.

The fix adds an optional `--wait-for-selector <CSS>` argument to `NavigateUrlArgs`. When provided, after the primary wait strategy completes, the navigate command polls for the selector using the same `document.querySelector` technique used by `page/wait.rs`, reusing the remaining timeout budget.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/cli/mod.rs` | 794-810 (`NavigateUrlArgs`) | Defines the navigate URL arguments; needs new `--wait-for-selector` field |
| `src/navigate.rs` | 115-203 (`execute_url`) | URL navigation logic; needs selector polling after primary wait strategy |
| `src/page/wait.rs` | 99-110 (`check_selector_condition`) | Existing selector polling logic to reuse |

### Triggering Conditions

- The target site is an SPA that renders dynamic content asynchronously after the page load event
- The cached app shell loads fast enough that `Page.loadEventFired` fires before async content renders
- The user expects specific DOM elements to be present when navigate returns
- There is no workaround in a single command invocation

---

## Fix Strategy

### Approach

Add an optional `--wait-for-selector` field to `NavigateUrlArgs` in the CLI module. In `execute_url`, after the primary wait strategy completes (load, domcontentloaded, networkidle, or none), if `--wait-for-selector` is provided, poll for the selector using `Runtime.evaluate` with `document.querySelector(selector) !== null` until the selector matches or the remaining timeout budget is exhausted.

The polling logic will be extracted from `page/wait.rs` into a reusable function (or called directly since `check_selector_condition` is already a standalone async function). The poll interval will be hardcoded at 100ms, matching the `page wait --selector` default.

The `Runtime` domain must be enabled before polling. Since `execute_url` already has a `ManagedSession`, it can call `managed.ensure_domain("Runtime")` before the polling loop.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/cli/mod.rs` | Add `wait_for_selector: Option<String>` field to `NavigateUrlArgs` with `#[arg(long)]` | Exposes the new flag to the CLI |
| `src/navigate.rs` | After the primary wait strategy block (lines ~177-189), add a selector polling loop when `args.wait_for_selector` is `Some(selector)`. Enable `Runtime` domain, compute remaining timeout, poll with 100ms interval. | Implements the post-navigation selector check |
| `src/page/wait.rs` | Make `check_selector_condition` `pub(crate)` (it is currently non-public) | Allows `navigate.rs` to reuse the existing selector check logic |

### Blast Radius

- **Direct impact**: `src/cli/mod.rs` (new field), `src/navigate.rs` (new polling block), `src/page/wait.rs` (visibility change)
- **Indirect impact**: None. The new field is optional and defaults to `None`. When not provided, the existing code path is unchanged — no selector polling occurs. The visibility change to `check_selector_condition` does not alter its behavior.
- **Risk level**: Low

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Default navigate behavior changes when `--wait-for-selector` is not used | Low | The field defaults to `None`; the polling block is gated by `if let Some(selector) = &args.wait_for_selector` — the existing code path is completely unchanged |
| Timeout calculation error causes premature timeout or infinite wait | Low | Use `Instant::now()` at the start of `execute_url` to compute remaining time after the primary wait completes; cap the selector poll timeout at `timeout_ms` minus elapsed time |
| Selector polling causes excessive CPU usage | Low | 100ms poll interval with `tokio::time::sleep` is lightweight; matches existing `page wait --selector` behavior |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Automatically detect SPA and switch wait strategy | Use heuristics to detect SPA frameworks and wait for content | Unreliable — different SPAs render differently; adds complexity; the generic flag is more predictable |
| Combine `navigate` + `page wait` in a shell pipeline | Tell users to run two commands | Requires two separate CDP sessions, timeout is not coordinated, user experience is poor for AI agents that chain commands |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #178 | 2026-03-15 | Initial defect spec |
