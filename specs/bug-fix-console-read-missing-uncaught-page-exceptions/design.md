# Root Cause Analysis: console read misses uncaught page exceptions

**Issue**: #290
**Date**: 2026-05-26
**Status**: Draft
**Author**: Codex (write-spec)

---

## Root Cause

`console read` currently builds its result set from only one CDP Runtime event stream: `Runtime.consoleAPICalled`. In `src/console.rs`, `execute_read()` subscribes to `Runtime.consoleAPICalled` before enabling the Runtime domain, drains the replayed events, parses each event through `parse_console_event()`, and applies the existing filters and pagination. That path correctly captures explicit `console.error(...)` calls because Chrome delivers those through `Runtime.consoleAPICalled`.

Uncaught page exceptions use a different Runtime event: `Runtime.exceptionThrown`. The current drain loop never subscribes to that event, never stores its parameters, and never normalizes `exceptionDetails` into the `ConsoleMessage` / `ConsoleMessageDetail` contracts. As a result, `--errors-only` sees only explicit console API error events. The issue is not in filtering itself; the filter is only working with an incomplete input set.

This defect escaped the existing runtime-message spec because issue #146 focused on replaying `Runtime.consoleAPICalled` across invocations and preserving page state. It did not require a sibling event-path audit for Runtime exception events, even though uncaught exceptions are one of the primary reasons an AI agent asks for console evidence after a browser workflow.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/console.rs` | 15-26 | `ConsoleMessage` list output contract used by `console read` |
| `src/console.rs` | 28-42 | `ConsoleMessageDetail` detail output contract used by `console read <id>` |
| `src/console.rs` | 210-246 | `parse_console_event()` normalizes only `Runtime.consoleAPICalled` event payloads |
| `src/console.rs` | 249-284 | `parse_console_event_detail()` normalizes only `Runtime.consoleAPICalled` event payloads |
| `src/console.rs` | 374-451 | `execute_read()` subscribes only to `Runtime.consoleAPICalled`, then drains only that receiver |
| `src/console.rs` | 453-469 | Type filters and pagination operate on the incomplete event set |

### Triggering Conditions

- The page throws an uncaught JavaScript exception that Chrome reports through `Runtime.exceptionThrown`.
- The page may also emit explicit `console.error(...)` output, which masks the missing exception by making `--errors-only` look partially successful.
- `console read` is invoked after navigation or runtime interaction and depends on Runtime event replay.
- The agent expects console evidence to include all JavaScript failures, not only calls made through the console API.

---

## Fix Strategy

### Approach

Extend the `console read` collection strategy to subscribe to both `Runtime.consoleAPICalled` and `Runtime.exceptionThrown` before enabling the Runtime domain. Drain both receivers within the existing idle/absolute timeout window, normalize both event shapes into a single internal message representation, then reuse the existing filtering, pagination, plain output, JSON output, and detail output flow.

Exception records should use `type: "error"` so `--errors-only` and `--type error` include them. The `text` field should prefer `exceptionDetails.exception.description`, then `exceptionDetails.text`, then the thrown object's value or description. Source fields should come from `exceptionDetails.url`, `lineNumber`, and `columnNumber`, falling back to the first `exceptionDetails.stackTrace.callFrames[]` frame when needed. Detail output should expose stack frames from `exceptionDetails.stackTrace` using the existing `StackFrame` shape.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/console.rs` | Add parsing helpers for `Runtime.exceptionThrown` list and detail records. | Keeps CDP-shape-specific extraction isolated instead of forcing exception payloads through `parse_console_event()`. |
| `src/console.rs` | Subscribe to `Runtime.exceptionThrown` before `managed.ensure_domain("Runtime")`. | Ensures replayed exception events are captured alongside replayed console API events. |
| `src/console.rs` | Drain both console and exception receivers in the same timeout loop and merge records in timestamp order before assigning output IDs. | Preserves deterministic output ordering and keeps pagination/detail IDs stable. |
| `src/console.rs` | Apply `resolve_type_filter()`, `filter_by_type()`, `paginate()`, plain output, and `output::emit()` after merging the full message set. | Keeps the existing output contract and large-response summary behavior intact. |
| `src/console.rs` | Add unit coverage for exception parsing, error filtering, detail output stack frames, and merged ordering. | Catches regressions without requiring Chrome for every shape-level assertion. |
| `tests/features/290-fix-console-read-missing-uncaught-page-exceptions.feature` | Add defect regression scenarios for uncaught exception capture, existing filters, and detail mode. | Creates BDD coverage that maps directly to the acceptance criteria. |
| `tests/fixtures/console-read-uncaught-exception.html` | Add a deterministic local fixture that logs explicit errors and throws uncaught exceptions. | Supports the required manual smoke test against a real headless browser. |
| `tests/bdd.rs` | Wire the new feature file into the BDD runner, using the existing Chrome-required scenario pattern. | Keeps regression coverage discoverable in the project harness. |

### Blast Radius

- **Direct impact**: `src/console.rs::execute_read()`, parsing helpers, and unit tests for console read.
- **Indirect impact**: `console read` list mode, detail mode, `--errors-only`, `--type`, `--limit`, `--page`, plain output, JSON output, and large-response summaries all consume the merged record set.
- **Unaffected paths**: `console follow` has an independent event loop and remains unchanged unless helper extraction requires a small shared parser.
- **Risk level**: Medium. The change touches a core debugging command and merges two event streams, but it is contained in one command module and can be guarded with unit, BDD, and real-browser smoke tests.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Merged console and exception events appear out of chronological order. | Medium | Sort normalized records by timestamp before assigning IDs; add unit coverage with interleaved event timestamps. |
| `--errors-only` includes non-error records or excludes exception records. | Low | Normalize exception records as `type: "error"` and extend filter unit tests. |
| Detail IDs shift after pagination or filtering in a confusing way. | Medium | Preserve existing behavior by assigning IDs before filters and using the same collected message set for detail lookup. Document and test expected ID handling. |
| Exception source fields are blank on browsers that omit top-level URL/line fields. | Medium | Fall back to `exceptionDetails.stackTrace.callFrames[0]` for URL, line, and column. |
| `console follow` behavior changes accidentally. | Low | Do not modify `execute_follow()` except for purely shared helpers; run existing console follow tests. |
| Large-response summary counts omit exception records. | Low | Feed the merged list into the existing `summary_of_read()` path so `error_count` includes exception records. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Subscribe only to `Log.entryAdded`. | Use the CDP Log domain as a broader error source. | It does not preserve the existing console read contract and may not carry the same argument/source detail as Runtime events. |
| Print exception events separately to stderr. | Keep console output unchanged and emit exceptions as diagnostic errors. | Violates AgentChrome's structured stdout contract and makes agents merge two evidence channels manually. |
| Add a new `console exceptions` subcommand. | Keep `console read` unchanged and expose exceptions separately. | The user asked for complete `console read --errors-only` evidence; a new command would leave the original debugging path incomplete. |
| Implement a persistent recorder daemon. | Capture every console and exception event over time in a background process. | Larger architecture change, not needed for the replay-buffer defect, and explicitly out of scope. |

---

## Validation Checklist

- [x] Root cause is identified with specific code references
- [x] Fix is minimal - no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #290 | 2026-05-26 | Initial defect analysis |
