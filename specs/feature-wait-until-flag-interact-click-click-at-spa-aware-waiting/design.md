# Design: Add --wait-until Flag to Interact Click Commands

**Issues**: #148
**Date**: 2026-02-26
**Status**: Draft
**Author**: Claude

---

## Overview

This feature adds a `--wait-until` flag to the `interact click` and `interact click-at` commands, reusing the existing `WaitUntil` enum (`load`, `domcontentloaded`, `networkidle`, `none`) and wait infrastructure from the `navigate` module. The key architectural decision is to expose the existing wait helpers (`wait_for_event`, `wait_for_network_idle`) as public functions in `navigate.rs` so `interact.rs` can call them directly, avoiding code duplication.

The default behavior when `--wait-until` is omitted remains unchanged: `click` retains its 100ms grace period with `Page.frameNavigated` check, and `click-at` returns immediately after dispatching. When `--wait-until` is provided, the command subscribes to the appropriate CDP events before dispatching the click, then delegates to the navigate module's wait strategy implementation.

---

## Architecture

### Component Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    CLI Layer (cli/mod.rs)                 │
│  ┌──────────────┐    ┌───────────────┐                   │
│  │  ClickArgs   │    │  ClickAtArgs  │                   │
│  │ + wait_until │    │ + wait_until  │                   │
│  └──────────────┘    └───────────────┘                   │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              Command Module (interact.rs)                 │
│  ┌─────────────────┐    ┌──────────────────┐             │
│  │ execute_click()  │    │ execute_click_at()│             │
│  │ + wait strategy  │    │ + wait strategy   │             │
│  └────────┬────────┘    └────────┬─────────┘             │
│           │ if --wait-until      │ if --wait-until        │
│           ▼                      ▼                        │
│  ┌──────────────────────────────────────────┐            │
│  │      navigate.rs (public wait helpers)    │            │
│  │  wait_for_event()                         │            │
│  │  wait_for_network_idle()                  │            │
│  │  NETWORK_IDLE_MS                          │            │
│  └──────────────────────────────────────────┘            │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              CDP Client (cdp/client.rs)                   │
│  subscribe() → Receiver<CdpEvent>                        │
│  Events: Network.requestWillBeSent, loadingFinished,     │
│          loadingFailed, Page.loadEventFired,              │
│          Page.domContentEventFired                        │
└──────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User runs: agentchrome interact click s12 --wait-until networkidle
2. CLI parses ClickArgs with wait_until = Some(WaitUntil::Networkidle)
3. execute_click() enables DOM, Page, Network domains
4. Subscribes to CDP events based on wait strategy (before clicking)
5. Resolves target coordinates via accessibility tree
6. Dispatches click via Input.dispatchMouseEvent
7. Delegates to navigate::wait_for_network_idle() with event receivers
8. wait_for_network_idle() tracks in-flight requests until 500ms idle
9. After wait completes, fetches current URL via Runtime.evaluate
10. Returns ClickResult JSON with navigated=true and updated URL
```

---

## API / Interface Changes

### CLI Changes

| Command | Change | Description |
|---------|--------|-------------|
| `interact click` | Add `--wait-until` flag | Optional `WaitUntil` enum, no default (omission preserves legacy behavior) |
| `interact click-at` | Add `--wait-until` flag | Optional `WaitUntil` enum, no default (omission preserves legacy behavior) |

#### `interact click` — Updated Signature

```
agentchrome interact click <TARGET> [--double] [--right] [--include-snapshot] [--wait-until <STRATEGY>]
```

#### `interact click-at` — Updated Signature

```
agentchrome interact click-at <X> <Y> [--double] [--right] [--include-snapshot] [--wait-until <STRATEGY>]
```

Where `<STRATEGY>` is one of: `load`, `domcontentloaded`, `networkidle`, `none`.

### Clap Argument Definition

Both `ClickArgs` and `ClickAtArgs` gain:

```rust
/// Wait strategy after click (e.g., for SPA navigation).
/// If omitted, click returns immediately with a brief navigation check.
#[arg(long, value_enum)]
pub wait_until: Option<WaitUntil>,
```

**Critical design choice**: The field is `Option<WaitUntil>` (not `WaitUntil` with a default). This distinguishes "user did not provide the flag" from "user explicitly chose a strategy." When `None`, the legacy behavior (100ms grace period) is preserved. This differs from `navigate`, where `wait_until` defaults to `WaitUntil::Load`.

### Output Schemas

#### `interact click` — Output (unchanged structure)

```json
{
  "clicked": "s12",
  "url": "https://spa-app.example.com/dashboard",
  "navigated": true,
  "snapshot": null
}
```

The `url` and `navigated` fields already exist. With `--wait-until`, the `url` reflects the post-wait URL and `navigated` is set based on whether the URL changed (or for `load`/`domcontentloaded`, always `true` if the event fired).

#### `interact click-at` — Output (enhanced)

```json
{
  "clicked_at": { "x": 150.0, "y": 300.0 },
  "url": "https://spa-app.example.com/dashboard",
  "navigated": true,
  "snapshot": null
}
```

Currently `ClickAtResult` lacks `url` and `navigated` fields. When `--wait-until` is provided, these fields are added as optional (serialized only when present). When `--wait-until` is omitted, the output remains unchanged for backward compatibility.

**Errors:**

| Exit Code | Condition |
|-----------|-----------|
| 4 (Timeout) | Wait strategy did not complete within `--timeout` duration |
| 0 (Success) | Click dispatched and wait completed successfully |

---

## Module Visibility Changes

### navigate.rs — Expose Wait Helpers

The following items in `navigate.rs` must be made `pub` so `interact.rs` can import them:

| Item | Current | New | Rationale |
|------|---------|-----|-----------|
| `wait_for_event()` | private `async fn` | `pub async fn` | Reused for `load` and `domcontentloaded` strategies |
| `wait_for_network_idle()` | private `async fn` | `pub async fn` | Reused for `networkidle` strategy |
| `NETWORK_IDLE_MS` | private `const` | `pub const` | Referenced by interact.rs timeout calculations |
| `DEFAULT_NAVIGATE_TIMEOUT_MS` | private `const` | `pub const` | Used as fallback timeout when global `--timeout` not set |

### interact.rs — New Imports

```rust
use crate::cli::{WaitUntil, ...};  // Add WaitUntil to existing import
use crate::navigate::{wait_for_event, wait_for_network_idle, DEFAULT_NAVIGATE_TIMEOUT_MS};
```

---

## State Management

No persistent state changes. The `--wait-until` flag is consumed within a single command invocation. CDP event subscriptions are established before the click and automatically cleaned up when the receivers are dropped at function exit.

### Event Subscription Lifecycle

```
execute_click() entry
  ├── enable Network domain (if --wait-until is networkidle)
  ├── subscribe to wait-strategy events
  ├── dispatch_click()
  ├── delegate to wait helper (consumes receivers)
  ├── receivers dropped → subscriptions cleaned up
  └── return result
