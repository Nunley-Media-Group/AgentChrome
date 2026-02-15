# Defect Report: emulate status always reports inaccurate emulation state

**Issue**: #74
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/21-device-network-viewport-emulation/`

---

## Reproduction

### Steps to Reproduce

1. Launch a Chrome session via `chrome-cli connect` or `chrome-cli launch`
2. Run `emulate set --viewport 375x667 --mobile` to enable mobile emulation
3. Observe the `set` command correctly returns `mobile: true`
4. Immediately run `emulate status`
5. Observe that it reports `mobile: false`

Additionally:

6. Run `emulate set --network slow4g` to enable network throttling
7. Run `emulate status`
8. Observe that `network` is not reported (shows `None`)

9. Run `emulate set --cpu 4` to enable CPU throttling
10. Run `emulate status`
11. Observe that `cpu` is not reported (shows `None`)

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | All (macOS, Linux, Windows) |
| **Version / Commit** | Current `main` branch |
| **Browser / Runtime** | Any Chrome/Chromium with CDP |
| **Configuration** | Default |

### Frequency

Always — 100% reproducible.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `emulate status` accurately reflects the current emulation state: `mobile: true` when mobile emulation is active, the current network throttling profile name when applied, and the current CPU throttling factor when applied |
| **Actual** | `mobile` is always `false`, `network` is always `None`, and `cpu` is always `None`, regardless of what overrides have been applied via `emulate set` |

### Error Output

```
# After running: emulate set --viewport 375x667 --mobile
# emulate set correctly returns:
{
  "viewport": { "width": 375, "height": 667 },
  "deviceScaleFactor": 1.0,
  "mobile": true
}

# But emulate status returns:
{
  "viewport": { "width": 375, "height": 667 },
  "deviceScaleFactor": 1.0,
  "mobile": false   <-- WRONG: should be true
}
# network and cpu fields are absent (None) even when set
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Mobile emulation state is accurately reported

**Given** a Chrome session with mobile emulation enabled via `emulate set --viewport 375x667 --mobile`
**When** the user runs `emulate status`
**Then** the status output includes `mobile: true`

### AC2: Network throttling state is accurately reported

**Given** a Chrome session with network throttling enabled via `emulate set --network slow4g`
**When** the user runs `emulate status`
**Then** the status output includes the network profile name (e.g., `"Slow 4G"`)

### AC3: CPU throttling state is accurately reported

**Given** a Chrome session with CPU throttling enabled via `emulate set --cpu 4`
**When** the user runs `emulate status`
**Then** the status output includes the CPU throttling rate (e.g., `4`)

### AC4: No regression — status still reports viewport, user agent, and color scheme

**Given** a Chrome session with viewport, user agent, and color scheme overrides applied
**When** the user runs `emulate status`
**Then** the viewport, user agent, and color scheme are still accurately reported

### AC5: Status reports default state when no emulation is active

**Given** a Chrome session with no emulation overrides applied (or after `emulate reset`)
**When** the user runs `emulate status`
**Then** `mobile` is `false`, and `network` and `cpu` are absent or indicate no throttling

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `execute_status` must track and report the current mobile emulation state instead of hardcoding `false` | Must |
| FR2 | `execute_status` must track and report the current network throttling profile instead of hardcoding `None` | Must |
| FR3 | `execute_status` must track and report the current CPU throttling rate instead of hardcoding `None` | Must |
| FR4 | State must survive across separate CLI invocations (e.g., `emulate set` followed by `emulate status` in separate processes) | Must |
| FR5 | `emulate reset` must clear persisted emulation state so status returns to defaults | Should |

---

## Out of Scope

- Adding new emulation features beyond fixing the status reporting
- Refactoring the overall emulation command architecture
- Querying CDP directly for active overrides (CDP does not expose a reliable query API for these settings)
- Persisting geolocation state (already detected via CDP/JavaScript)

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC4)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
