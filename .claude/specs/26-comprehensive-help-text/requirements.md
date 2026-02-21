# Requirements: Comprehensive Help Text

**Issue**: #26
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude (automated)

---

## User Story

**As a** developer or AI agent using agentchrome
**I want** rich, detailed `--help` documentation for every command, subcommand, and flag
**So that** I can fully understand all capabilities, parameters, return values, and common workflows without needing external documentation

---

## Background

agentchrome's primary consumer is Claude Code and other AI agents. The `--help` output is the primary discovery mechanism for understanding what the CLI can do. Currently, the CLI has short `about` strings and `long_about` paragraphs at the command-group level, but lacks `after_help` / `after_long_help` sections with usage examples, exit code documentation, quick-start workflows, and detailed leaf-command descriptions that explain return values and how commands compose together.

This feature adds comprehensive help text using clap's `about`, `long_about`, `after_help`, and `after_long_help` attributes so that an agent reading `agentchrome --help` or `agentchrome <cmd> --help` knows exactly what each command does, what parameters it takes, what it returns, and how to combine commands for common workflows.

---

## Acceptance Criteria

### AC1: Top-level help displays complete overview

**Given** a user runs `agentchrome --help`
**When** the help text is rendered
**Then** it displays a one-line description of the tool
**And** it lists all subcommand groups with descriptions
**And** it lists all global flags with descriptions
**And** it shows version and author info
**And** it includes an `after_help` section with 3–5 common workflow examples

### AC2: Subcommand group help shows commands and examples

**Given** a user runs `agentchrome <group> --help` for any command group (e.g., `tabs`, `navigate`, `page`)
**When** the help text is rendered
**Then** it displays a description of what the group does
**And** it lists all subcommands with descriptions
**And** it includes an `after_help` section with examples of common usage for that group

### AC3: Leaf command help shows detailed usage

**Given** a user runs `agentchrome <group> <command> --help` for any leaf command (e.g., `tabs list`, `page screenshot`)
**When** the help text is rendered
**Then** it displays a one-line `about` summary
**And** it displays a multi-line `long_about` description covering what the command does, what it returns (JSON structure), common use cases, and interaction with other commands
**And** it lists all flags and arguments with `help` text
**And** it includes an `after_help` section with 2–3 usage examples

### AC4: Flag documentation is complete

**Given** any flag or argument in the CLI
**When** its help text is displayed
**Then** it has a `help` string explaining what it does
**And** default values are shown for all optional flags that have defaults
**And** enum values are listed for flags with fixed options (already handled by clap `ValueEnum`)
**And** conflicting flags are documented in the help text where applicable

### AC5: Exit codes documented in top-level help

**Given** a user runs `agentchrome --help`
**When** the help text is rendered
**Then** the `after_help` section includes a list of exit codes:
  - 0: Success
  - 1: General error
  - 2: Connection error
  - 3: Target error
  - 4: Timeout error
  - 5: Protocol error

### AC6: Help text is consistent and well-formatted

**Given** all help text across the CLI
**When** reviewed for quality
**Then** it uses consistent terminology throughout (e.g., always "UID" not sometimes "uid" and sometimes "accessibility ID")
**And** it is grammatically correct
**And** it follows a uniform style (imperative voice for descriptions, present tense)
**And** it reads well at 100-column width (matching `term_width = 100`)

### AC7: Help text verified by running CLI

**Given** all help text has been written
**When** `agentchrome --help`, `agentchrome <cmd> --help`, and `agentchrome <cmd> <subcmd> --help` are run for every command
**Then** all commands produce valid help output without errors
**And** no placeholder or TODO text remains

### Generated Gherkin Preview

```gherkin
Feature: Comprehensive help text
  As a developer or AI agent using agentchrome
  I want rich, detailed --help documentation for every command, subcommand, and flag
  So that I can fully understand all capabilities without external documentation

  Scenario: Top-level help displays complete overview
    Given the agentchrome binary is built
    When I run "agentchrome --help"
    Then the output contains "Browser automation via the Chrome DevTools Protocol"
    And the output contains all top-level subcommand names
    And the output contains a quick-start examples section
    And the output contains an exit codes section

  Scenario: Subcommand group help shows commands and examples
    Given the agentchrome binary is built
    When I run "agentchrome tabs --help"
    Then the output contains a description of the tabs group
    And the output lists all tabs subcommands
    And the output contains usage examples

  Scenario: Leaf command help shows detailed usage
    Given the agentchrome binary is built
    When I run "agentchrome tabs list --help"
    Then the output contains a detailed description
    And the output contains usage examples

  Scenario: Help text is consistent across all commands
    Given the agentchrome binary is built
    When I run --help for every command and subcommand
    Then no output contains placeholder or TODO text
    And all output renders without errors
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Add `after_help` to root `Cli` struct with quick-start workflows and exit codes | Must | 3–5 workflow examples |
| FR2 | Add `after_help` to each command group enum variant with group-level examples | Must | Every command group |
| FR3 | Add `long_about` to each leaf command with detailed description, return value, and usage notes | Must | Every leaf command |
| FR4 | Add `after_help` to each leaf command with 2–3 usage examples | Must | Every leaf command |
| FR5 | Ensure all flags have complete `help` strings with defaults and constraints | Must | Review all ~80 flags |
| FR6 | Document exit codes in the top-level `after_help` | Must | Codes 0–5 |
| FR7 | Use consistent terminology and style across all help text | Must | Style guide adherence |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Readability** | Help text reads well at 100-column width (matches `term_width = 100`) |
| **Consistency** | Uniform style: imperative voice, present tense, consistent capitalization |
| **Maintainability** | Help text co-located with command definitions in `src/cli/mod.rs` |
| **Performance** | No runtime impact — all text is compile-time string literals |

---

## UI/UX Requirements

Reference `structure.md` and `product.md` for project-specific design standards.

| Element | Requirement |
|---------|-------------|
| **Interaction** | [Touch targets, gesture requirements] |
| **Typography** | [Minimum text sizes, font requirements] |
| **Contrast** | [Accessibility contrast requirements] |
| **Loading States** | [How loading should be displayed] |
| **Error States** | [How errors should be displayed] |
| **Empty States** | [How empty data should be displayed] |

---

## Data Requirements

### Input Data

N/A — this is a documentation-only change to compile-time string literals.

### Output Data

| Field | Type | Description |
|-------|------|-------------|
| help text | String | Rendered by clap to stdout when `--help` is passed |

---

## Dependencies

### Internal Dependencies
- [x] All CLI commands and subcommands are defined in `src/cli/mod.rs`
- [x] Exit codes are defined in `src/error.rs`

### External Dependencies
- [x] clap 4.x with `about`, `long_about`, `after_help`, `after_long_help` support

### Blocked By
- None — all commands are already defined (even `Dom` which is a placeholder)

---

## Out of Scope

- Man page generation (`clap_mangen`) — separate issue
- README rewrite — separate documentation effort
- Interactive `--help` pager — not needed for AI agents
- Localization / i18n of help text
- Adding new commands or flags — this is documentation of existing commands only

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Help coverage | 100% of commands have `after_help` examples | Automated test counts `after_help` presence |
| Exit code docs | All 6 codes documented in top-level help | Manual review |
| Build success | `cargo build` succeeds with all new help text | CI pipeline |
| Consistency | No style violations in help text | Manual review |

---

## Open Questions

- None — the issue is well-specified and the codebase is fully explored.

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