```

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: Duplicate wait logic** | Copy `wait_for_network_idle` and `wait_for_event` into `interact.rs` | No cross-module coupling | Code duplication, divergent maintenance | Rejected — violates DRY |
| **B: Extract shared wait module** | Create `src/wait.rs` with shared wait helpers | Clean separation of concerns | Unnecessary abstraction for 2 consumers; extra module to maintain | Rejected — over-engineering for now |
| **C: Make navigate helpers public** | Add `pub` to existing functions in `navigate.rs` | Minimal change, no code movement, single source of truth | Slightly expands navigate.rs public API | **Selected** — simplest correct solution |

---

## Security Considerations

- [x] **No new authentication**: No auth changes
- [x] **No new input surfaces**: `--wait-until` reuses the existing `WaitUntil` enum validated by clap
- [x] **CDP connection**: Uses existing localhost-only CDP connection
- [x] **No sensitive data**: No secrets or credentials involved

---

## Performance Considerations

- [x] **No overhead without flag**: When `--wait-until` is omitted, no extra CDP subscriptions are created and the legacy 100ms path executes
- [x] **Subscription cost**: CDP event subscriptions are lightweight (channel creation)
- [x] **Network idle**: Uses the existing 500ms threshold; no additional network overhead
- [x] **Domain enablement**: `Network` domain only enabled when `--wait-until` is `networkidle`, avoiding unnecessary CDP traffic otherwise

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI parsing | Unit | `--wait-until` flag parses correctly for both click and click-at; `Option<WaitUntil>` is `None` when flag omitted |
| Wait logic | Integration (BDD) | All 6 acceptance criteria become Gherkin scenarios |
| Backward compat | Integration (BDD) | Click without `--wait-until` produces identical behavior |
| Timeout | Integration (BDD) | Timeout error produces exit code 4 with JSON error |
| Smoke test | Manual | SauceDemo SPA navigation with `--wait-until networkidle` |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Making navigate helpers public exposes internal API | Low | Low | Functions have clean signatures with no navigate-specific dependencies; they accept generic CDP event receivers |
| Network idle may not settle if SPA has background polling (e.g., WebSocket heartbeat) | Medium | Medium | This is the same limitation as `navigate --wait-until networkidle`; documented in help text; users can use `--timeout` to bound wait time |
| `click-at` output schema change (adding `url`/`navigated`) could break consumers | Low | Medium | Fields are `Option` with `skip_serializing_if = "Option::is_none"` — absent when `--wait-until` is not provided |

---

## Open Questions

- None

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #148 | 2026-02-26 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] No database/storage changes required
- [x] State management approach is clear (no persistent state)
- [x] No UI components (CLI-only)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
