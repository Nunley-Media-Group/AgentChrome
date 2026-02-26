# Design: Form Submit Subcommand

**Issues**: #147
**Date**: 2026-02-26
**Status**: Draft
**Author**: Claude (nmg-sdlc)

---

## Overview

This design adds a `form submit` subcommand to the existing `form` command group. The implementation follows the established patterns in `src/form.rs` -- resolving a target element via UID or CSS selector, executing JavaScript on the resolved DOM node via `Runtime.callFunctionOn`, and returning structured JSON output. The key addition is form resolution logic (finding the parent `<form>` when the target is a child element) and optional navigation detection (following the pattern from `interact.rs` click handling).

The command uses `HTMLFormElement.requestSubmit()` rather than `HTMLFormElement.submit()` because `requestSubmit()` triggers browser validation and fires the `submit` event, matching what a real user click on a submit button would do. This aligns with the product principle that form submit should respect browser validation (stated in the issue's out-of-scope section).

---

## Architecture

### Component Diagram

```
CLI Layer (cli/mod.rs)
    │
    │  FormCommand::Submit(FormSubmitArgs)
    ▼
Command Dispatch (main.rs)
    │
    │  form::execute_form() match arm
    ▼
Form Module (form.rs)
    │
    │  execute_submit()
    ├──▶ setup_session()           [existing]
    ├──▶ resolve_to_object_id()    [existing]
    ├──▶ SUBMIT_JS via Runtime.callFunctionOn  [new]
    ├──▶ navigation detection      [new, follows interact.rs pattern]
    ├──▶ take_snapshot()           [existing, if --include-snapshot]
    └──▶ print output              [existing print_output()]
```

### Data Flow

```
1. User runs: agentchrome form submit <TARGET> [--include-snapshot]
2. CLI layer parses args into FormSubmitArgs { target, include_snapshot }
3. main.rs dispatches to form::execute_form()
4. execute_form() matches FormCommand::Submit → execute_submit()
5. execute_submit():
   a. Sets up CDP session (setup_session)
   b. Enables DOM, Runtime, Page domains
   c. Resolves target to Runtime object ID (resolve_to_object_id)
   d. Subscribes to Page.frameNavigated event
   e. Calls SUBMIT_JS on the object via Runtime.callFunctionOn
      - JS finds the <form> (self or closest ancestor)
      - If no form found, returns { found: false }
      - If form found, calls form.requestSubmit(), returns { found: true }
   f. Waits briefly (100ms) for navigation event
   g. Checks if navigation occurred via try_recv()
   h. Gets current URL via Runtime.evaluate
   i. Optionally takes snapshot
   j. Returns JSON result
```

---

## API / Interface Changes

### New CLI Variant

| Variant | Type | Purpose |
|---------|------|---------|
| `FormCommand::Submit(FormSubmitArgs)` | Subcommand | Submit a form by targeting a form element or child element |

### CLI Arguments: `FormSubmitArgs`

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `target` | `String` | Yes | UID (e.g., `s5`) or CSS selector (e.g., `css:#login-form`) |
| `--include-snapshot` | `bool` | No | Include updated accessibility snapshot in output |

### Output Schema

**Success (no navigation):**
```json
{
  "submitted": "s5"
}
```

**Success (with navigation):**
```json
{
  "submitted": "s5",
  "url": "https://example.com/dashboard"
}
```

**Success (with snapshot):**
```json
{
  "submitted": "s5",
  "snapshot": { "role": "document", ... }
}
```

**Success (with navigation and snapshot):**
```json
{
  "submitted": "s5",
  "url": "https://example.com/dashboard",
  "snapshot": { "role": "document", ... }
}
```

**Plain text output:**
```
Submitted s5
```

**Errors:**

| Condition | Error Message Pattern | Exit Code |
|-----------|----------------------|-----------|
| Target not found | `UID 'sN' not found` / `Element not found for selector: X` | 1 (GeneralError) |
| Target not in a form | `No form found for target: X` | 1 (GeneralError) |
| Submit dispatch failed | `Interaction failed (submit): reason` | 5 (ProtocolError) |

---

## New Error Constructor

A new `not_in_form` error constructor will be added to `AppError` in `src/error.rs`:

```rust
pub fn not_in_form(target: &str) -> Self {
    Self {
        message: format!("No form found for target: {target}"),
        code: ExitCode::GeneralError,
        custom_json: None,
    }
}
```

This follows the pattern of existing target-specific errors like `not_file_input()`.

---

## JavaScript Strategy

### SUBMIT_JS

```javascript
function() {
    const el = this;
    const form = el.tagName.toLowerCase() === 'form'
        ? el
        : el.closest('form');
    if (!form) {
        return { found: false };
    }
    form.requestSubmit();
    return { found: true };
}
```

Key design decisions:
- Uses `el.closest('form')` for ancestor resolution -- standard DOM API, handles arbitrary nesting depth
- Uses `requestSubmit()` instead of `submit()` because `requestSubmit()`:
  - Fires the `submit` event (so JS handlers run)
  - Triggers HTML5 constraint validation (so required fields, patterns, etc. are checked)
  - Matches the behavior of clicking a submit button
- Returns a JSON object with `found` flag so Rust code can distinguish "no form" from "submit succeeded"

---

## Navigation Detection

Follows the established pattern from `interact.rs` click handling (lines 1345-1412):

1. Subscribe to `Page.frameNavigated` before calling SUBMIT_JS
2. After submit, sleep 100ms for opportunistic navigation detection
3. Use `try_recv()` to check if navigation event was captured
4. Always get the current URL via `Runtime.evaluate("window.location.href")`
5. Include `url` in output only if navigation was detected

This is intentionally opportunistic -- form submissions that trigger AJAX requests without navigation will not report a URL change, which is correct behavior.

---

## State Management

No new persistent state is introduced. The command follows the existing per-invocation session pattern:
- Connect to Chrome, create session, execute command, return result
- Snapshot state is updated only if `--include-snapshot` is used (via existing `take_snapshot()`)

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: `form.submit()` JS call** | Use the DOM `submit()` method | Simpler, no validation | Skips browser validation, doesn't fire submit event | Rejected -- doesn't match real user behavior |
| **B: `form.requestSubmit()` JS call** | Use the newer `requestSubmit()` method | Fires submit event, triggers validation, matches user click | Requires Chrome 76+ (universally available now) | **Selected** |
| **C: Click the submit button** | Find and click `[type=submit]` or first `<button>` | Most realistic user simulation | Complex button discovery, fails for forms with no visible submit button | Rejected -- the whole point of this command is to avoid needing a submit button |
| **D: `Input.dispatchKeyEvent` Enter** | Simulate pressing Enter | Simple | Only works when a form field is focused; unreliable | Rejected -- workaround the command replaces |

---

## Security Considerations

- [x] **Input Validation**: Target string validated as UID or CSS selector by existing `resolve_target_to_backend_node_id()`
- [x] **No injection risk**: JavaScript is a static const string, not interpolated from user input; target is resolved via CDP node ID
- [x] **No new privileges**: Uses same CDP domains already used by form fill/clear

---

## Performance Considerations

- [x] **Single CDP round-trip** for the submit call (plus existing session setup overhead)
- [x] **100ms navigation detection wait** is bounded and non-blocking for the caller
- [x] **No new domain enablement** beyond what's already required (DOM, Runtime, Page)

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Unit (form.rs) | `#[test]` | SubmitResult serialization, plain text output |
| BDD CLI | Gherkin + cucumber-rs | Argument validation (AC8, AC9, AC10), help text |
| BDD Chrome | Gherkin (commented) | Submit by form UID, submit by child element, no-form error, navigation detection |
| Smoke Test | Manual | Submit SauceDemo login form, verify navigation |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `requestSubmit()` not supported on very old Chrome | Low | Low | Chrome 76+ universally supports it; agentchrome already requires modern Chrome |
| Navigation detection misses fast navigations | Low | Low | 100ms wait follows proven pattern from click handler; URL is always returned |
| Form validation blocks submit silently | Medium | Low | This is correct behavior per requirements -- submit respects validation |

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #147 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] State management approach is clear (no new state)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
