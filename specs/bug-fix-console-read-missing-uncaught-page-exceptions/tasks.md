# Tasks: console read misses uncaught page exceptions

**Issue**: #290
**Date**: 2026-05-26
**Status**: Planning
**Author**: Codex (write-spec)

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| T001 | Normalize Runtime exception events into console read records | [ ] |
| T002 | Drain console API and exception events together | [ ] |
| T003 | Add regression tests and fixture coverage | [ ] |
| T004 | Verify no regressions with unit, BDD, and real-browser smoke tests | [ ] |

---

### T001: Normalize Runtime Exception Events

**File(s)**: `src/console.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `Runtime.exceptionThrown` payloads are converted into list-mode records with `type`, `text`, `timestamp`, `url`, `line`, and `column`.
- [ ] Exception records use `type: "error"` so existing error-level filters include them.
- [ ] Detail-mode records include exception text, source fields, args where practical, and stack frames from `exceptionDetails.stackTrace`.
- [ ] Parser unit tests cover exception payloads with full source data and payloads that require stack-frame fallback.

**Notes**: Keep CDP event-shape parsing in focused helpers. Do not weaken the existing `ConsoleMessage` or `ConsoleMessageDetail` JSON contracts.

### T002: Drain Console API and Exception Event Streams Together

**File(s)**: `src/console.rs`
**Type**: Modify
**Depends**: T001
**Acceptance**:
- [ ] `execute_read()` subscribes to both `Runtime.consoleAPICalled` and `Runtime.exceptionThrown` before `managed.ensure_domain("Runtime")`.
- [ ] The drain loop collects both event streams until the existing idle or absolute timeout condition is met.
- [ ] Console API records and exception records are merged deterministically before filtering and pagination.
- [ ] Existing plain output, JSON output, large-response summary, `--type`, `--errors-only`, `--limit`, `--page`, and detail lookup behavior remains compatible.

**Notes**: Preserve `console follow` behavior unless extracting shared parse helpers makes a tiny non-behavioral edit unavoidable.

### T003: Add Regression Tests and Fixture Coverage

**File(s)**: `tests/features/290-fix-console-read-missing-uncaught-page-exceptions.feature`, `tests/fixtures/console-read-uncaught-exception.html`, `tests/bdd.rs`, `src/console.rs`
**Type**: Create / Modify
**Depends**: T001, T002
**Acceptance**:
- [ ] Gherkin scenarios cover AC1, AC2, and AC3 from `requirements.md`.
- [ ] Every scenario is tagged `@regression`; Chrome-dependent scenarios also follow the existing `@requires-chrome` convention.
- [ ] The fixture emits an explicit `console.error(...)`, an uncaught `TypeError`, and non-error console messages for filter preservation checks.
- [ ] `tests/bdd.rs` includes the feature file using the repo's existing Chrome-required scenario pattern.
- [ ] Unit tests fail if exception records are not normalized as error-level messages.

**Notes**: The BDD feature documents the browser behavior even if CI skips Chrome-required scenarios; the real-browser smoke test is mandatory during verification.

### T004: Verify No Regressions

**File(s)**: `specs/bug-fix-console-read-missing-uncaught-page-exceptions/verification-report.md`
**Type**: Verify
**Depends**: T001, T002, T003
**Acceptance**:
- [ ] `cargo build` passes.
- [ ] `cargo test --lib` passes.
- [ ] Focused BDD execution for the new feature file passes or correctly records Chrome-required skips according to the existing harness.
- [ ] `cargo clippy --all-targets` passes.
- [ ] `cargo fmt --check` passes.
- [ ] Manual smoke test with `./target/debug/agentchrome connect --launch --headless`, the local fixture, `navigate`, `console read --errors-only`, and `console read <id>` confirms the uncaught exception is visible.
- [ ] `./target/debug/agentchrome console follow --timeout 2000` behavior is spot-checked or covered by existing tests to confirm no streaming regression.
- [ ] Any headed or headless Chrome process launched for verification is disconnected and cleaned up.

---

## Critical Path

T001 -> T002 -> T003 -> T004

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #290 | 2026-05-26 | Initial defect task plan |

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently given dependencies
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included
- [x] No circular dependencies
- [x] Tasks are in logical execution order
