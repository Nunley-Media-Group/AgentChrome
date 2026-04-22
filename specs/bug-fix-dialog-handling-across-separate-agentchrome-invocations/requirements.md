# Defect Report: Dialog handling fails across separate agentchrome invocations

**Issue**: #225
**Date**: 2026-04-21
**Status**: Draft
**Author**: Rich Nunley
**Severity**: High
**Related Spec**: `specs/feature-browser-dialog-handling/`

---

## Reproduction

### Steps to Reproduce

1. `agentchrome connect --launch --headless --port <P>`
2. `agentchrome --port <P> navigate https://the-internet.herokuapp.com/javascript_alerts`
3. `agentchrome --port <P> page snapshot` — confirms `s4 = "Click for JS Prompt"`.
4. `agentchrome --port <P> interact click s4` — returns `Clicked s4`. Process 1 exits immediately.
5. Wait ~1 second.
6. In a **new** process: `agentchrome --port <P> dialog info` — returns `No dialog open` (BUG).
7. `agentchrome --port <P> dialog handle accept --text "Hello agentchrome"` — returns `{"error":"No dialog is currently open. …","code":1}`.
8. `agentchrome --port <P> js exec "document.getElementById('result').innerText"` — returns empty string.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | Windows 11 |
| **Version / Commit** | agentchrome 1.33.1 |
| **Browser / Runtime** | Chrome launched via `connect --launch --headless` |
| **Configuration** | Two separate processes sharing `--port <P>` |

### Frequency

Always — reproducible every run with the steps above.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | Process 2's `dialog info` sees the open dialog and reports its type/message; `dialog handle accept --text "…"` accepts the prompt and the page reflects the entered text. |
| **Actual** | Process 2 reports `No dialog open`. `dialog handle` errors with `No dialog is currently open.` The prompt is never answered and `#result` stays empty. Additionally, `--auto-dismiss-dialogs interact click s2` (JS Alert) also leaves `#result` empty — the auto-dismisser does not fire because Process 1 exits before the dialog opens. |

### Error Output

```
$ agentchrome --port <P> dialog info
No dialog open

$ agentchrome --port <P> dialog handle accept --text "Hello agentchrome"
{"error":"No dialog is currently open. …","code":1}
```

---

## Acceptance Criteria

### AC1: Cross-process prompt accept

**Given** two separate `agentchrome` invocations share the same `--port`
**And** `https://the-internet.herokuapp.com/javascript_alerts` is loaded
**When** Process 1 runs `interact click s4` (opens the JS prompt) and exits
**And** Process 2 runs `dialog info`
**Then** `dialog info` reports `open=true`, `type=prompt`, and a non-empty `message`
**And** `dialog handle accept --text "Hello agentchrome"` succeeds with exit code 0
**And** `document.getElementById('result').innerText` equals `"You entered: Hello agentchrome"`

### AC2: Cross-process alert auto-dismiss

**Given** the same two-process setup as AC1
**When** `agentchrome --auto-dismiss-dialogs --port <P> interact click s2` runs (single process — the alert opens and must be dismissed before that process exits)
**Then** the JS alert is dismissed and no dialog remains blocking the renderer
**And** `document.getElementById('result').innerText` equals `"You successfully clicked an alert"`

### AC3: No regression in single-process flow

**Given** a single `agentchrome` process that triggers a dialog and handles it in the same process
**When** the existing same-process `interact click` → `dialog handle` flow runs
**Then** behavior matches the current contract exactly — same JSON output shape, same exit codes, same plain-text messages

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `interact click` (and any other interaction command that may trigger a dialog) installs the dialog-metadata interceptor on its session **before** dispatching the click, so the cookie is written by Process 1 and readable by Process 2. | Must |
| FR2 | `--auto-dismiss-dialogs` fires correctly when the triggering click and dismissal happen in the same process — the process must not exit before the dialog has been given a chance to open and be dismissed. | Must |
| FR3 | The examples and man-page material for `dialog` / `interact click` demonstrate the cross-process flow end-to-end so AI agents can discover the supported pattern. | Should |

---

## Out of Scope

- Redesigning the cookie-based interceptor mechanism; the existing mechanism is correct, it is simply not being activated on the clicking path.
- Supporting Firefox/Safari dialog handling.
- Rewriting the same-process `dialog info` / `dialog handle` flow beyond what's needed to avoid regression.
- A long-running `dialog watch` daemon mode (mentioned as an alternative in the issue body) — not required once the interceptor is installed on the clicking session.
- A composite `interact click --expect-dialog <accept|dismiss>` flag — not required once FR1 and FR2 are satisfied; may be revisited as a separate enhancement.

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #225 | 2026-04-21 | Initial defect report |
