# Defect Report: Fix macOS headless launch keychain prompt timeout

**Issue**: #266
**Date**: 2026-04-25
**Status**: Complete
**Author**: Codex
**Severity**: High
**Related Spec**: `specs/feature-chrome-instance-discovery-and-launch/`

---

## Reproduction

### Steps to Reproduce

1. On macOS with Google Chrome installed, run `HOME=/tmp/agentchrome-e2e-home ./target/debug/agentchrome --timeout 30000 connect --launch --headless`.
2. Observe the command timing out with `Chrome startup timed out on port <port>` while Chrome may show a Keychain prompt.
3. Retry with `HOME=/tmp/agentchrome-launch-check-home ./target/debug/agentchrome --timeout 30000 connect --launch --headless --chrome-arg=--use-mock-keychain --chrome-arg=--password-store=basic --chrome-arg=--disable-features=AutofillServerCommunication,OptimizationGuideModelDownloading,OptimizationHintsFetching,MediaRouter`.
4. Observe the retry succeeds with a `ws_url`, `port`, and `pid`.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS 26.3.1 (25D771280a) |
| **Version / Commit** | agentchrome 1.51.2 / `091bac0` |
| **Browser / Runtime** | Google Chrome 147.0.7727.102 |
| **Configuration** | Default AgentChrome-managed temporary profile |

### Frequency

Intermittent but blocking on macOS environments where Chrome startup triggers Keychain integration.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `connect --launch --headless` is non-interactive by default and returns `ws_url`, `port`, and `pid` without a Chrome Keychain prompt. |
| **Actual** | Chrome can display a Keychain prompt and AgentChrome times out waiting for the DevTools port. |

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: macOS managed profiles avoid Keychain prompts

**Given** AgentChrome launches Chrome with an internally managed temporary user data directory on macOS
**When** the Chrome argument list is built
**Then** the launch arguments include keychain-avoidance flags that keep the headless launch non-interactive

### AC2: Headless launch succeeds without user-supplied workaround flags

**Given** no AgentChrome session exists
**When** the user runs `agentchrome connect --launch --headless`
**Then** AgentChrome launches Chrome and returns `ws_url`, `port`, and `pid` with exit code 0

### AC3: Explicit Chrome args are preserved

**Given** the user supplies additional `--chrome-arg` values
**When** AgentChrome launches Chrome
**Then** the user-supplied arguments are still present in the final Chrome argument list

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | AgentChrome-managed Chrome launches must add safe keychain-avoidance defaults on macOS. | Must |
| FR2 | The launch argument builder must preserve user-supplied `--chrome-arg` values after built-in defaults. | Must |
| FR3 | Existing non-macOS launch behavior, session JSON shape, and exit-code contracts must remain unchanged. | Must |

---

## Out of Scope

- Attaching to existing user Chrome sessions.
- Installing, reading, or modifying macOS Keychain items.
- Adding Firefox or Safari support.

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific.
- [x] Expected vs actual behavior is clearly stated.
- [x] Severity is assessed.
- [x] Acceptance criteria use Given/When/Then format.
- [x] At least one regression scenario is included.
- [x] Fix scope is minimal.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #266 | 2026-04-25 | Initial defect report |
