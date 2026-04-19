# Defect Report: Fix navigate back/forward timeout on SPA same-document history navigations

**Issue**: #144
**Date**: 2026-02-19
**Status**: Draft
**Author**: Claude
**Severity**: High
**Related Spec**: `.claude/specs/72-fix-navigate-back-forward-cross-origin-timeout/`

---

## Reproduction

### Steps to Reproduce

1. Launch Chrome: `agentchrome connect --launch`
2. Navigate to `https://www.saucedemo.com/`
3. Log in: `agentchrome form fill css:#user-name "standard_user"` / `agentchrome form fill css:#password "secret_sauce"` / `agentchrome interact click css:#login-button`
4. Add item to cart: `agentchrome interact click css:.btn_inventory` (first one)
5. Go to cart: `agentchrome interact click css:.shopping_cart_link`
6. Checkout: `agentchrome interact click css:#checkout`
7. Fill form: `agentchrome form fill css:#first-name "John"` / `css:#last-name "Doe"` / `css:#postal-code "90210"`
8. Continue: `agentchrome interact click css:#continue`
9. Finish: `agentchrome interact click css:#finish`
10. Run: `agentchrome navigate back`
11. Observe: command hangs for 30 seconds then returns timeout error

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS Darwin 25.3.0 |
| **Version / Commit** | `dbbbfac` (v1.0.5) |
| **Browser / Runtime** | Chrome via CDP |
| **Configuration** | Default (30s navigation timeout) |

### Frequency

Always (100% reproducible on any SPA using `pushState` routing)

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `navigate back` completes within ~200ms and returns JSON with the previous URL |
| **Actual** | `navigate back` hangs for 30 seconds and fails with timeout error (exit code 4), even though the URL actually changes |

### Error Output

```json
{"error":"Navigation timed out after 30000ms waiting for navigation","code":4}
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: SPA same-document navigate back succeeds

**Given** a tab has navigated through multiple SPA pages via `pushState` routing (e.g., saucedemo.com checkout flow)
**When** I run `agentchrome navigate back`
**Then** the exit code is 0
**And** the JSON output has key `url` containing the previous page's URL

### AC2: SPA same-document navigate forward succeeds

**Given** a tab has navigated through SPA pages and then navigated back
**When** I run `agentchrome navigate forward`
**Then** the exit code is 0
**And** the JSON output has key `url` containing the forward destination URL

### AC3: Cross-document navigate back still works (no regression)

**Given** a tab has navigated between two pages via full page loads (e.g., `agentchrome navigate <url>`)
**When** I run `agentchrome navigate back`
**Then** the exit code is 0
**And** the JSON output has key `url` containing the previous page's URL

### AC4: Cross-origin navigate back still works (no regression from #72 fix)

**Given** a tab has navigated across origins via full page loads
**When** I run `agentchrome navigate back`
**Then** the exit code is 0
**And** the JSON output has key `url` containing the previous origin's URL

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | `execute_back` and `execute_forward` must detect navigation completion for both cross-document (`Page.frameNavigated`) and same-document (`Page.navigatedWithinDocument`) history navigations | Must |
| FR2 | Existing cross-document and cross-origin back/forward behavior must be preserved (no regression from #72 fix) | Must |

---

## Out of Scope

- Changing the default timeout value
- Adding the `--timeout` flag to `navigate back`/`forward` (separate issue)
- Refactoring `navigate reload` or `navigate <url>`
- Changes to `interact click` navigation detection

---

## Validation Checklist

Before moving to PLAN phase:

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC3, AC4)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined
