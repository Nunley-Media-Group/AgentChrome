# Defect Report: console read misses uncaught page exceptions

**Issue**: #290
**Date**: 2026-05-26
**Status**: Draft
**Author**: Codex (write-spec)
**Severity**: High
**Related Spec**: specs/feature-console-read-runtime-messages/

---

## Reproduction

### Steps to Reproduce

1. Start a page that emits `console.error("Login validation setup failed: selector #missing-password returned null")` during load.
2. On the same page load, throw an uncaught exception such as `TypeError: Cannot read properties of null (reading 'addEventListener')`.
3. Run `agentchrome connect --launch --headless`.
4. Run `agentchrome navigate <fixture-url> --wait-until networkidle`.
5. Run `agentchrome console read --errors-only`.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS local benchmark environment |
| **Version / Commit** | AgentChrome 1.62.0 |
| **Browser / Runtime** | Google Chrome 148.0.7778.97 via CDP |
| **Configuration** | Default headless AgentChrome session |

### Frequency

Always for pages where the only uncaught failure is delivered through `Runtime.exceptionThrown` instead of `Runtime.consoleAPICalled`.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `agentchrome console read --errors-only` returns both the explicit `console.error(...)` record and the uncaught exception record. Each record is machine-readable and includes type, text, timestamp, and source fields where CDP provides them. |
| **Actual** | `agentchrome console read --errors-only` returns the explicit `console.error(...)` entry but omits the uncaught `TypeError`, leaving agents with incomplete JavaScript failure evidence. |

### Error Output

```text
Login validation setup failed: selector #missing-password returned null
```

The command exits successfully but omits the uncaught exception text:

```text
TypeError: Cannot read properties of null (reading 'addEventListener')
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Uncaught exceptions appear in errors-only console reads

**Given** a page logs `console.error(...)` and then throws an uncaught `TypeError` during the same load
**When** I run `agentchrome console read --errors-only`
**Then** the output includes one error record for the explicit console error
**And** the output includes one error record for the uncaught `TypeError`
**And** both records expose `type`, `text`, `timestamp`, `url`, `line`, and `column` fields where CDP provides them

### AC2: Existing console filters and pagination still work

**Given** a page emits log, warn, explicit error, and uncaught exception events
**When** I run `agentchrome console read`, `agentchrome console read --errors-only`, `agentchrome console read --type warn`, and `agentchrome console read --limit 2`
**Then** the existing type filtering and pagination behavior is preserved
**And** uncaught exception records are included only in error-level result sets unless no error filter is applied

### AC3: Detail mode includes exception source context

**Given** `agentchrome console read --errors-only` returns an uncaught exception record with an `id`
**When** I run `agentchrome console read <id>`
**Then** the detail output includes the exception text
**And** the detail output includes stack trace frames when CDP provides `exceptionDetails.stackTrace`

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `console read` must subscribe to and drain `Runtime.exceptionThrown` events in addition to `Runtime.consoleAPICalled` events. | Must |
| FR2 | Uncaught exceptions must be normalized into the existing `ConsoleMessage` and `ConsoleMessageDetail` output contracts rather than printed as unstructured stderr. | Must |
| FR3 | `--errors-only` must include uncaught exception records as error-level output. | Must |
| FR4 | `--type warn`, `--type error`, `--limit`, `--page`, plain output, JSON output, and detail lookup behavior must remain compatible with the existing console read contract. | Must |
| FR5 | The implementation must preserve existing `console follow` behavior unless a shared helper extraction is required; streaming exception monitoring is out of scope for this defect. | Should |

---

## Out of Scope

- README, Codex guide, or benchmark-positioning updates.
- Playwright CLI, Playwright MCP, or Chrome DevTools CLI benchmark follow-up work.
- Installed Codex skill version drift or stale-skill warning behavior.
- A persistent background console recorder.
- Changing `console follow` to stream `Runtime.exceptionThrown` events.

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included
- [x] Fix scope is minimal - no feature work mixed in
- [x] Out of scope is defined

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #290 | 2026-05-26 | Initial defect report |
