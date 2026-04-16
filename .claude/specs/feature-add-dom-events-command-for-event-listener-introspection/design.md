# Design: DOM Events Command for Event Listener Introspection

**Issues**: #192
**Date**: 2026-04-16
**Status**: Approved
**Author**: Claude (spec agent)

---

## Overview

This feature adds a `dom events <target>` subcommand to the existing DOM command group in `src/dom.rs`. The command resolves the target element (via UID, CSS selector, or backendNodeId), obtains a `Runtime.RemoteObjectId` for the element, then calls `DOMDebugger.getEventListeners` to retrieve all attached event listeners — including both `addEventListener`-registered handlers and inline attribute handlers (e.g., `onclick`).

The implementation follows the established pattern of other DOM subcommands: session setup, frame resolution, node resolution via `resolve_node()`, CDP interaction, and structured JSON output via `print_output()`. The key architectural decision is to reuse the existing `DOM.resolveNode` → objectId pipeline already used by `get_text_content()` and other helpers, adding the `DOMDebugger.getEventListeners` CDP call as the final step.

No new modules or files are created — the implementation adds a new variant to `DomCommand`, new output types, and a new `execute_events` function, all within the existing `dom.rs` and `cli/mod.rs` files.

---

## Architecture

### Component Diagram

```
CLI Layer (cli/mod.rs)
    │
    │  DomCommand::Events(DomNodeIdArgs)
    ▼
Command Module (dom.rs)
    │
    │  execute_events()
    │    ├── setup_session_with_interceptors()
    │    ├── resolve_optional_frame()
    │    ├── ensure_domain("DOM")
    │    ├── ensure_domain("Runtime")
    │    ├── resolve_node(target) → ResolvedNode { node_id, backend_node_id }
    │    ├── DOM.resolveNode({ nodeId }) → objectId
    │    └── DOMDebugger.getEventListeners({ objectId }) → listeners
    ▼
CDP Client (cdp/client.rs)
    │
    ▼
Chrome (DOMDebugger domain)
```

### Data Flow

```
1. User runs: agentchrome dom events css:button
2. CLI layer parses args → DomCommand::Events(DomNodeIdArgs { node_id: "css:button" })
3. execute_dom() dispatches to execute_events()
4. Session established, frame resolved (if --frame provided)
5. DOM and Runtime domains enabled
6. resolve_node("css:button") → ResolvedNode { node_id: 42, backend_node_id: 100 }
7. DOM.resolveNode({ nodeId: 42 }) → { object: { objectId: "obj-123" } }
8. DOMDebugger.getEventListeners({ objectId: "obj-123" }) → { listeners: [...] }
9. Map CDP response → EventListenersResult { listeners: [...] }
10. print_output() serializes to JSON/plain text on stdout
```

---

## API / Interface Changes

### New CLI Subcommand

| Command | Type | Auth | Purpose |
|---------|------|------|---------|
| `dom events <target>` | CLI subcommand | No | List all event listeners attached to a DOM element |

### CLI Arguments

The `events` subcommand reuses the existing `DomNodeIdArgs` struct (same as `get-text`, `get-html`, `remove`, `parent`, `children`, `siblings`):

- **`target`** (positional, required): Element identifier — UID (`s1`), CSS selector (`css:button`), or integer backendNodeId
- **`--frame`** (optional, inherited from `DomArgs`): Target frame by index, path, or `auto`

### Output Schema

**Success (JSON):**
```json
{
  "listeners": [
    {
      "type": "click",
      "useCapture": false,
      "once": true,
      "passive": false,
      "handler": {
        "description": "function handleClick() { ... }",
        "scriptId": "42",
        "lineNumber": 10,
        "columnNumber": 0
      }
    }
  ]
}
```

**Success (empty):**
```json
{
  "listeners": []
}
```

**Plain text format (--plain):**
```
click  capture:false  once:true  passive:false  handler:function handleClick() { ... }
mouseover  capture:false  once:false  passive:true  handler:function() { ... }
```

**Errors:**

| Code / Type | Condition |
|-------------|-----------|
| ExitCode::ProtocolError (5) | CDP `DOMDebugger.getEventListeners` call fails |
| ExitCode::TargetError (3) | Target element not found (node resolution failure) |

---

## Database / Storage Changes

None. This is a read-only query command with no persistent state.

---

## State Management

No new state introduced. The command is stateless — it queries CDP and returns the result. It follows the same session-scoped pattern as all other DOM subcommands.

---

## Implementation Details

### New Output Types (dom.rs)

