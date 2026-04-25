# Tasks: Fix macOS headless launch keychain prompt timeout

**Issue**: #266
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Related Spec**: `specs/feature-chrome-instance-discovery-and-launch/`

---

## Task List

| ID | Task | Status |
|----|------|--------|
| T001 | Add macOS keychain-avoidance launch defaults in `src/chrome/launcher.rs`. | [x] |
| T002 | Add regression coverage for built-in launch args and explicit `--chrome-arg` preservation. | [x] |
| T003 | Verify `connect --launch --headless` succeeds on macOS without user-supplied keychain workaround flags. | [x] |

---

## T001: Add macOS Keychain-Avoidance Launch Defaults

**File(s)**: `src/chrome/launcher.rs`

Acceptance:
- [x] AgentChrome-managed Chrome launches include `--use-mock-keychain` on macOS.
- [x] AgentChrome-managed Chrome launches include `--password-store=basic` on macOS.
- [x] Non-macOS launch behavior remains unchanged.
- [x] Existing launch flags stay in their current relative order before user `extra_args`.

## T002: Add Regression Coverage

**File(s)**: `src/chrome/launcher.rs`, `tests/features/266-fix-macos-headless-launch-keychain-prompt-timeout.feature`

Acceptance:
- [x] Unit tests verify the macOS-specific keychain defaults when compiled for macOS.
- [x] Unit tests verify user `extra_args` remain present.
- [x] Defect Gherkin scenarios map to AC1-AC3 and are tagged `@regression`.

## T003: Verify

**File(s)**: `CHANGELOG.md`, `VERSION`, `Cargo.toml`, `Cargo.lock`

Acceptance:
- [x] `cargo fmt --check` passes.
- [x] Focused launcher tests pass.
- [x] Manual smoke `agentchrome connect --launch --headless` succeeds without keychain workaround flags.
- [x] Patch version and changelog include issue #266.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #266 | 2026-04-25 | Initial defect task plan |
