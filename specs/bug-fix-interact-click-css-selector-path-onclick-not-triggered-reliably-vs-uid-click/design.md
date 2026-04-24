# Root Cause Analysis: interact click CSS selector path fails to trigger onclick

**Issue**: #252
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley

---

## Root Cause

`interact click` routes both UIDs and CSS selectors through `resolve_target_to_backend_node_id` → `scroll_into_view` → `get_element_center` → `dispatch_click` (`src/interact.rs:255–373, 383–469, 1713`). Static inspection shows the CSS branch and UID branch converge on the same `dispatch_click` at an identical `(x, y)`. The observable symptom — handler fires from UID and from `click-at` at the same coordinates but not from the CSS branch — points to divergence **inside the CSS resolution path** rather than inside `dispatch_click` itself.

The most likely root cause, pending confirmation in T001, is in `resolve_target_to_backend_node_id` (`src/interact.rs:271–305`). The CSS branch calls `DOM.getDocument` → `DOM.querySelector` → `DOM.describeNode`, then returns the `backendNodeId`. If the document returned by `DOM.getDocument` is stale or the `scrollIntoViewIfNeeded` call subsequently shifts layout, the `DOM.getBoxModel` content quad can describe a **pre-scroll** rectangle while the dispatched `Input.dispatchMouseEvent` lands on a **post-scroll** layout — at coordinates that no longer sit on the button. The UID path is not affected because UIDs carry a stable `backendNodeId` already scoped to the snapshot's layout state, and `click-at` bypasses resolution entirely.

A secondary candidate is coordinate-space mismatch: `DOM.getBoxModel` returns content quads in CSS pixels relative to the layout viewport, while `Input.dispatchMouseEvent` expects coordinates in the same space. If device-pixel scaling or a viewport override is active in the CSS branch only (e.g., because of the order in which `DOM` vs `Page` domains are enabled), coordinates would be off by a scaling factor. This is considered less likely because the control experiment at `click-at 89 113` succeeds, implying the integer CSS-pixel quad is correct at dispatch time.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/interact.rs` | 255–309 | `resolve_target_to_backend_node_id` — CSS branch (271–305) |
| `src/interact.rs` | 351–358 | `scroll_into_view` — common helper |
| `src/interact.rs` | 314–348 | `get_element_center` — reads `DOM.getBoxModel` content quad |
| `src/interact.rs` | 366–373 | `resolve_target_coords` — orchestrates resolve → scroll → measure |
| `src/interact.rs` | 1713 | `execute_click` call site |

### Triggering Conditions

- Target is a `css:<selector>` (not a UID, not raw coordinates).
- Target element relies on an `onclick` attribute rather than navigation.
- `DOM.getDocument` root is used for `DOM.querySelector` (no frame targeting).
- Conditions weren't caught before because existing BDD coverage for `interact click` exercises navigation and UID targets; no scenario validates that a CSS-selector click actually fires a JS handler that mutates the DOM.

---

## Fix Strategy

### Approach

Make the CSS branch behaviourally equivalent to the UID branch at dispatch time. Concretely:

1. **Confirm the root cause** before editing. In T001, capture the actual CDP frames for UID, CSS, and `click-at` on the reference page and diff them. Only then commit to the specific change.
2. **Apply the minimal fix** identified by the diff. The expected shape is to reorder operations in `resolve_target_coords` so that `DOM.getBoxModel` is read **after** any scroll-induced layout has settled, and to ensure the CSS branch measures the same quad space as the UID branch. If the diff instead reveals a coordinate-space mismatch, the fix is to normalize the coordinates (or the event-dispatch space) before calling `Input.dispatchMouseEvent`.
3. **Do not refactor** the dispatch helpers, the UID branch, or the `click-at` path. The fix stays inside `resolve_target_to_backend_node_id`'s CSS branch and/or `resolve_target_coords`.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/interact.rs` | Adjust the CSS branch of `resolve_target_to_backend_node_id` and/or the ordering inside `resolve_target_coords` so the dispatched mouse event lands on the same live layout the UID path would. Exact edit is T001-gated on the CDP diff. | Fixes the path that diverges while leaving working paths untouched. |
| `tests/features/bug-fix-interact-click-css-selector-path-onclick-not-triggered-reliably-vs-uid-click.feature` | New `@regression` Gherkin file. | Guards the fix. |
| `tests/bdd.rs` (or the corresponding steps module) | Step definitions to run the reproduction and assert DOM mutation. | Executes the regression scenario. |

### Blast Radius

- **Direct impact**: CSS-selector branch of `resolve_target_to_backend_node_id` and/or `resolve_target_coords` in `src/interact.rs`.
- **Indirect impact**: Any `interact` subcommand that calls `resolve_target_coords` with a CSS selector — limited to `click` and the CSS-selector mode of other `interact` subcommands that share this resolver. The fix must leave the UID branch byte-identical.
- **Risk level**: Low. The fix is scoped to a single function's CSS branch; UID and `click-at` paths are untouched.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| UID click path regresses while CSS path is fixed. | Low | Edit only the CSS branch / resolver ordering; AC2 regression scenario re-exercises the UID path on the same page. |
| CSS-selector navigation clicks (e.g., `<a href>`) stop reporting `navigated: true`. | Low | AC3 adds a `@regression` scenario for CSS-selector navigation. |
| Coordinates shift under dynamic layout (element is outside the viewport before `scrollIntoViewIfNeeded`). | Medium | Ensure `DOM.getBoxModel` runs *after* `DOM.scrollIntoViewIfNeeded` completes (the current code already orders it this way; verify the CDP diff confirms it). |
| The chosen fix masks a deeper CDP issue (e.g., stale `DOM.getDocument` node handle). | Low | T001 captures CDP frames and records the observed divergence in the PR description so future defects in the same area have a trail. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Route CSS selectors through the UID path by first snapshotting and resolving via the uid_map. | Would eliminate the divergent branch entirely. | Requires a snapshot before every CSS-selector click — unacceptable latency and behavioural change. Out of scope for a defect fix. |
| Replace `Input.dispatchMouseEvent` with a JS-synthesized `element.click()` on the resolved node. | Would sidestep coordinate math entirely. | Diverges from the project's CDP-native dispatch model and wouldn't fire real pointer events. |

---

## Validation Checklist

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #252 | 2026-04-23 | Initial defect design |