```rust
/// Individual event listener handler source information.
#[derive(Serialize)]
struct EventHandler {
    description: String,
    #[serde(rename = "scriptId")]
    script_id: Option<String>,
    #[serde(rename = "lineNumber")]
    line_number: Option<i64>,
    #[serde(rename = "columnNumber")]
    column_number: Option<i64>,
}

/// Individual event listener entry from DOMDebugger.getEventListeners.
#[derive(Serialize)]
struct EventListenerInfo {
    #[serde(rename = "type")]
    event_type: String,
    #[serde(rename = "useCapture")]
    use_capture: bool,
    once: bool,
    passive: bool,
    handler: EventHandler,
}

/// Top-level result for `dom events`.
#[derive(Serialize)]
struct EventListenersResult {
    listeners: Vec<EventListenerInfo>,
}
```

### New DomCommand Variant (cli/mod.rs)

```rust
/// List event listeners attached to an element
#[command(
    long_about = "List all event listeners attached to a DOM element. Shows listeners \
        registered via addEventListener and inline handlers (e.g., onclick). Output \
        includes event type, capture/bubble phase, once/passive flags, and handler \
        source location.",
    after_long_help = "\
EXAMPLES:
  # List listeners by UID
  agentchrome dom events s3

  # List listeners by CSS selector
  agentchrome dom events css:button

  # List listeners in a frame
  agentchrome dom --frame 0 events css:button"
)]
Events(DomNodeIdArgs),
```

### CDP Interaction Pattern

The `execute_events` function follows the same pattern as `execute_get_text`:

1. Setup session and frame context
2. Enable `DOM` and `Runtime` domains
3. Call `resolve_node()` to get session-scoped `node_id`
4. Call `DOM.resolveNode({ nodeId })` to get `objectId`
5. Call `DOMDebugger.getEventListeners({ objectId })` to get listeners
6. Map CDP response to `EventListenersResult`
7. Output via `print_output()` or plain text

Key detail: `DOMDebugger.getEventListeners` does not require enabling the `DOMDebugger` domain — it is a standalone query method that only needs a valid `Runtime.RemoteObjectId`.

### CDP Response Mapping

The CDP `DOMDebugger.getEventListeners` response has this shape:

```json
{
  "listeners": [
    {
      "type": "click",
      "useCapture": false,
      "passive": false,
      "once": false,
      "handler": {
        "type": "function",
        "className": "Function",
        "description": "function handleClick() { ... }",
        "objectId": "...",
        "preview": { ... }
      },
      "scriptId": "42",
      "lineNumber": 10,
      "columnNumber": 0
    }
  ]
}
```

Note: `scriptId`, `lineNumber`, `columnNumber` are at the listener level in the CDP response. The handler source information (`description`) is inside the `handler` object. Our output schema groups all source info under a `handler` sub-object for cleaner consumption.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: JavaScript-based** | Use `Runtime.evaluate` with a page-injected script to read listeners | No CDP domain dependency | Cannot access `getEventListeners()` from page scripts — it's a DevTools-only API | Rejected — technically impossible from page JS |
| **B: DOMDebugger.getEventListeners** | Use the CDP method designed for this purpose | Direct, reliable, returns all listener types | Requires resolving target to RemoteObjectId first | **Selected** |
| **C: Separate `events` top-level command** | Create a new top-level `events` command | Could grow independently | Breaks the dom command group pattern, more CLI surface area | Rejected — belongs logically with DOM commands |

---

## Security Considerations

- [x] **Input Validation**: Target string validated by existing `resolve_node()` (UID format, CSS selector prefix, integer parse)
- [x] **No mutation**: Command is read-only — cannot modify or remove listeners
- [x] **Local only**: CDP connections are localhost-only (per tech.md)

---

## Performance Considerations

- [x] **Single CDP call**: After node resolution (1-2 calls), only one `DOMDebugger.getEventListeners` call is needed
- [x] **No caching needed**: Results are point-in-time queries, not persisted
- [x] **Bounded output**: Typical elements have < 10 listeners; no pagination needed

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Output types | Unit | Serialization of `EventListenerInfo`, `EventHandler`, `EventListenersResult` |
| Command | Integration (BDD) | All 7 acceptance criteria as Gherkin scenarios |
| Smoke | Manual | Real Chrome instance with test fixture |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CDP response format varies across Chrome versions | Low | Medium | Defensive parsing with `.as_str()/.as_bool()/.as_i64()` and fallback defaults |
| `DOMDebugger.getEventListeners` not available in older Chrome | Low | High | Document minimum Chrome version requirement; fail gracefully with descriptive error |

---

## Open Questions

- None

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #192 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] No database/storage changes needed
- [x] No state management changes needed
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
