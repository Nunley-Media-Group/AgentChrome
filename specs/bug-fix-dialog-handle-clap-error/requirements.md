# Defect Report: dialog handle --accept flag misleading clap error

**Issue**: #250
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley
**Severity**: Low
**Related Spec**: `specs/feature-browser-dialog-handling/`

---

## Reproduction

### Steps to Reproduce

1. Run `agentchrome dialog handle --accept`.
2. Observe clap's error output on stderr.
3. Follow the printed tip (`use '-- --accept'`) and run `agentchrome dialog handle -- --accept`.
4. Observe a second error — the literal string `--accept` is not a valid `DialogAction`.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS / Linux / Windows (shared clap parsing path) |
| **Version / Commit** | 1.46.0 (branch `250-fix-dialog-handle-clap-error`) |
| **Runtime** | n/a — CLI parsing, no Chrome connection required |
| **Configuration** | Default |

### Frequency

Always.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | When a user writes `dialog handle --accept` (or `--dismiss`), the error message should point them to the correct positional form: `agentchrome dialog handle accept` / `agentchrome dialog handle dismiss`. |
| **Actual** | Clap emits `error: unexpected argument '--accept' found` followed by `tip: to pass '--accept' as a value, use '-- --accept'`. The tip is actively misleading — it leads the user to `dialog handle -- --accept`, which also fails because `--accept` is not a valid `DialogAction` variant. |

### Error Output

```
error: unexpected argument '--accept' found

  tip: to pass '--accept' as a value, use '-- --accept'

Usage: agentchrome dialog handle <ACTION>

For more information, try '--help'.
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Bug Is Fixed — `--accept` yields a corrected hint

**Given** the user runs `agentchrome dialog handle --accept`
**When** clap rejects the unknown flag
**Then** the JSON error on stderr includes a hint pointing to the correct positional syntax: `Did you mean: agentchrome dialog handle accept`

### AC2: Bug Is Fixed — `--dismiss` yields a corrected hint

**Given** the user runs `agentchrome dialog handle --dismiss`
**When** clap rejects the unknown flag
**Then** the JSON error on stderr includes a hint pointing to the correct positional syntax: `Did you mean: agentchrome dialog handle dismiss`

### AC3: No Regression in Valid Usage

**Given** the user runs `agentchrome dialog handle accept` or `agentchrome dialog handle dismiss` with a live dialog
**When** the command is parsed
**Then** parsing succeeds and the command executes exactly as it did before this fix

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Extend `syntax_hint` in `src/main.rs` to recognize `--accept` and `--dismiss` on the `dialog handle` subcommand and emit a `Did you mean: agentchrome dialog handle <accept\|dismiss>` suffix on the JSON error. | Must |
| FR2 | The hint must only fire for `dialog handle` — other subcommands that legitimately accept `--accept` or `--dismiss` flags (none exist today, but the guard keeps the rule targeted) must not be affected. | Must |
| FR3 | The existing `--uid` / `--selector` hint path must continue to work unchanged. | Must |

---

## Out of Scope

- Introducing `--accept` / `--dismiss` as real boolean flag aliases (FR2 "Could" from the issue — rejected in favor of the targeted hint to keep one-way-to-invoke parity with the rest of the CLI).
- Changes to the `--text` flag for prompt dialogs.
- Changes to `dialog info`.
- Any refactor of the clap error-rendering pipeline beyond the hint extension.
- Updating the `--help` synopsis text (FR3 from the issue): clap already renders `<ACTION>` as a positional in the current `Usage:` line, and the existing `after_long_help` EXAMPLES block demonstrates the positional form.

---

## Validation Checklist

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
| #250 | 2026-04-23 | Initial defect report |
