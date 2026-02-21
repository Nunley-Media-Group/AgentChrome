# Defect Report: Clap Argument Validation Errors Output Non-JSON stderr and Wrong Exit Code

**Issue**: #98
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/3-cli-skeleton/`

---

## Reproduction

### Steps to Reproduce

1. Run a command with mutually exclusive flags: `agentchrome interact scroll --to-top --to-bottom`
2. Observe stderr output: `error: the argument '--to-top' cannot be used with '--to-bottom'`
3. Observe exit code: 2

Additional triggers:
- Invalid enum value: `agentchrome emulate set --network invalid-profile`
- Out-of-range value: `agentchrome emulate set --cpu 0`
- Conflicting flags with values: `agentchrome emulate set --geolocation "37.7,-122.4" --no-geolocation`
- Conflicting output format flags: `agentchrome --json --plain navigate`

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS (Darwin 25.3.0) |
| **Version / Commit** | `c584d2d` (main) |
| **Browser / Runtime** | N/A (bug is in CLI argument parsing, before Chrome connection) |

### Frequency

Always — every clap validation error triggers this behavior.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | stderr contains a JSON error object `{"error":"...","code":1}` and exit code is 1 (general error / invalid arguments) |
| **Actual** | stderr contains clap's default plain-text error format and exit code is 2 (which agentchrome defines as "connection error") |

### Error Output

```
# Actual stderr (plain text, not JSON):
error: the argument '--to-top' cannot be used with '--to-bottom'

Usage: agentchrome interact scroll [OPTIONS]

For more information, try '--help'.

# Expected stderr (JSON):
{"error":"the argument '--to-top' cannot be used with '--to-bottom'","code":1}
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Mutually exclusive flags produce JSON error with exit code 1

**Given** I run a command with conflicting flags (e.g., `--to-top --to-bottom`)
**When** clap rejects the arguments
**Then** stderr contains a single JSON error object with `error` and `code` fields
**And** exit code is 1

**Example**:
- Given: agentchrome is built
- When: I run `agentchrome interact scroll --to-top --to-bottom`
- Then: stderr is valid JSON with `error` containing "cannot be used with" and `code` equal to 1, and exit code is 1

### AC2: Invalid enum values produce JSON error with exit code 1

**Given** I run a command with an invalid enum value (e.g., `--network invalid-profile`)
**When** clap rejects the value
**Then** stderr contains a JSON error object mentioning the invalid value
**And** exit code is 1

**Example**:
- Given: agentchrome is built
- When: I run `agentchrome emulate set --network invalid-profile`
- Then: stderr is valid JSON with `error` containing "invalid value" and `code` equal to 1, and exit code is 1

### AC3: Out-of-range values produce JSON error with exit code 1

**Given** I run a command with an out-of-range value (e.g., `--cpu 0`)
**When** clap rejects the value
**Then** stderr contains a JSON error object with context about the valid range
**And** exit code is 1

**Example**:
- Given: agentchrome is built
- When: I run `agentchrome emulate set --cpu 0`
- Then: stderr is valid JSON with `error` containing "not in" and `code` equal to 1, and exit code is 1

### AC4: Existing JSON error behavior is preserved for non-clap errors

**Given** I run a command that triggers a non-clap error (e.g., `agentchrome dom`)
**When** the application-level error handler formats the error
**Then** stderr contains a JSON error object with `error` and `code` fields
**And** the exit code matches the existing behavior (exit code 1 for not-implemented)

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | All clap argument validation errors must produce JSON on stderr (not plain text) | Must |
| FR2 | Clap argument validation errors must use exit code 1 (`GeneralError`), not exit code 2 | Must |
| FR3 | JSON error message should preserve clap's helpful context (valid options, ranges, conflict details) | Should |
| FR4 | The existing `cli-skeleton.feature` test for conflicting flags must be updated to expect exit code 1 and JSON stderr | Must |

---

## Out of Scope

- Changing clap's internal error types or validation logic
- Adding custom validation beyond what clap provides
- Reformatting clap's error messages (preserve the original wording)
- Intercepting `--help` or `--version` output (these are informational, not errors)

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC4)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
