# Defect Report: dialog handle fails with 'no dialog open' even when dialog info shows open:true

**Issue**: #99
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/20-browser-dialog-handling/` and `.claude/specs/86-fix-dialog-commands-timeout-with-open-dialog/`

---

## Reproduction

### Steps to Reproduce

1. `agentchrome connect --launch --headless`
2. `agentchrome navigate https://www.google.com --wait-until load`
3. `agentchrome js exec --no-await "setTimeout(() => alert('test alert'), 100); 'triggered'"`
4. `sleep 2`
5. `agentchrome dialog info` — returns `{"open":true,"type":"unknown","message":""}`
6. `agentchrome dialog handle accept` — returns `{"error":"No dialog is currently open.","code":1}`
7. The dialog remains open and blocks all further CDP operations
8. `agentchrome navigate ... --auto-dismiss-dialogs` also hangs

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS (Darwin 25.3.0) |
| **Version / Commit** | `c584d2d` (main) |
| **Browser / Runtime** | Chrome via CDP (headless) |

### Frequency

Always — 100% reproducible with the steps above.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `dialog info` reports correct `type` and `message`; `dialog handle accept` dismisses the dialog; `--auto-dismiss-dialogs` clears blocking dialogs |
| **Actual** | `dialog info` detects the dialog but reports `type: "unknown"` and `message: ""`; `dialog handle` fails with "No dialog is currently open"; `--auto-dismiss-dialogs` hangs because `spawn_auto_dismiss()` calls `Page.enable` which blocks when a dialog is open |

### Error Output

```
# dialog info output (incorrect type and message):
{"open":true,"type":"unknown","message":""}

# dialog handle output (fails entirely):
{"error":"No dialog is currently open.","code":1}
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Dialog info reports correct type and message

**Given** a JavaScript `alert('test')` dialog is open in the browser
**When** I run `agentchrome dialog info`
**Then** the output shows `type: "alert"` and `message: "test"` and `open: true`

### AC2: Dialog handle accept dismisses alert

**Given** a JavaScript alert dialog is open in the browser
**When** I run `agentchrome dialog handle accept`
**Then** the dialog is dismissed successfully
**And** the output shows `action: "accept"` and `dialog_type: "alert"`

### AC3: Dialog handle dismiss works for confirm

**Given** a JavaScript `confirm('sure?')` dialog is open in the browser
**When** I run `agentchrome dialog handle dismiss`
**Then** the dialog is dismissed with the dismiss result
**And** the output shows `action: "dismiss"` and `dialog_type: "confirm"`

### AC4: Auto-dismiss flag clears blocking dialogs

**Given** a dialog is blocking CDP operations
**When** I run any command with `--auto-dismiss-dialogs`
**Then** the dialog is automatically dismissed and the command proceeds

### AC5: Dialog handle with text for prompt

**Given** a JavaScript `prompt('name?')` dialog is open in the browser
**When** I run `agentchrome dialog handle accept --text "Alice"`
**Then** the dialog is accepted with the provided text
**And** the output shows `dialog_type: "prompt"` and `text: "Alice"`

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `dialog info` must capture dialog type and message from `Page.javascriptDialogOpening` events, even when the dialog opened before the command's CDP session was created | Must |
| FR2 | `dialog handle` must be able to accept/dismiss open dialogs regardless of which CDP session received the original `Page.javascriptDialogOpening` event | Must |
| FR3 | `--auto-dismiss-dialogs` (`spawn_auto_dismiss`) must not call `Page.enable` when a dialog is already blocking, as `Page.enable` hangs in this state | Must |
| FR4 | State must be consistent between `dialog info` and `dialog handle` — if `dialog info` reports `open: true`, then `dialog handle` must be able to act on that dialog | Must |

---

## Out of Scope

- Handling `beforeunload` dialogs (separate behavior, different CDP semantics)
- Automatic dialog recovery without user action
- Persistent dialog state across CLI invocations (no state file needed)
- Refactoring beyond the minimal fix for the dialog subsystem

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3 — confirm dialog still works)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
