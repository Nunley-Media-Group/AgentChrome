# Design: JavaScript Execution in Page Context

**Issues**: #13, #183
**Date**: 2026-04-16
**Status**: Draft
**Author**: Claude (writing-specs)

---

## Overview

This feature adds the `js exec` subcommand to execute arbitrary JavaScript in the browser page context. It exposes two CDP methods — `Runtime.evaluate` for expressions and `Runtime.callFunctionOn` for function calls with element context — through a unified CLI interface. The implementation follows the same layered patterns as existing commands (`page`, `perf`, `tabs`): parse CLI args, resolve connection, create a managed CDP session, execute CDP commands, and format output as JSON.

The key design decisions are: (1) using `Runtime.evaluate` with `awaitPromise: true` by default, (2) using `Runtime.callFunctionOn` with `DOM.resolveNode` for the `--uid` element context feature, (3) supporting code input from positional argument, `--file`, or stdin, and (4) capturing console messages via `Runtime.consoleAPICalled` events.

Issue #183 adds three enhancements: (5) wrapping user code in a block scope `{ ... }` to isolate `let`/`const` declarations between invocations, (6) adding `--stdin` as a discoverable boolean flag for stdin input, and (7) adding `--code` as a named argument alternative to the positional `<CODE>` for cross-platform quoting resilience.

---

## Architecture

### Component Diagram

```
CLI Layer (cli/mod.rs)
  └── JsArgs → JsCommand::Exec(JsExecArgs)
        ↓
Command Layer (js.rs)       ← EXISTING FILE (modified)
  └── execute_js() → execute_exec()
        ↓
  ┌─ resolve_code() ← modified: --code, --stdin support
  │   ├── --file <PATH>: read file
  │   ├── --stdin: read from stdin
  │   ├── code == "-": read from stdin (legacy)
  │   ├── --code <CODE>: named inline code
  │   └── <CODE> (positional): inline code
  │
  └─ Block-scope wrapping ← NEW
      └── wraps code as "{ <user_code> }" before evaluation
        ↓
Connection Layer (connection.rs)  ← existing
  └── resolve_connection() → resolve_target() → ManagedSession
        ↓
CDP Layer (cdp/client.rs)     ← existing
  ├── Runtime.evaluate({ expression, awaitPromise, returnByValue })
  ├── Runtime.callFunctionOn({ functionDeclaration, objectId })
  ├── Runtime.consoleAPICalled (event subscription)
  └── DOM.resolveNode({ backendNodeId })
        ↓
Chrome Browser
  └── Executes JS, returns result
```

### Data Flow

```
1. User runs: agentchrome js exec <CODE> [--code CODE] [--stdin] [--file PATH] [--uid UID] [--no-await] [--timeout MS] [--max-size N]
2. CLI layer parses args into JsExecArgs
3. Resolve code source (priority order):
   a. If --file: read file contents
   b. If --stdin: read stdin to string
   c. If code is "-": read stdin (legacy behavior, preserved)
   d. If --code: use named argument value
   e. If positional <CODE>: use positional argument directly
   f. None of the above: return no_js_code error
4. Apply block-scope wrapping: code becomes "{ <original_code> }"
   - Exception: --uid path does NOT wrap (code is a function declaration for callFunctionOn)
5. Command layer resolves connection and target tab (standard setup_session)
6. Creates CdpSession via Target.attachToTarget
7. Enables Runtime domain (via ManagedSession.ensure_domain)
8. Subscribe to Runtime.consoleAPICalled for console capture
9. Branch on --uid:
   a. Without --uid: Runtime.evaluate with wrapped expression
   b. With --uid:
      i.   Read snapshot state → resolve UID to backendNodeId
      ii.  Enable DOM domain
      iii. DOM.resolveNode({ backendNodeId }) → get remote objectId
      iv.  Runtime.callFunctionOn({ functionDeclaration, objectId, arguments: [objectId] })
           (no block wrapping — code is used as-is as a function declaration)
10. Handle result:
    - Success → JsExecResult { result, type, console, truncated }
    - Exception → structured error with error message + stack trace
    - Timeout → timeout error
11. Apply --max-size truncation if result exceeds limit
12. Format output via print_output (JSON / pretty JSON)
```

---

## API / Interface Changes

### New CLI Commands

| Command | Purpose |
|---------|---------|
| `agentchrome js exec <CODE>` | Execute JavaScript in the page context |

### CLI Arguments (JsExecArgs)

