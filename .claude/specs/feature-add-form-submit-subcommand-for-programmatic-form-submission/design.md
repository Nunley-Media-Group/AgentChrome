# Design: Form Submit Subcommand

**Issues**: #147
**Date**: 2026-02-26
**Status**: Draft
**Author**: Claude (nmg-sdlc)

---

## Overview

This feature adds a `form submit` subcommand to the existing `form` command group. The implementation follows the same architectural patterns established by `form fill`, `form clear`, and `form upload`: a clap-derived CLI args struct, a Serialize output type, session setup via `setup_session()`, target resolution via `resolve_target_to_backend_node_id()`, and JavaScript execution via `Runtime.callFunctionOn`.

The key technical decisions are: (1) using `HTMLFormElement.requestSubmit()` as the submit mechanism to respect browser validation, (2) resolving parent forms via `element.closest('form')` when the target is an element inside a form rather than the form itself, and (3) detecting post-submit navigation using the same `Page.frameNavigated` subscription pattern used by `interact click`.

---

## Architecture

### Component Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    CLI Layer                               │
│  cli/mod.rs: FormCommand::Submit(FormSubmitArgs)          │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────┐
│                    Command Module                          │
│  form.rs: execute_submit()                                │
│    1. setup_session()                                     │
│    2. resolve_target_to_backend_node_id()                 │
│    3. resolve_to_object_id()                              │
│    4. FIND_FORM_JS → closest('form') or self              │
│    5. subscribe(Page.frameNavigated)                      │
│    6. SUBMIT_JS → form.requestSubmit()                    │
│    7. Grace period → check navigation                     │
│    8. Build SubmitResult → print_output()                 │
└──────────────────────────────┬─────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────┐
│                    CDP Client                              │
│  Runtime.callFunctionOn (JS execution)                    │
│  DOM.resolveNode (target resolution)                      │
│  Page.frameNavigated (navigation detection)               │
└──────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User runs: agentchrome form submit <TARGET> [--include-snapshot]
2. CLI layer parses args into FormSubmitArgs { target, include_snapshot }
3. main.rs dispatches to form::execute_form() → FormCommand::Submit
4. execute_submit() sets up CDP session via setup_session()
5. Target resolved to backend node ID → object ID via existing helpers
6. FIND_FORM_JS runs on the element:
   - If element is a <form>, returns its object ID
   - If element is inside a <form>, returns closest('form') object ID
   - If neither, throws error → caught and mapped to AppError
7. Subscribe to Page.frameNavigated before submitting
8. Record pre-submit URL via get_current_url()
9. SUBMIT_JS calls form.requestSubmit() on the resolved form
10. 100ms grace period, then check for frameNavigated event
11. If navigated: get post-submit URL
12. If --include-snapshot: take_snapshot()
13. Build SubmitResult, serialize to JSON, print to stdout
```

---

## API / Interface Changes

### New CLI Subcommand

| Command | Type | Purpose |
|---------|------|---------|
| `form submit <TARGET> [--include-snapshot]` | CLI subcommand | Submit a form by target UID or CSS selector |

### CLI Args Schema

```rust
/// Arguments for `form submit`.
pub struct FormSubmitArgs {
    /// Target element (UID like 's1' or CSS selector like 'css:#login-form')
    pub target: String,

    /// Include updated accessibility snapshot in output
    pub include_snapshot: bool,
}
```

### Output Schema

**Success (no navigation):**
```json
{
  "submitted": "s3"
}
```

**Success (with navigation):**
```json
{
  "submitted": "s3",
  "url": "https://example.com/dashboard"
}
```

**Success (with snapshot):**
```json
{
  "submitted": "s3",
  "snapshot": { ... }
}
```

**Error (not in form):**
```json
{
  "error": "Target element is not a form and is not inside a form: s7",
  "code": 3
}
```

### Errors

| Code | Condition |
|------|-----------|
| ExitCode::TargetError (3) | Target element not found (existing) |
| ExitCode::TargetError (3) | Target element is not in a form (new) |
| ExitCode::GeneralError (1) | Submit failed (JS execution error) |

---

## State Management

No new persistent state. The command is stateless between invocations, following the same pattern as all other form subcommands. The only state interaction is:

- **Read**: Snapshot state file (for UID resolution, existing behavior)
- **Write**: Snapshot state file (only if `--include-snapshot`, existing behavior via `take_snapshot()`)

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: `form.submit()`** | Call the native `form.submit()` method | Simple, one-liner | Bypasses browser validation, does not fire submit event handlers | Rejected — issue explicitly says "submit should respect browser validation" |
| **B: `form.requestSubmit()`** | Call `form.requestSubmit()` | Respects validation, fires submit event, standard API | Requires Chrome 76+ (not a concern for CDP users) | **Selected** |
| **C: Dispatch `SubmitEvent` manually** | Create and dispatch a `SubmitEvent` | Full control over event | Does not trigger actual form submission/navigation; just fires the event | Rejected — need the actual submission behavior |

---

## Security Considerations

- [x] **Input Validation**: Target string validated by existing `is_uid()` / `is_css_selector()` functions
- [x] **No new attack surface**: Uses same CDP session pattern; no new network endpoints or data persistence
- [x] **No credential handling**: Form values not involved in submit (just the submit action itself)

---

## Performance Considerations

- [x] **Navigation wait**: 100ms grace period for navigation detection (same as `interact click`), not blocking
- [x] **No additional CDP roundtrips**: Only 2-3 CDP calls (resolve node, find form, submit) beyond session setup
- [x] **Snapshot optional**: Snapshot is only taken when `--include-snapshot` is passed

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Unit | #[test] in form.rs | SubmitResult serialization (with/without url, with/without snapshot) |
| Unit | #[test] in form.rs | FIND_FORM_JS behavior (form element, element inside form, element not in form) |
| CLI | BDD (Gherkin) | Argument validation (help, missing args) |
| Integration | BDD (commented, Chrome-required) | Full submit flow (navigation, no-navigation, error cases) |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `requestSubmit()` not available in very old Chrome | Low | Medium | CDP users use modern Chrome; could fall back to `submit()` but unnecessary |
| Navigation detection misses AJAX-only submits | Low | Low | AJAX submits don't navigate, so the command correctly reports no URL; this is expected behavior |
| Form inside iframe | Low | Medium | Out of scope for this feature; target resolution already handles same-document elements only |

---

## Open Questions

None.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #147 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] State management approach is clear (stateless, reads/writes snapshot only when flagged)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
