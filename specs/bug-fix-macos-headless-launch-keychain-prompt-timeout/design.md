# Design: Fix macOS headless launch keychain prompt timeout

**Issue**: #266
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Related Spec**: `specs/feature-chrome-instance-discovery-and-launch/`

---

## Root Cause Analysis

`src/chrome/launcher.rs::build_chrome_args` constructs the managed Chrome launch argument list with remote debugging, temporary profile, first-run suppression, default-browser suppression, automation, and optional headless flags. On macOS, that default set can still allow Chrome to touch system credential storage during startup, producing a Keychain prompt that blocks a non-interactive headless launch until AgentChrome reports `Chrome startup timed out on port <port>`.

The e2e run proved the timeout is avoidable: the same binary and browser succeeded when the caller passed `--use-mock-keychain` and `--password-store=basic`. Those flags belong in the managed launch defaults because AgentChrome's product contract is non-interactive, AI/CI-friendly browser automation.

## Minimal Fix Strategy

Add platform-scoped keychain-avoidance defaults to `build_chrome_args` for macOS:

| File | Change |
|------|--------|
| `src/chrome/launcher.rs` | Add a small helper that appends macOS-only keychain-avoidance flags to AgentChrome-managed Chrome launches. Keep the helper close to `build_chrome_args` so launch defaults remain auditable. |
| `src/chrome/launcher.rs` tests | Add assertions that macOS launch args contain the keychain-avoidance defaults and that explicit `extra_args` are still preserved. |

The fix is intentionally limited to launch argument construction. It does not change Chrome discovery, process detachment, session persistence, startup polling, or output contracts.

## Blast Radius

- Directly affects every AgentChrome-managed Chrome launch on macOS.
- Does not affect attaching to existing Chrome instances via `--port`, `--ws-url`, or auto-discovery.
- Does not affect non-macOS platforms because the new defaults are guarded with `cfg(target_os = "macos")`.
- User-supplied `--chrome-arg` values remain appended after built-in defaults.

## Regression Risk

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| macOS-only flags accidentally apply to Linux/Windows. | Low | Medium | Guard helper with `cfg(target_os = "macos")`; tests assert the helper behavior behind cfg. |
| User-supplied `--chrome-arg` ordering changes. | Low | Medium | Keep extra args appended at the end and add a regression assertion. |
| Launch argument tests become platform-dependent. | Medium | Low | Use cfg-gated expectations and keep non-macOS tests focused on existing common flags. |

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #266 | 2026-04-25 | Initial defect design |
