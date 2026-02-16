# Tasks: Clap Argument Validation Errors Output Non-JSON stderr and Wrong Exit Code

**Issue**: #98
**Date**: 2026-02-15
**Status**: Planning
**Author**: Claude

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Intercept clap validation errors in `main()` | [ ] |
| T002 | Update existing `cli-skeleton.feature` test for corrected behavior | [ ] |
| T003 | Add regression test scenarios for clap validation errors | [ ] |
| T004 | Verify no regressions | [ ] |

---

### T001: Intercept Clap Validation Errors in `main()`

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `Cli::parse()` replaced with `Cli::try_parse()`
- [ ] Clap validation errors (conflicting flags, invalid values, out-of-range) produce JSON on stderr
- [ ] Clap validation errors exit with code 1 (`GeneralError`), not code 2
- [ ] `--help` and `--version` continue to work normally (plain text output, exit code 0)
- [ ] JSON error object contains `error` and `code` fields matching `AppError::to_json()` format
- [ ] Clap's original error message text is preserved in the `error` field
- [ ] No unrelated changes in the diff

**Notes**: Use `Cli::try_parse()` and match on the error. For `ErrorKind::DisplayHelp` and `ErrorKind::DisplayVersion`, print the message as-is and exit with code 0. For all other clap errors, construct an `AppError` with `ExitCode::GeneralError` and call `print_json_stderr()`.

### T002: Update Existing `cli-skeleton.feature` Test

**File(s)**: `tests/features/cli-skeleton.feature`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] "Conflicting output format flags are rejected" scenario updated: exit code changed from 2 to 1
- [ ] Scenario asserts stderr is valid JSON
- [ ] Scenario asserts stderr JSON has `error` and `code` keys
- [ ] Scenario still checks that error message contains "cannot be used with"

**Notes**: The existing test on line 49 expects exit code 2 — this is the documented buggy behavior. Update it to expect exit code 1 and JSON-formatted stderr.

### T003: Add Regression Test Scenarios for Clap Validation Errors

**File(s)**: `tests/features/98-fix-clap-validation-json-stderr.feature`
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] Gherkin scenario for mutually exclusive flags producing JSON error (AC1)
- [ ] Gherkin scenario for invalid enum values producing JSON error (AC2)
- [ ] Gherkin scenario for out-of-range values producing JSON error (AC3)
- [ ] Gherkin scenario for preserved non-clap error behavior (AC4)
- [ ] All scenarios tagged `@regression`
- [ ] Step definitions exist or are reusable from existing steps
- [ ] All tests pass with the fix applied

### T004: Verify No Regressions

**File(s)**: [existing test files]
**Type**: Verify (no file changes)
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] All existing BDD tests pass (`cargo test --test bdd`)
- [ ] All unit tests pass (`cargo test --lib`)
- [ ] `--help` and `--version` produce expected output with exit code 0
- [ ] No side effects in related code paths

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Tasks are focused on the fix — no feature work
- [x] Regression test is included (T003)
- [x] Each task has verifiable acceptance criteria
- [x] No scope creep beyond the defect
- [x] File paths reference actual project structure (per `structure.md`)
