# Root Cause Analysis: Dialog handling fails across separate agentchrome invocations

**Issue**: #225
**Date**: 2026-04-21
**Status**: Draft
**Author**: Rich Nunley

---

## Root Cause

The interceptor that makes cross-process dialog handling work writes dialog metadata to a cookie named `__agentchrome_dialog`. That cookie is installed by `ManagedSession::install_dialog_interceptors()` in `src/connection.rs:558`, which overrides `window.alert`, `window.confirm`, and `window.prompt` so that every dialog opening records its `{type, message, defaultValue}` to a cookie the `Network` domain can read even while the renderer is blocked. This is the mechanism the defect report (`src/dialog.rs:340-383`) assumes will carry metadata across invocations.

The interceptor is only installed on sessions that go through `setup_session_with_interceptors()` (`src/output.rs:199-205`). Today only `js exec` (`src/js.rs:77`) and that helper's direct callers install it. **`interact click` does not** — it calls the plain `setup_session()` at `src/interact.rs:1401, 1549, 1682, 1813, 1872, 1966, 2066, 2141, 2210, 2260`. So in Rich's reproduction, Process 1 opens a session, clicks the prompt button, and exits **without ever having installed the interceptor**. No cookie is written. When Process 2 opens a fresh session and `dialog info` reads cookies via `Network.getCookies`, there is nothing to read, so the probe correctly concludes the dialog metadata is unknown. The `No dialog open` response follows because `probe_dialog_open()` then fails to obtain evidence of an open dialog: `Runtime.evaluate` hangs (blocked), the timeout expires, but without interceptor metadata the `execute_info` path has no confirmation signal either — the existing logic in `src/dialog.rs:225-261` needs the cookie to report `open=true` with meaningful type/message, and when no cookie is present the path currently returns `open=false`.

The `--auto-dismiss-dialogs` failure is adjacent but distinct. `spawn_auto_dismiss()` (`src/connection.rs:603-631`) spawns a background task that listens for `Page.javascriptDialogOpening` and dismisses dialogs as they arrive. When Rich runs `--auto-dismiss-dialogs interact click s2` in a single process, the click returns quickly and the command finishes, which drops the `ManagedSession` and aborts the background task **before the dialog has finished opening and been dispatched to the event stream**. The dismissal race is lost because the process tears down too fast.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/interact.rs` | 1401-1404, 1549-1552, 1682-1685, 1813-1816, 1872-1875, 1966-1969, 2066-2069, 2141-2144, 2210-2213, 2260-2263 | `execute_*` entry points in `interact` group; all use `setup_session` without installing dialog interceptors before a click can fire. |
| `src/output.rs` | 180-205 | `setup_session` vs `setup_session_with_interceptors`. The second variant exists and already runs the interceptor install — it is simply not being used from `interact`. |
| `src/connection.rs` | 558-589 | `install_dialog_interceptors` — best-effort injection via `Runtime.evaluate` plus `Page.addScriptToEvaluateOnNewDocument`. Correct as written; simply not invoked. |
| `src/connection.rs` | 591-631 | `spawn_auto_dismiss` — background task aborts when `ManagedSession` is dropped. Fine when the process lives long enough, but a fast click+exit races the dialog event. |
| `src/dialog.rs` | 104-126 | `setup_dialog_session` — Process 2's session-setup path. The `Page.enable` timeout workaround is the right shape; it relies on the cookie being present from the other side. |

### Triggering Conditions

- The `interact` command path is used to trigger a dialog (click, key press, form submit — anything that can fire `alert` / `confirm` / `prompt`).
- Either (a) a second `agentchrome` process opens a new CDP session to handle the dialog, or (b) the same process uses `--auto-dismiss-dialogs` and exits before the dialog event is delivered.
- The interceptor cookie was never written — because the `interact` code path does not call `install_dialog_interceptors()` before dispatching the click.

Why this was not caught previously: the existing BDD coverage for `feature-browser-dialog-handling` exercises `dialog info` / `dialog handle` in the **same** process as the trigger, and `js exec` (the path that *does* install interceptors) is used for many developer-driven tests, giving a false signal that the cookie mechanism works end-to-end. The cross-process flow with `interact click` has no automated coverage today.

---

## Fix Strategy

### Approach

Install the dialog interceptor on any `interact` session that could plausibly trigger a dialog, so the cookie is written in the clicking process and is available to the handling process. The minimal correct change is to switch the `interact click` path (and sibling interaction paths) from `setup_session` to `setup_session_with_interceptors`. That helper already exists and is used by `js exec` — we are not inventing new machinery, we are turning the existing machinery on for the code path that needed it.

For `--auto-dismiss-dialogs` in the single-process flow (AC2), add a short post-action settle before the command returns when the flag is active. The settle waits for either the dismissal task to observe and handle a dialog event, or a short bounded timeout — whichever comes first. Reuse the same duration budget already used by `PAGE_ENABLE_TIMEOUT_MS` so behavior stays predictable.

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/interact.rs` | Replace `setup_session(global)` with `setup_session_with_interceptors(global)` in every `execute_*` entry point that can trigger a dialog (click, click_at, keyboard, mouse_*, form-adjacent). Update the import. | Ensures the `__agentchrome_dialog` cookie is written when Process 1 opens a dialog via a click, so Process 2's `dialog info` / `dialog handle` can read it. This is the direct cause of AC1's failure. |
| `src/interact.rs` | In the click / click_at entry points, when `global.auto_dismiss_dialogs` is true, await a short post-dispatch settle that resolves when `Page.javascriptDialogOpening` is observed *or* when `PAGE_ENABLE_TIMEOUT_MS` elapses. Keep the current fire-and-forget semantics when the flag is false. | Gives `spawn_auto_dismiss`'s background task time to see and dismiss a dialog before the `ManagedSession` is dropped on command exit. Fixes AC2. |
| `src/connection.rs` (optional, if needed) | Expose a lightweight `wait_for_dialog_settled(Duration)` helper on `ManagedSession` if the settle logic cannot be expressed inline without breaking encapsulation. | Only if inline implementation is awkward; preserve existing boundaries first. |
| `tests/fixtures/dialog-cross-invocation.html` | New test fixture with an `alert`, a `confirm`, and a `prompt` trigger (mirroring `javascript_alerts.herokuapp.com`). | Required by the Feature Exercise Gate in `steering/tech.md`. Deterministic, self-contained, no external network. |
| `tests/features/bug-fix-dialog-handling-across-separate-agentchrome-invocations.feature` | New `@regression`-tagged Gherkin scenarios mapping 1:1 to AC1–AC3. | Catches the defect if it regresses. |