| Argument | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `<code>` | `Option<String>` (positional) | Conditional | None | JavaScript code to execute; `-` reads stdin |
| `--code <CODE>` | `Option<String>` (named) | No | None | JavaScript code as a named argument (cross-platform quoting) |
| `--stdin` | `bool` (flag) | No | `false` | Read JavaScript code from stdin |
| `--file <PATH>` | `Option<PathBuf>` | No | None | Read JavaScript from a file |
| `--uid <UID>` | `Option<String>` | No | None | Element UID from snapshot; function receives element as first arg |
| `--no-await` | `bool` (flag) | No | `false` | Do not await promise results |
| `--timeout <MS>` | `Option<u64>` | No | Global timeout | Execution-specific timeout override |
| `--max-size <BYTES>` | `Option<usize>` | No | None (unlimited) | Truncate results exceeding this size |

Global flags `--tab`, `--json`, `--pretty`, `--plain`, `--host`, `--port`, `--ws-url` all apply as usual.

**Mutual exclusion**: The following are mutually exclusive code sources — only one may be specified:
- Positional `<code>` argument
- `--code <CODE>` named argument
- `--stdin` flag
- `--file <PATH>` flag

### Output Schema

**JSON mode** (success):

```json
{
  "result": "Example Domain",
  "type": "string"
}
```

With console output:

```json
{
  "result": 42,
  "type": "number",
  "console": [
    { "level": "log", "text": "hello" }
  ]
}
```

With truncation:

```json
{
  "result": "xxxxxxxxxx...",
  "type": "string",
  "truncated": true
}
```

**Error output** (stderr):

```json
{
  "error": "ReferenceError: foo is not defined",
  "stack": "ReferenceError: foo is not defined\n    at <anonymous>:1:1",
  "code": 1
}
```

### Errors

| Condition | Error Message | Exit Code |
|-----------|---------------|-----------|
| JS exception | `"JavaScript execution failed: {description}"` | `GeneralError` (1) |
| File not found | `"Script file not found: {path}"` | `GeneralError` (1) |
| File read error | `"Failed to read script file: {path}: {error}"` | `GeneralError` (1) |
| UID not found | Existing `uid_not_found` | `GeneralError` (1) |
| No snapshot | `"No snapshot state found. Run 'agentchrome page snapshot' first."` | `GeneralError` (1) |
| No code provided | `"No JavaScript code provided. Specify code as argument, --code, --file, or pipe via --stdin."` | `GeneralError` (1) |
| No connection | Existing `no_session` / `no_chrome_found` | `ConnectionError` (2) |
| Tab not found | Existing `target_not_found` | `TargetError` (3) |
| Timeout | Existing `command_timeout` from CDP layer | `TimeoutError` (4) |

---

## Scope Isolation Design (Issue #183)

### Problem

`Runtime.evaluate` executes code in the page's global execution context. `let` and `const` declarations create bindings in the script scope that persist across invocations. Sequential calls like:

```
js exec "let x = 1"
js exec "let x = 2"   // SyntaxError: Identifier 'x' has already been declared
```

### Solution: Block-Scope Wrapping

Wrap user-provided code in a JavaScript block statement `{ ... }` before passing to `Runtime.evaluate`:

```
User code:     let x = 1; x + 1
Wrapped code:  { let x = 1; x + 1 }
```

**Why block wrapping over alternatives:**

| Property | Block `{ ... }` | IIFE `(() => { ... })()` | Isolated World |
|----------|-----------------|--------------------------|----------------|
| `let`/`const` isolation | Yes | Yes | Yes |
| `var` isolation | No | Yes | Yes |
| Expression return value | Preserved (last expression) | Requires explicit `return` | Preserved |
| `window.` globals persist | Yes | Yes | No |
| `this` context | Unchanged | Changed (arrow) or bound | Separate |
| Extra CDP round-trip | No | No | Yes (`createIsolatedWorld`) |
| Top-level `await` | Works | Requires async IIFE | Works |

Block wrapping is selected because:
1. It isolates `let`/`const` (the reported problem) without changing expression semantics
2. It preserves return values — `{ document.title }` evaluates to the title
3. It allows intentional `window.` global sharing (per Out of Scope)
4. Zero overhead — no extra CDP calls, no function wrapper

**When NOT to wrap:** Code provided via `--uid` is passed to `Runtime.callFunctionOn` as a `functionDeclaration`, not as an expression to `Runtime.evaluate`. Function declarations are inherently scope-isolated, so no wrapping is needed.

### Implementation Location

In `js.rs`, in the `execute_expression_with_context()` function (and `execute_expression()`), wrap the expression before building the CDP params:

```rust
// Before: expression passed directly
let wrapped = format!("{{ {code} }}");
let params = serde_json::json!({
    "expression": wrapped,
    ...
});
```

---

## `--stdin` Flag Design (Issue #183)

### Problem

Reading code from stdin currently requires the `-` positional argument convention, which is not discoverable via `--help` and can be confusing for users unfamiliar with Unix conventions.

### Solution

Add a `--stdin` boolean flag to `JsExecArgs`:

```rust
/// Read JavaScript code from stdin
#[arg(long, conflicts_with_all = ["code", "code_flag", "file"])]
pub stdin: bool,
```

In `resolve_code()`, add a check for `args.stdin` that reads from stdin:

```rust
if args.stdin {
    return std::io::read_to_string(std::io::stdin())
        .map_err(|e| AppError::script_file_read_failed("stdin", &e.to_string()));
}
```

The existing `-` convention continues to work for backward compatibility.

---

## `--code` Named Argument Design (Issue #183)

### Problem

On Windows PowerShell, positional arguments containing single quotes, backslashes, or special characters are subject to platform-specific quoting rules that differ from Bash/Zsh. This causes `SyntaxError` for valid JavaScript like `document.querySelector('div')`.

### Solution

Add `--code` as a named argument alternative to the positional `<code>`:

```rust
/// JavaScript code as a named argument (avoids shell quoting issues)
#[arg(long = "code", id = "code_flag", conflicts_with_all = ["code", "stdin", "file"])]
pub code_flag: Option<String>,
```

In `resolve_code()`, check `code_flag` in addition to the positional `code`:

```rust
// After --file and --stdin checks:
if let Some(ref code) = args.code_flag {
    return Ok(code.clone());
}
if let Some(ref code) = args.code {
    // existing positional handling...
}
```

**Note on `--code` vs positional mutual exclusion**: clap's `conflicts_with` ensures that providing both `--code "x"` and a positional `"y"` produces a clear error message. The positional argument remains the primary interface for simple cases; `--code` is recommended when cross-platform quoting is a concern.

---

## New Files and Modifications

### New Files

None — all changes modify existing files.

### Modified Files

| File | Change |
|------|--------|
| `src/cli/mod.rs` | Add `--stdin` flag and `--code` named argument to `JsExecArgs`; update mutual exclusion constraints |
| `src/js.rs` | (1) Block-scope wrap expressions in `execute_expression*()` functions; (2) Update `resolve_code()` to handle `--stdin` and `--code`; (3) Update `no_js_code` error message to mention new flags |

### No Changes Needed

| Component | Why |
|-----------|-----|
| `src/main.rs` | `js` command dispatch is already wired |
| `src/error.rs` | Existing error helpers are sufficient; only the `no_js_code` message text changes (in `js.rs`) |
| `src/cdp/*` | No CDP protocol changes needed |
| `src/connection.rs` | No connection changes needed |

---

## JavaScript Execution Strategies

### Strategy 1: Expression evaluation (no --uid) — UPDATED

Uses `Runtime.evaluate` with block-scope wrapping:

```json
{
  "expression": "{ <user code> }",
  "returnByValue": true,
  "awaitPromise": true,
  "generatePreview": true
}
```

- Expression is wrapped in `{ ... }` for scope isolation
- `returnByValue: true` ensures we get the serialized value, not a remote object reference
- `awaitPromise: true` (default) waits for promises; disabled by `--no-await`
- `generatePreview: true` provides useful string representations for complex objects

### Strategy 2: Element context execution (--uid) — UNCHANGED

Uses `DOM.resolveNode` + `Runtime.callFunctionOn`:

```
Step 1: Read snapshot state → get backendNodeId for UID
Step 2: DOM.resolveNode({ backendNodeId }) → get objectId (remote object reference)
Step 3: Runtime.callFunctionOn({
  functionDeclaration: "<user code>",
  objectId: <resolved objectId>,
  arguments: [{ objectId: <resolved objectId> }],
  returnByValue: true,
  awaitPromise: true
})
```

No block wrapping applied — the code is already a function declaration with its own scope.

### Console Capture

Before executing user code, subscribe to `Runtime.consoleAPICalled` events:

```
1. managed.subscribe("Runtime.consoleAPICalled")
2. Execute user code
3. Collect any console events received during execution
4. Include in output as "console" array
```

Each console entry: `{ "level": "log|warn|error|info", "text": "<message>" }`.

### Result Truncation (--max-size)

After receiving the result, check its serialized JSON size against `--max-size`:

```
1. Serialize result to JSON string
2. If byte length > max_size:
   a. Truncate the serialized string to max_size bytes
   b. Set truncated = true in output
3. Otherwise: use full result, omit truncated field
```

---

## Code Resolution Priority (Updated)

The `resolve_code()` function checks code sources in this priority order:

