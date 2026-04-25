# Defect Report: Fix interact click timeout when JavaScript dialog opens

**Issue**: #267
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Severity**: High
**Related Spec**: `specs/feature-browser-dialog-handling/`

---

## Reproduction

### Steps to Reproduce

1. Start or connect to an isolated headless Chrome session.
2. Run `agentchrome navigate https://the-internet.herokuapp.com/javascript_alerts --wait-until load`.
3. Run `agentchrome interact click 'css:button[onclick="jsAlert()"]'`.
4. Run `agentchrome dialog info`.
5. Run `agentchrome dialog handle accept`.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS 26.3.1 (25D771280a) |
| **Version / Commit** | agentchrome 1.51.2 / `091bac0` |
| **Browser / Runtime** | Google Chrome 147.0.7727.102; `https://the-internet.herokuapp.com/javascript_alerts` |
| **Configuration** | Isolated headless Chrome CDP session |

### Frequency

Always for native alert and prompt buttons observed on the target test page when `--auto-dismiss-dialogs` is not used.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `interact click` reports a deterministic click result when the click opens a native JavaScript dialog, and follow-up `dialog info` / `dialog handle` can proceed. |
| **Actual** | `interact click` exits 5 with `Interaction failed (mouse_release): CDP command timed out: Input.dispatchMouseEvent`, even though `dialog info` then reports the dialog is open. |

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Dialog-opening click does not report generic protocol timeout

**Given** a page button synchronously opens a JavaScript alert
**When** the user runs `agentchrome interact click` on that button without `--auto-dismiss-dialogs`
**Then** AgentChrome does not return a generic `Input.dispatchMouseEvent` timeout as the final result
**And** the user can proceed to `agentchrome dialog info` and `agentchrome dialog handle`

### AC2: Auto-dismiss path remains successful

**Given** the same JavaScript alert button
**When** the user runs `agentchrome --auto-dismiss-dialogs interact click` on that button
**Then** the command exits 0 with the existing clicked JSON shape
**And** no dialog remains open afterward

### AC3: Prompt dialogs are covered

**Given** a page button synchronously opens a JavaScript prompt
**When** the user clicks it through `agentchrome interact click`
**Then** the behavior is deterministic
**And** the prompt can still be accepted with `agentchrome dialog handle accept --text <value>`

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `interact click` and `interact click-at` must detect native dialog-opening click outcomes and avoid surfacing them as generic mouse-release protocol timeouts. | Must |
| FR2 | Existing successful `--auto-dismiss-dialogs` click behavior must remain unchanged. | Must |
| FR3 | Regression coverage must include alert and prompt buttons opened by `interact click` across separate CLI invocations. | Must |

---

## Out of Scope

- Redesigning the dialog command group.
- Adding a composite click-and-handle-dialog command.
- Changing custom in-page modal behavior that is not a native JavaScript dialog.
- Changing file upload or HTTP authentication dialog handling.

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific.
- [x] Expected vs actual behavior is clearly stated.
- [x] Severity is assessed.
- [x] Acceptance criteria use Given/When/Then format.
- [x] At least one regression scenario is included.
- [x] Fix scope is minimal.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #267 | 2026-04-25 | Initial defect report |
