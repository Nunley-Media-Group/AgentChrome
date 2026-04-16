# Design: Fix Full-Page Screenshot for Scrollable Inner Containers

**Issues**: #184
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude

---

## Overview

This design extends the existing `page screenshot --full-page` command to handle pages where scrollable content lives inside an inner container rather than the document body. The core approach adds a `--scroll-container <selector>` CLI argument and a new capture path in `execute_screenshot` that: (1) queries the target element's scroll dimensions via `Runtime.evaluate`, (2) temporarily overrides the element's and its ancestors' CSS to make overflow content visible, (3) expands the viewport to the scroll dimensions, (4) captures the screenshot, and (5) restores all modifications. A lightweight auto-detection mechanism warns when full-page dimensions match the viewport, suggesting the new flag.

The changes are confined to two files: `src/cli/mod.rs` (new argument) and `src/page/screenshot.rs` (new helper functions and an additional branch in the capture strategy). No new modules, dependencies, or architectural changes are needed. The existing capture pipeline (`Page.captureScreenshot` with `captureBeyondViewport`) is reused; only the dimension source and pre-capture DOM preparation change.

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────┐
│                    CLI Layer                          │
│  PageScreenshotArgs                                  │
│  + scroll_container: Option<String>  ← NEW           │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              execute_screenshot()                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  Validation │  │ Capture      │  │  Cleanup   │  │
│  │  (new rules)│─▶│ Strategy     │─▶│  (restore) │  │
│  └─────────────┘  └──────┬───────┘  └────────────┘  │
│                          │                           │
│           ┌──────────────┼──────────────┐            │
│           ▼              ▼              ▼            │
│  ┌─────────────┐  ┌────────────┐  ┌────────────┐    │
│  │ Default     │  │ Scroll     │  │ Selector/  │    │
│  │ full-page   │  │ Container  │  │ UID/Clip   │    │
│  │ (existing)  │  │ (NEW)      │  │ (existing) │    │
│  └─────────────┘  └────────────┘  └────────────┘    │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                 CDP Client Layer                      │
│  Runtime.evaluate  │  DOM.querySelector               │
│  Emulation.setDeviceMetricsOverride                   │
│  Page.captureScreenshot                               │
└─────────────────────────────────────────────────────┘
```

### Data Flow — Scroll Container Path

```
1. CLI parses --full-page + --scroll-container ".main-content"
2. Validation: confirm --full-page is set, no conflicting flags
3. DOM.querySelector finds the target element's nodeId
4. Runtime.evaluate gets element's scrollWidth/scrollHeight
5. Runtime.evaluate saves original inline styles of element + ancestors
6. Runtime.evaluate sets overflow:visible, height:auto on element + ancestors
7. Emulation.setDeviceMetricsOverride expands viewport to scroll dimensions
8. Page.captureScreenshot with captureBeyondViewport: true
9. Runtime.evaluate restores original inline styles
10. Emulation.clearDeviceMetricsOverride restores viewport
11. Output JSON with captured dimensions
```

### Data Flow — Auto-Detection Warning

```
1. CLI parses --full-page (no --scroll-container)
2. get_page_dimensions() returns (page_w, page_h)
3. get_viewport_dimensions() returns (vp_w, vp_h)
4. If page_h == vp_h: emit warning to stderr
5. Proceed with normal full-page capture (no behavior change)
```

---

## API / Interface Changes

### CLI Changes

| Flag | Type | Conflicts With | Purpose |
|------|------|----------------|---------|
| `--scroll-container <SELECTOR>` | `Option<String>` | `--selector`, `--uid`, `--clip`; requires `--full-page` | CSS selector for the inner scrollable element |

### Updated Command Help

```
agentchrome page screenshot --full-page --scroll-container ".main-content" --file shot.png
```

### Output Schema

No changes. Output remains:

**Success (file):**
```json
{
  "format": "png",
  "file": "/path/to/shot.png",
  "width": 1280,
  "height": 3000
}
```

**Success (base64):**
```json
{
  "format": "png",
  "data": "iVBORw0KGgo...",
  "width": 1280,
  "height": 3000
}
```

**Errors:**

| Condition | Error Message |
|-----------|---------------|
| `--scroll-container` without `--full-page` | `"Screenshot capture failed: --scroll-container requires --full-page"` |
| `--scroll-container` with `--selector`/`--uid`/`--clip` | `"Screenshot capture failed: Cannot combine --scroll-container with --selector, --uid, or --clip"` |
| Element not found | `"Element not found for selector: .nonexistent"` |

---

## State Management

### Temporary State During Scroll-Container Capture

The scroll-container path modifies two kinds of state that must be restored:

1. **Viewport override** — set via `Emulation.setDeviceMetricsOverride`, cleared via `Emulation.clearDeviceMetricsOverride`. This is the same mechanism the existing `--full-page` path uses.

2. **Element inline styles** — the target element and its ancestors need `overflow: visible` and `height: auto` to make content visible to the compositor. Original `style` attribute values are saved and restored via `Runtime.evaluate`. This is new to this feature.

### Restoration Guarantee

Both modifications are restored in a finally-like pattern: the capture result is captured first, then restoration runs unconditionally before the result is returned or the error is propagated. This matches the existing pattern where `clear_viewport_override` runs after `--full-page` capture.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: CSS override + viewport expand** | Temporarily set `overflow: visible; height: auto` on the container and ancestors, expand viewport, capture with compositor | Works with CDP's existing capture; single screenshot; consistent with current `--full-page` approach | Requires DOM manipulation; may affect layout of absolutely-positioned elements | **Selected** |
| **B: Scroll-and-stitch** | Scroll the container in steps, capture each viewport, stitch into a single image | No DOM manipulation needed; works for any scroll container | Complex image assembly; potential alignment issues; much slower; larger memory footprint | Rejected — complexity and performance cost outweigh benefits |
| **C: CDP Page.printToPDF** | Use the print/PDF pathway which naturally expands content | Built-in content expansion | Not a screenshot (different rendering); no transparency; format limitations; doesn't respect CSS media screen | Rejected — different output semantics |
| **D: Auto-detect and auto-expand** | Automatically find the scrollable container without user input | No extra flag needed | Unreliable heuristic; multiple scrollable containers are ambiguous; surprising behavior | Rejected for auto-expand — warning-only auto-detect is included |

---

## Security Considerations

- [x] **Input Validation**: CSS selector is passed to `DOM.querySelector` which handles escaping; also passed to `Runtime.evaluate` inside a JSON string — must be properly escaped to prevent JS injection
- [x] **No new external communication**: All operations are local CDP commands to a local Chrome instance
- [x] **Style restoration**: Failed restoration could leave the page in a modified state; mitigated by always-restore pattern

---

## Performance Considerations

- [x] **No overhead for non-full-page captures**: The scroll-container path only activates when both `--full-page` and `--scroll-container` are set
- [x] **Auto-detection cost**: One additional `Runtime.evaluate` call to compare page and viewport dimensions; negligible latency (~1ms)
- [x] **Style override round-trips**: Two `Runtime.evaluate` calls (save+override, then restore) plus the existing viewport override — adds ~5-10ms total
- [x] **Large screenshots**: Very tall inner containers could produce large images; the existing `LARGE_IMAGE_THRESHOLD` warning (10MB) applies

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI arg parsing | Unit | `--scroll-container` parsed correctly, validation errors for conflicting/missing flags |
| Dimension helpers | Unit | `get_container_scroll_dimensions` returns correct values from mock JS responses |
| Style override JS | Unit | JavaScript string generation produces correct override/restore scripts |
| Auto-detection | Unit | Warning emitted when page dimensions match viewport dimensions |
| Full capture flow | BDD/Integration | All 7 acceptance criteria as Gherkin scenarios |
| Smoke test | Manual | Real headless Chrome with inner-scrollable test page |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CSS override breaks page layout for absolutely-positioned elements | Medium | Low | Override only `overflow` and `height`; keep `width` and positioning unchanged; restore immediately after capture |
| Style restoration fails mid-capture | Low | Medium | Use always-restore pattern; if JS eval fails, viewport is still cleared by `clear_viewport_override` |
| Inner container has CSS `max-height` that prevents expansion | Medium | Medium | Override `max-height: none` alongside `height: auto` in the style override script |
| Selector matches wrong element on complex pages | Low | Low | User provides the selector explicitly; error message guides them if element not found |

---

## Open Questions

- None

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #184 | 2026-04-16 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] State management approach is clear
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