```
1. --file <PATH>  →  read file contents
2. --stdin        →  read stdin to string
3. code == "-"    →  read stdin (legacy convention)
4. --code <CODE>  →  use named argument value
5. <CODE>         →  use positional argument
6. (none)         →  error: no JavaScript code provided
```

Mutual exclusion is enforced by clap `conflicts_with_all` annotations, so at most one source is active at runtime.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: `Runtime.evaluate` only** | Use `evaluate` for all cases, wrap element into expression | Simple, single code path | Cannot pass live DOM element references; would need to re-query by selector | Rejected — cannot reliably pass element context |
| **B: `Runtime.evaluate` + `callFunctionOn`** | Use `evaluate` for expressions, `callFunctionOn` for `--uid` | Clean separation, correct semantics for element context | Two code paths | **Selected** — matches CDP design intent |
| **C: Wrap user code in IIFE** | Always wrap in `(() => { ... })()` | Full scope isolation (var, let, const) | Breaks expression return values (requires explicit `return`), changes `this` context | Rejected — too disruptive to expression semantics |
| **D: `Page.createIsolatedWorld`** | Create a fresh execution context per invocation | Complete isolation | Prevents intentional `window.` global sharing; extra CDP round-trip per call | Rejected — too aggressive; breaks cross-invocation state sharing |
| **E: Block scope wrapping `{ ... }`** | Wrap user code in a block statement | Isolates `let`/`const`, preserves expression return values, zero overhead | Does not isolate `var` (acceptable per Out of Scope) | **Selected for scope isolation** — minimal, correct |

---

## Security Considerations

- [x] **No sandboxing needed**: This is a power-user tool; the user controls the browser and the code they execute. The issue explicitly states "no sandboxing needed."
- [x] **Local CDP only**: CDP connections are localhost-only by default (per `tech.md`), so remote code execution is not a concern.
- [x] **File access**: `--file` reads local files, which is standard CLI behavior. No path traversal concern since the user controls the argument.
- [x] **stdin**: Reading from stdin is standard Unix pipeline behavior. `--stdin` flag is a discoverable alias.
- [x] **Block wrapping**: Wrapping in `{ ... }` does not introduce injection risk — the user already controls the code being executed.
- [x] **No new argument collisions**: `--code` and `--stdin` do not collide with any global flags or framework-reserved names.

---

## Performance Considerations

- [x] **Single CDP round-trip** for expressions (Runtime.evaluate) — unchanged by block wrapping
- [x] **Two CDP round-trips** for element context (DOM.resolveNode + Runtime.callFunctionOn)
- [x] **`returnByValue: true`** avoids an extra round-trip to fetch remote objects
- [x] **Console subscription** is lightweight — events arrive asynchronously during execution
- [x] **Truncation** happens client-side after receiving the full result (no way to limit at CDP level)
- [x] **Block wrapping** adds negligible string concatenation overhead (one `format!` call)

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Output types | Unit | Serialization of `JsExecResult`, `JsExecError` (JSON fields, skip_serializing_if) |
| Error helpers | Unit | New error constructors produce correct messages and exit codes |
| Code resolution | Unit | Positional arg, `--code`, `--stdin`, `--file`, `-`, mutual exclusion |
| Block wrapping | Unit | Verify expressions are wrapped as `{ <code> }` for evaluate path; verify no wrapping for `--uid` path |
| Result type mapping | Unit | All 7 JS types → correct `type` string |
| Truncation logic | Unit | Result exceeds --max-size, truncated flag set |
| Feature | BDD (Gherkin) | All 19 acceptance criteria as scenarios |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Large JS results cause memory pressure | Low | Med | `--max-size` truncation; `returnByValue: true` streams result directly |
| `DOM.resolveNode` fails for stale snapshots | Med | Low | Clear error message: "Run `page snapshot` first" |
| Console capture races (messages arrive after result) | Low | Low | Small delay or drain after receiving result; console messages are best-effort |
| Stdin blocks indefinitely if no data piped | Low | Med | Document that `--stdin` reads until EOF; bounded by global `--timeout` |
| Block wrapping changes object literal parsing | Low | Low | `{key: "val"}` is already a labeled statement without block wrapping; users must use `({key: "val"})` in both cases — no semantic change |
| `--code` and positional `<code>` confusion | Low | Low | clap produces a clear error if both are provided; `--help` documents both forms |

---

## Open Questions

None — all questions resolved.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #13 | 2026-02-12 | Initial design: Runtime.evaluate, callFunctionOn, file/stdin/positional input, console capture |
| #183 | 2026-04-16 | Added block-scope wrapping for isolation, `--stdin` flag, `--code` named argument, updated code resolution priority, new alternatives considered |

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
