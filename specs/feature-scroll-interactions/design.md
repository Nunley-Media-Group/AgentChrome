# Design: Scroll Interactions

**Issues**: #17
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude (writing-specs)

---

## Overview

This feature adds a `scroll` subcommand to the existing `interact` command group, following the established patterns in `src/interact.rs`. The scroll command allows users to scroll the page or a specific container element using `Runtime.evaluate` with `window.scrollBy()` / `window.scrollTo()` for page scrolling, and `DOM.scrollIntoViewIfNeeded` for element-targeted scrolling. The implementation reuses the existing session setup, target resolution, snapshot, and output formatting infrastructure.

The command integrates naturally into the existing `InteractCommand` enum as a new variant `Scroll(ScrollArgs)`, dispatched through `execute_interact()` in `src/interact.rs`. No new modules or files are required — all scroll logic lives in `src/interact.rs` alongside the other interaction commands.

---

## Architecture

### Component Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    CLI Layer (src/cli/mod.rs)             │
├──────────────────────────────────────────────────────────┤
│  InteractCommand::Scroll(ScrollArgs)                     │
│  ScrollArgs: --direction, --amount, --to-element,        │
│              --to-top, --to-bottom, --smooth,            │
│              --container, --include-snapshot              │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│              Command Layer (src/interact.rs)              │
├──────────────────────────────────────────────────────────┤
│  execute_scroll()                                        │
│  ├── setup_session()              [reuse existing]       │
│  ├── resolve_target_to_backend_node_id()  [for element]  │
│  ├── dispatch_scroll()            [new — JS evaluation]  │
│  ├── take_snapshot()              [reuse existing]       │
│  └── print_output() / print_scroll_plain()               │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│                CDP Layer (src/cdp/)                       │
├──────────────────────────────────────────────────────────┤
│  Runtime.evaluate          → window.scrollBy/scrollTo    │
│  DOM.scrollIntoViewIfNeeded → scroll element into view   │
│  Runtime.evaluate          → read scroll position        │
│  Accessibility.getFullAXTree → snapshot (optional)       │
└──────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User runs: agentchrome interact scroll [options]
2. Clap parses args into ScrollArgs
3. execute_scroll() sets up CDP session via setup_session()
4. Read initial scroll position via Runtime.evaluate (window.scrollX/Y)
5. Determine scroll mode:
   a. --to-element: resolve target → DOM.scrollIntoViewIfNeeded
   b. --to-top: Runtime.evaluate → window.scrollTo(0, 0)
   c. --to-bottom: Runtime.evaluate → window.scrollTo(0, document.body.scrollHeight)
   d. --direction + --amount: Runtime.evaluate → window.scrollBy(dx, dy)
   e. --container + above: resolve container → element.scrollBy/scrollTo
