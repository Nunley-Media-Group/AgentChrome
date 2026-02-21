# Root Cause Analysis: Clap Argument Validation Errors Output Non-JSON stderr and Wrong Exit Code

**Issue**: #98
**Date**: 2026-02-15
**Status**: Draft
**Author**: Claude

---

## Root Cause

The bug occurs because `main()` in `src/main.rs:37` calls `Cli::parse()` directly. When clap encounters a validation error (conflicting flags, invalid enum values, out-of-range numbers), it bypasses the application's error handling entirely — clap prints its own plain-text error message to stderr and calls `std::process::exit(2)`.

The application's JSON error formatting (`AppError::print_json_stderr()`) and custom exit code mapping (`ExitCode::GeneralError = 1`) are never reached because clap short-circuits the process before `run()` is called. Clap's default exit code for usage errors is 2, which conflicts with agentchrome's exit code 2 meaning "connection error" (`ExitCode::ConnectionError = 2`).

The fix is to replace `Cli::parse()` with `Cli::try_parse()`, which returns a `Result` instead of exiting. The `Err` variant can then be caught, converted to an `AppError` with `ExitCode::GeneralError`, and output as JSON via the existing `print_json_stderr()` method.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/main.rs` | 36–43 | `main()` calls `Cli::parse()` without catching clap errors |
| `src/error.rs` | 5–14 | `ExitCode` enum — exit code 2 means `ConnectionError`, conflicting with clap's default |

### Triggering Conditions

- User provides mutually exclusive flags (e.g., `--to-top --to-bottom`, `--json --plain`)
- User provides an invalid value for an enum argument (e.g., `--network invalid-profile`)
- User provides an out-of-range value (e.g., `--cpu 0` when the valid range is `1..=20`)
- User provides a missing required argument for certain subcommands
- These conditions were not caught before because `Cli::parse()` handles errors internally and was never wrapped in error handling

---

## Fix Strategy

### Approach

Replace `Cli::parse()` with `Cli::try_parse()` in `main()`. When `try_parse()` returns an `Err`, extract the error message from clap's `Error` type, wrap it in an `AppError` with `ExitCode::GeneralError` (code 1), and emit it as JSON on stderr using the existing `print_json_stderr()` method.

Clap errors that are not actual errors (e.g., `--help` and `--version` which print information and exit with code 0) should be handled separately: their output should be printed as-is (they are informational, not error conditions).

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/main.rs` | Replace `Cli::parse()` with `Cli::try_parse()` and handle the `Err` case by converting to `AppError` with JSON output | Intercepts clap validation errors before they reach stderr as plain text |
| `tests/features/cli-skeleton.feature` | Update "Conflicting output format flags" scenario: change expected exit code from 2 to 1, add JSON validation assertions | Aligns the existing test with the corrected behavior |

### Blast Radius

- **Direct impact**: `src/main.rs` — only the `main()` function changes (lines 36–43)
- **Indirect impact**: None — `Cli::try_parse()` returns the same `Cli` struct on success, so the `run()` function and all downstream code are unaffected
- **Risk level**: Low — the change is confined to the entry point and only affects the error path; the success path is identical

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `--help` and `--version` stop working | Low | Clap's `Error` type has an `exit_code()` method and `kind()` discriminant — help/version errors use exit code 0 and can be detected via `ErrorKind::DisplayHelp` / `ErrorKind::DisplayVersion`; these should be printed as-is and exit with code 0 |
| Clap error messages lose context | Low | The fix preserves the original clap error message text; it only wraps it in JSON |
| Existing non-clap error handling breaks | Very Low | The `run()` function and `AppError::print_json_stderr()` are unchanged; only the clap parsing path is affected |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Custom clap error handler via `Command::error` | Override clap's error formatting at the `Command` level | More invasive — requires modifying the CLI definition in `src/cli/mod.rs`; `try_parse()` is the idiomatic clap approach |
| Write to stderr manually with `clap::Error::render()` | Use clap's render API for custom formatting | Still requires `try_parse()` to intercept the error; adds unnecessary complexity over simply extracting the message string |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)
