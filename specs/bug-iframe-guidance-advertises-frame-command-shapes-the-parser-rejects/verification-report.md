# Verification Report: Iframe guidance advertises --frame command shapes the parser rejects

**Date**: 2026-04-28
**Issue**: #286
**Reviewer**: Codex
**Scope**: Defect-fix verification against `specs/bug-iframe-guidance-advertises-frame-command-shapes-the-parser-rejects/`

---

## Executive Summary

| Category | Score (1-5) |
|----------|-------------|
| Spec Compliance | 5 |
| Architecture (SOLID) | 5 |
| Security | 5 |
| Performance | 5 |
| Testability | 5 |
| Error Handling | 5 |
| **Overall** | 5.0 |

**Status**: Pass
**Total Issues**: 0

The implementation corrects stale iframe/frame-targeting command guidance to the current parser contract: group-scoped `--frame` for `page`, `dom`, `js`, `interact`, `form`, and `media`, with `network list --frame` preserved. Parser-backed BDD coverage validates advertised command strings, generated man pages are in sync, and the live headless Chrome smoke test confirmed accepted frame commands still work while the previously advertised rejected page shape is absent from guidance.

---

## Acceptance Criteria Verification

| AC | Description | Status | Evidence |
|----|-------------|--------|----------|
| AC1 | Strategy guide uses accepted command shapes | Pass | `src/examples/strategies.rs:62`, `src/examples/strategies.rs:87`, `tests/bdd.rs:418`, focused BDD pass |
| AC2 | Diagnose suggestions use accepted command shapes | Pass | `src/diagnose/detectors.rs:252`, `src/diagnose/patterns.rs:107`, `tests/bdd.rs:430`, live `diagnose --current --json` smoke output |
| AC3 | Help, examples, and man pages are consistent | Pass | `src/cli/mod.rs:1365`, `src/examples_data.rs:175`, `tests/bdd.rs:451`, `cargo xtask man` pass |
| AC4 | Regression coverage validates parser acceptance | Pass | `tests/features/286-iframe-guidance-advertises-frame-command-shapes-the-parser-rejects.feature:17`, `tests/bdd.rs:858`, focused BDD pass |

---

## Task Completion

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| T001 | Correct frame command guidance strings | Complete | Strategy, examples, clap help, diagnose detector, and diagnose pattern strings use accepted shapes. |
| T002 | Add parser-backed regression coverage | Complete | Issue-specific BDD extracts advertised commands and calls `agentchrome::command().try_get_matches_from(...)`. |
| T003 | Regenerate docs and verify no regressions | Complete | `cargo xtask man`, stale-guidance search, fmt, lib tests, BDD, and clippy passed. |
| T004 | Run real-browser smoke verification | Complete | Headless Chrome smoke exercised accepted frame commands, live diagnose output, and cleanup. |

---

## Architecture Assessment

### Blast Radius Review

| Question | Result |
|----------|--------|
| What other callers share the changed code path? | Guidance strings feed `examples`, clap help, generated man pages, and diagnose output. No command execution path was changed. |
| Does the fix alter a public contract? | No parser or runtime behavior changed. The fix aligns documentation/guidance with the existing public parser contract. |
| Could the fix introduce silent data changes? | No persisted data, session format, or output schema changed. Only string values and tests changed. |

### Checklist Scores

| Area | Score (1-5) | Notes |
|------|-------------|-------|
| SOLID Principles | 5 | Static guidance remains in its existing modules; parser validation helpers are isolated in BDD test code. |
| Security | 5 | No auth, network trust, secret, or command execution behavior changed. |
| Performance | 5 | Runtime cost is unchanged; parser validation runs only in tests. |
| Testability | 5 | Regression tests validate command parseability instead of text presence only. |
| Error Handling | 5 | Existing structured parser error contract is preserved. |

---

## Test Coverage

| Acceptance Criterion | Has Scenario | Has Steps | Passes |
|---------------------|-------------|-----------|--------|
| AC1 | Yes | Yes | Yes |
| AC2 | Yes | Yes | Yes |
| AC3 | Yes | Yes | Yes |
| AC4 | Yes | Yes | Yes |

### Commands Run

| Command | Result |
|---------|--------|
| `cargo fmt --check` | Pass |
| `cargo build 2>&1` | Pass |
| `cargo test --lib 2>&1` | Pass, 256 tests |
| `cargo clippy --all-targets 2>&1` | Pass |
| `cargo xtask man 2>&1` | Pass, 106 man pages generated |
| `cargo test --test bdd -- --input tests/features/286-iframe-guidance-advertises-frame-command-shapes-the-parser-rejects.feature --fail-fast` | Pass, 4 scenarios |
| `cargo test --test bdd -- --input tests/features/examples-strategies.feature --fail-fast` | Pass, 24 scenarios |
| `cargo test --test bdd -- --input tests/features/diagnose.feature --fail-fast` | Pass, 5 scenarios |
| `rg` stale rejected page frame placement search across `src`, `tests/features`, `man`, `README.md`, and `docs` | Pass, no matches |
| `git diff --check main...HEAD` | Pass |

---

## Steering Doc Verification Gates

| Gate | Status | Evidence |
|------|--------|----------|
| Debug Build | Pass | `cargo build 2>&1` exited 0 |
| Unit Tests | Pass | `cargo test --lib 2>&1` exited 0 |
| Clippy | Pass | `cargo clippy --all-targets 2>&1` exited 0 |
| Format Check | Pass | `cargo fmt --check` exited 0 |
| Feature Exercise | Pass | Headless Chrome launched, fixture loaded, accepted `page --frame 1 snapshot`, `dom --frame 1 select body`, `js --frame 1 exec document.title`, and `form --frame 1 fill s2 smoke-value` succeeded; rejected `page snapshot --frame 1 --compact` still fails as expected but is absent from guidance; `diagnose --current --json` emitted accepted guidance. Chrome disconnected and no `chrome.*--remote-debugging` process remained. |

**Gate Summary**: 5/5 gates passed, 0 failed, 0 incomplete

---

## Fixes Applied

| Severity | Category | Location | Original Issue | Fix Applied | Routing |
|----------|----------|----------|----------------|-------------|---------|
| N/A | N/A | N/A | No verification findings requiring code changes | None | N/A |

---

## Remaining Issues

No remaining issues.

---

## Recommendations Summary

Ready for PR.
