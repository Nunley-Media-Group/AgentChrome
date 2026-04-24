# Defect Report: `dom tree` rejects positional ROOT while sibling subcommands accept one

**Issue**: #251
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley
**Severity**: Low
**Related Spec**: `specs/feature-dom-command-group/`

---

## Reproduction

### Steps to Reproduce

1. Launch a Chrome instance with `agentchrome connect --launch --headless`.
2. Navigate to any page that has a `<table>` element: `agentchrome navigate file://.../page.html`.
3. Run `agentchrome dom tree "css:table"`.

### Environment

| Factor | Value |
|--------|-------|
| **OS / Platform** | macOS 15.x (reproducer), any platform |
| **Version / Commit** | v1.47.0 / branch `251-fix-dom-tree-...` |
| **Browser / Runtime** | Chrome (any recent) |
| **Configuration** | N/A |

### Frequency

Always.

---

## Expected vs Actual

| | Description |
|---|-------------|
| **Expected** | `agentchrome dom tree "css:table"` prints the subtree rooted at the first `<table>` element, matching the positional-argument pattern used by `dom get-text`, `dom children`, `dom parent`, and every other `dom` subcommand that targets a node. |
| **Actual** | clap rejects the invocation with `error: unexpected argument 'css:table' found`. The user must instead type `agentchrome dom tree --root "css:table"`. |

### Error Output

```
error: unexpected argument 'css:table' found

Usage: agentchrome dom tree [OPTIONS]

For more information, try '--help'.
```

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Positional ROOT accepted

**Given** a page containing at least one `<table>` element
**When** the user runs `agentchrome dom tree "css:table" --depth 3`
**Then** the command exits 0 and prints the DOM tree rooted at the first `<table>` element, limited to depth 3.

### AC2: `--root` flag still works (backward compatible)

**Given** a page containing at least one `<table>` element
**When** the user runs `agentchrome dom tree --root "css:table" --depth 3`
**Then** the command exits 0 and produces output identical to AC1.

### AC3: No-argument form still works

**Given** a page with any DOM
**When** the user runs `agentchrome dom tree`
**Then** the command exits 0 and prints the full document tree (existing behavior is preserved).

### AC4: Conflict when both positional and `--root` are supplied

**Given** a page with any DOM
**When** the user runs `agentchrome dom tree "css:table" --root "css:div"`
**Then** the command exits non-zero with a clap conflict error indicating that the positional `ROOT` and `--root` cannot be used together.

### AC5: Help text shows the positional

**Given** the user runs `agentchrome dom tree --help`
**When** they read the synopsis
**Then** the usage line includes `[ROOT]` as an optional positional and the EXAMPLES section shows an invocation using the positional form.

---

## Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1 | Add an optional positional `ROOT` argument to the `dom tree` clap command that maps to the same target field as `--root`. | Must |
| FR2 | If both the positional `ROOT` and `--root` are provided, return a clap conflict error (`conflicts_with`). | Must |
| FR3 | Update `dom tree`'s `after_long_help` EXAMPLES and `src/examples_data.rs` entries to demonstrate the positional form. | Should |
| FR4 | Regenerate the `man/agentchrome-dom-tree.1` man page to reflect the new positional. | Should |

---

## Out of Scope

- Changes to `dom tree` output format, depth logic, or node resolution behavior.
- Adding positional shortcuts to any other `dom` subcommand (they already have them).
- Refactoring the shared `DomNodeIdArgs` struct to carry `dom tree`'s depth argument.

---

## Validation Checklist

- [x] Reproduction steps are repeatable and specific
- [x] Expected vs actual behavior is clearly stated
- [x] Severity is assessed
- [x] Acceptance criteria use Given/When/Then format
- [x] At least one regression scenario is included (AC2, AC3)
- [x] Fix scope is minimal — no feature work mixed in
- [x] Out of scope is defined

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #251 | 2026-04-23 | Initial defect report |