6. Read final scroll position via Runtime.evaluate
7. Compute scroll delta (final - initial)
8. Take snapshot if --include-snapshot
9. Output ScrollResult as JSON or plain text
```

---

## API / Interface Changes

### New CLI Subcommand

| Command | Purpose |
|---------|---------|
| `agentchrome interact scroll [OPTIONS]` | Scroll the page or a container element |

### ScrollArgs (Clap Struct)

| Flag | Type | Default | Conflicts With | Description |
|------|------|---------|----------------|-------------|
| `--direction <DIR>` | ValueEnum: down, up, left, right | down | `--to-element`, `--to-top`, `--to-bottom` | Scroll direction |
| `--amount <PIXELS>` | u32 | viewport height/width | `--to-element`, `--to-top`, `--to-bottom` | Scroll distance in pixels |
| `--to-element <TARGET>` | String (UID or css:...) | — | `--direction`, `--amount`, `--to-top`, `--to-bottom` | Scroll until element is in view |
| `--to-top` | bool flag | false | `--direction`, `--amount`, `--to-element`, `--to-bottom` | Scroll to page top |
| `--to-bottom` | bool flag | false | `--direction`, `--amount`, `--to-element`, `--to-top` | Scroll to page bottom |
| `--smooth` | bool flag | false | — | Use smooth scroll behavior |
| `--container <TARGET>` | String (UID or css:...) | — | `--to-element`, `--to-top`, `--to-bottom` | Scroll within a container element |
| `--include-snapshot` | bool flag | false | — | Include accessibility snapshot in output |

**Conflict groups**: The scroll command has three mutually exclusive modes:
1. **Direction scroll** (default): `--direction` + `--amount` (page or container)
2. **Element scroll**: `--to-element`
3. **Absolute scroll**: `--to-top` or `--to-bottom`

### Request / Response Schemas

**Output (success — JSON):**
```json
{
  "scrolled": { "x": 0, "y": 600 },
  "position": { "x": 0, "y": 600 },
  "snapshot": { "...": "optional accessibility tree" }
}
```

**Output (success — plain text):**
```
Scrolled down 600px to (0, 600)
Scrolled to element s5 at (0, 1200)
Scrolled to top at (0, 0)
Scrolled to bottom at (0, 4800)
Scrolled container s3 down 200px
```

**Errors:**

| Code / Type | Condition |
|-------------|-----------|
| `ExitCode::GeneralError` | UID not found, no snapshot state, element not found |
| `ExitCode::ProtocolError` | CDP command failure during scroll |
| Clap arg error | Conflicting flags (e.g., `--to-top --to-bottom`) |

---

## Database / Storage Changes

None. No database or persistent storage changes required.

---

## State Management

No new state. Reuses existing:
- `SnapshotState` for UID resolution (read-only unless `--include-snapshot`)
- `ManagedSession` for CDP domain tracking

---

## UI Components

### New Components

| Component | Location | Purpose |
|-----------|----------|---------|
| [name] | [path per structure.md] | [description] |

### Component Hierarchy

```
FeatureScreen
├── Header
├── Content
│   ├── LoadingState
│   ├── ErrorState
│   ├── EmptyState
│   └── DataView
│       ├── ListItem × N
│       └── DetailView
└── Actions
```

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: `Input.dispatchMouseEvent` (mouseWheel)** | Use CDP mouse wheel events to simulate scrolling | More realistic user simulation | Unreliable scroll distance, doesn't work in all contexts, no smooth scroll support, complex | Rejected — unreliable |
| **B: `Runtime.evaluate` with JS scroll APIs** | Use `window.scrollBy()`, `window.scrollTo()`, `element.scrollIntoView()` | Reliable, precise pixel control, smooth scroll support via `behavior: 'smooth'`, simple | Less "realistic" than mouse events | **Selected** |
| **C: Mixed approach** | Use `DOM.scrollIntoViewIfNeeded` for elements, JS for page scroll | Leverages existing helper | Inconsistent approach | Partially adopted — use `DOM.scrollIntoViewIfNeeded` for `--to-element` (already proven in codebase) |

**Decision**: Use `Runtime.evaluate` with JavaScript scroll APIs for page/container scrolling (Option B), and `DOM.scrollIntoViewIfNeeded` for `--to-element` (proven in the existing `scroll_into_view()` helper at `src/interact.rs:295`). This matches the issue's notes: "Runtime.evaluate with window.scrollTo() is simpler and more reliable than mouse wheel events."

---

## Security Considerations

- [x] **Input Validation**: Pixel amounts validated by clap (u32). Direction validated by ValueEnum. Targets validated by existing `resolve_target_to_backend_node_id()`.
- [x] **No new attack surface**: JavaScript executed via `Runtime.evaluate` uses only scroll APIs — no user-supplied JS code.
- [x] **Sensitive Data**: No sensitive data handled.

---

## Performance Considerations

- [x] **Minimal CDP round-trips**: 2-3 commands per scroll (read position, scroll, read position), plus optional snapshot
- [x] **Smooth scroll wait**: When `--smooth` is used, poll scroll position until stable (with timeout) rather than using a fixed sleep
- [x] **No caching needed**: Scroll is a one-shot command

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Output types | Unit | `ScrollResult` serialization, optional field skipping |
| Direction enum | Unit | Direction-to-delta mapping |
| Arg conflicts | BDD (no Chrome) | Conflicting flag combinations rejected by clap |
| CLI help | BDD (no Chrome) | `--help` shows scroll subcommand and options |
| Page scroll | BDD (Chrome) | Default scroll, directional scroll, pixel amount |
| Absolute scroll | BDD (Chrome) | `--to-top`, `--to-bottom` |
| Element scroll | BDD (Chrome) | `--to-element` with UID and CSS selector |
| Container scroll | BDD (Chrome) | `--container` with scrollable div |
| Smooth scroll | BDD (Chrome) | `--smooth` flag |
| Error cases | BDD (Chrome) | UID not found, no snapshot state |
| Plain text output | BDD (Chrome) | `--plain` flag formatting |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Smooth scroll timing is non-deterministic | Medium | Low | Poll scroll position with timeout (200ms intervals, 3s max) |
| Container scroll requires resolving to Runtime object ID | Low | Low | Use `DOM.resolveNode` (proven pattern in form.rs) to get objectId for JS execution on element |
| Viewport height detection varies across browsers | Low | Low | Use `window.innerHeight` — standard and well-supported |

---

## Implementation Notes

### Key CDP Commands

| Command | Use Case |
|---------|----------|
| `Runtime.evaluate("JSON.stringify({x: window.scrollX, y: window.scrollY})")` | Read page scroll position |
| `Runtime.evaluate("window.scrollBy(dx, dy)")` | Page directional scroll |
| `Runtime.evaluate("window.scrollTo(0, 0)")` | Scroll to top |
| `Runtime.evaluate("window.scrollTo(0, document.body.scrollHeight)")` | Scroll to bottom |
| `Runtime.evaluate("window.innerHeight")` | Get viewport height (default scroll amount) |
| `Runtime.evaluate("window.innerWidth")` | Get viewport width (default horizontal scroll) |
| `DOM.scrollIntoViewIfNeeded({ backendNodeId })` | Scroll element into view |
| `DOM.resolveNode({ backendNodeId })` + `Runtime.callFunctionOn({ objectId, functionDeclaration })` | Scroll within container element |

### Smooth Scroll Wait Strategy

For `--smooth`, after dispatching the scroll:
1. Read scroll position
2. Sleep 200ms
3. Read scroll position again
4. If position changed, repeat from step 2 (up to 3s timeout)
5. If position stable, return

### Default Scroll Amount

- Vertical (`down`/`up`): `window.innerHeight` pixels
- Horizontal (`left`/`right`): `window.innerWidth` pixels

---

## Open Questions

- [ ] [Technical question]
- [ ] [Architecture question]
- [ ] [Integration question]

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #17 | 2026-02-14 | Initial feature spec |

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] No database/storage changes needed
- [x] State management approach is clear (reuse existing)
- [x] No new UI components (CLI-only)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