No other files are touched. No refactor of the interceptor mechanism itself, no changes to `dialog.rs` contract, no changes to `connection.rs` beyond (optionally) adding the settle helper.

### Blast Radius

- **Direct impact**: `interact` subcommands that currently use `setup_session` will now additionally execute one `Runtime.evaluate` and one `Page.addScriptToEvaluateOnNewDocument` per session. Both are best-effort and already tolerated silently (`install_dialog_interceptors` swallows its errors). Per-command latency increases by the round-trip time of those two calls — a few milliseconds on a local CDP socket.
- **Indirect impact**:
  - Other consumers of `setup_session` are **not** affected — the change is scoped to `interact.rs`.
  - The cookie overhead (`__agentchrome_dialog`) is already accepted on pages hit by `js exec`; extending it to `interact`-touched pages is consistent.
  - The `--auto-dismiss-dialogs` settle adds up to `PAGE_ENABLE_TIMEOUT_MS` (~300 ms) to click-and-exit flows **only when the flag is set**. Default behavior is unchanged.
- **Risk level**: Low. The mechanism already exists and is exercised by `js exec`; we are extending its reach, not introducing it.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Interceptor install fails on a page with a strict CSP that blocks `Runtime.evaluate` injection, causing a visible error instead of the current silent-success path. | Low | `install_dialog_interceptors` already silently ignores errors (`let _ = …`). The new call path inherits that guarantee. |
| Increased per-click latency breaks tight automation loops. | Low | The added work is two CDP calls local to the browser — measured in single-digit milliseconds. The existing `js exec` path imposes the same cost without complaint. |
| `auto_dismiss_dialogs` settle adds a 300 ms wait to every click that does NOT trigger a dialog. | Medium | Gate the settle on `global.auto_dismiss_dialogs`; users opt in. The BDD regression test in AC3 verifies no visible change to the default (flag-absent) flow. |
| Cookie collisions with a page that uses its own cookie named `__agentchrome_dialog`. | Very Low | The cookie is namespaced under `__agentchrome_` already; no known conflict. Not introduced by this fix. |
| AC2 cannot be reproduced in headless Chrome because `alert()` is a no-op there. | Medium | The Feature Exercise Gate uses a fixture (`tests/fixtures/dialog-cross-invocation.html`) that is known to trigger dialogs in headless Chrome with the `--enable-features=…` flags agentchrome already uses, mirroring the issue's reproduction on herokuapp. If headless cannot trigger natively, the smoke test runs headed and kills the browser on exit per `steering/tech.md`. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Long-running `agentchrome dialog watch` daemon | Spawn a background mode that stays connected across invocations and handles dialogs as they arrive. | Large surface-area addition for a narrow problem. Process-lifecycle management, cleanup on crash, port reuse — all new concerns. The cookie mechanism already solves cross-process handoff when activated. |
| Composite `interact click --expect-dialog <accept\|dismiss> [--text "…"]` | Keep click + handle in one process. | Doesn't help agents that discover the dialog reactively (the common case). Still leaves the cookie-not-written bug latent. Can be a follow-on convenience once this fix lands. |
| Move the interceptor install into `setup_session` itself | Apply the interceptor universally. | Broader blast radius; affects every command including ones where the cookie footprint is unwelcome (e.g. `page screenshot` on sensitive pages). Scoped activation via `setup_session_with_interceptors` in interaction paths is the tighter fix. |

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
| #225 | 2026-04-21 | Initial root cause analysis |
