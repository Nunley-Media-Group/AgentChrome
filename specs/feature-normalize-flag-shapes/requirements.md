# Requirements: Normalize Flag Shapes (cookie set, tabs close, dom query aliases)

**Issues**: #230
**Date**: 2026-04-22
**Status**: Draft
**Author**: Rich Nunley

---

## User Story

**As a** first-time user or AI agent extrapolating flag shapes from one agentchrome subcommand to another
**I want** consistent flag/argument naming across related subcommands, or hidden aliases that accept the natural guesses
**So that** I don't fail three times before discovering the canonical form of every command

---

## Background

Rich's end-to-end exercise on agentchrome 1.33.1 surfaced three flag-shape divergences where the intuitive guess differs from the canonical form:

1. `cookie set` uses `--domain <D>`, not `--url <U>`
2. `tabs close` takes a positional `Vec<String>`, not `--tab <ID>`
3. `dom select` is the canonical subcommand; `dom query` does not exist

Each is individually defensible, but together they degrade the CLI's self-teaching property. Clap's default error messages ("unexpected argument '--url'", "unrecognized subcommand 'query'") do not point at the canonical shape, so a first-time user hits all three failures before discovering the canonical form.

This feature adds **hidden aliases** so the three guessed forms work without changing the canonical forms, and tightens error messages where aliases are not appropriate. Hidden aliases do not appear in `--help`, `capabilities`, or `examples` output, preserving the one-canonical-form story for documentation and agent training while still accepting the natural guess.

Reference: `src/cli/mod.rs` (`CookieSetArgs` @ 1737, `TabsCloseArgs` @ 1006, `DomCommand::Select` @ 3253).

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: `cookie set --url` is accepted as a hidden alias for `--domain`

**Given** a user runs `agentchrome cookie set session_id abc123 --url https://example.com/path`
**When** the CLI parses the invocation
**Then** `--url` is accepted as a hidden alias for `--domain`
**And** the URL's host (`example.com`) is extracted and used as the cookie domain
**And** the command succeeds with the same JSON output shape as `--domain example.com`

### AC2: `tabs close --tab <ID>` is accepted as a hidden alias for the positional

**Given** a user runs `agentchrome tabs close --tab 1A2B3C`
**When** the CLI parses the invocation
**Then** `--tab <ID>` is accepted as a hidden alias for the positional target
**And** the tab with the given ID is closed
**And** the command succeeds with the same JSON output shape as `agentchrome tabs close 1A2B3C`

### AC3: `--tab` may be repeated to close multiple tabs

**Given** a user runs `agentchrome tabs close --tab 1A2B3C --tab 4D5E6F`
**When** the CLI parses the invocation
**Then** both tabs are closed
**And** the behavior is identical to `agentchrome tabs close 1A2B3C 4D5E6F`

### AC4: `dom query` is accepted as a hidden alias for `dom select`

**Given** a user runs `agentchrome dom query "table tbody tr"`
**When** the CLI parses the invocation
**Then** `query` is accepted as a hidden alias for `select`
**And** all flags supported by `dom select` (e.g., `--xpath`) are supported on `dom query`
**And** the command produces the same output as `agentchrome dom select "table tbody tr"`

### AC5: Canonical forms still work unchanged

**Given** a user runs `agentchrome cookie set session_id abc123 --domain example.com`
**And** runs `agentchrome tabs close 1A2B3C 4D5E6F`
**And** runs `agentchrome dom select "h1"`
**When** the CLI parses those invocations
**Then** behavior is identical to the current release — no change in output, exit codes, or side effects

### AC6: Aliases are hidden from help, capabilities, and examples

**Given** a user runs `agentchrome cookie set --help`, `agentchrome tabs close --help`, or `agentchrome dom --help`
**When** clap renders help text
**Then** neither `--url`, `--tab`, nor the `query` alias appears in the help output
**And** `agentchrome capabilities` output does not list the aliases as first-class fields
**And** `agentchrome examples cookie`, `agentchrome examples tabs`, and `agentchrome examples dom` continue to show the canonical forms only

### AC7: Conflict between canonical and alias is rejected clearly

**Given** a user runs `agentchrome cookie set session_id abc123 --url https://example.com/ --domain other.com`
**When** the CLI parses the invocation
**Then** the CLI rejects the invocation with a structured JSON error on stderr
**And** the error message identifies that `--url` and `--domain` are aliases for the same value
**And** the exit code is `1` (general error)

**And given** a user runs `agentchrome tabs close 1A2B3C --tab 4D5E6F`
**When** the CLI parses the invocation
**Then** the positional IDs and `--tab` values are merged into a single target list and both tabs are closed (there is no conflict — the flag is a repeatable equivalent of the positional)

### AC8: Unrelated wrong shapes still get canonical-pointing errors

**Given** a user runs a command with a typo or related-but-unaliased flag (e.g., `agentchrome cookie set n v --host example.com`)
**When** the CLI parses the invocation
**Then** the error message explicitly names the canonical flag (`--domain`), not the generic clap "pass '--host' as a value" tip
**And** the exit code is `1` (general error)

### Generated Gherkin Preview

```gherkin
Feature: Normalize flag shapes across subcommands
  As a first-time user or AI agent
  I want consistent flag shapes or hidden aliases for natural guesses
  So that I don't fail before discovering the canonical form

  Scenario: cookie set accepts --url as a hidden alias for --domain
    Given agentchrome is connected to a Chrome instance
    When the user runs "cookie set session_id abc123 --url https://example.com/path"
    Then the command succeeds
    And the cookie's domain is set to "example.com"

  Scenario: tabs close accepts --tab as a hidden alias for the positional
    Given agentchrome is connected to a Chrome instance with one open tab
    When the user runs "tabs close --tab <ID>"
    Then the command succeeds
    And the tab is closed

  Scenario: dom query is accepted as a hidden alias for dom select
    Given agentchrome is connected to a page with a table
    When the user runs "dom query \"table tbody tr\""
    Then the command succeeds
    And the output matches dom select \"table tbody tr\"

  Scenario: Hidden aliases do not appear in help output
    When the user runs "cookie set --help"
    Then the help text does not mention "--url"
    When the user runs "tabs close --help"
    Then the help text does not mention "--tab"
    When the user runs "dom --help"
    Then the help text does not mention "query"
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Add `--url <URL>` as a hidden alias on `cookie set`; the URL's host component is extracted and used as the cookie domain | Must | Use `url::Url` (already a transitive dep via tokio-tungstenite) or a minimal host extractor; reject inputs that are not parseable URLs |
| FR2 | Add `--tab <ID>` (repeatable) as a hidden alias on `tabs close`; values are merged with the positional `targets` list | Must | Must not change the existing positional shape; at least one of positional or `--tab` must be supplied |
| FR3 | Add `query` as a hidden alias for the `dom select` subcommand | Must | Use clap's `#[command(alias = "query")]` (hidden by default) |
| FR4 | Aliases MUST NOT appear in `--help`, `capabilities` manifest output, or `examples` command output | Must | Use clap's `alias` (not `visible_alias`); update examples and capabilities tests to assert aliases are absent |
| FR5 | When a user passes a related-but-unaliased flag (e.g., `--host`), the error message explicitly names the canonical flag rather than the generic clap tip | Should | Requires a custom error handler or a `TryFromArgMatches` layer for the three affected commands |
| FR6 | Sweep the remaining subcommands for additional flag/positional divergences and document them in a follow-up issue if any are found | Could | Scope limited to a read-only audit; any further aliases are a separate issue |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | No measurable startup-time regression; alias parsing adds zero CDP round-trips |
| **Security** | `--url` input must be validated as a parseable URL before host extraction — reject malformed input with exit code 1 |
| **Platforms** | All platforms supported by agentchrome (macOS, Linux, Windows) |
| **Backwards Compatibility** | Canonical forms MUST remain byte-identical in behavior, output, and exit codes |

---

## Data Requirements

### Input Data (new)

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `cookie set --url` | URL string | Must parse via `url::Url::parse`; must have a `host_str()` | No (mutually equivalent to `--domain`) |
| `tabs close --tab` | String (repeatable) | Same validation as positional `targets` | No (at least one of positional or `--tab` required) |

### Output Data

No change. Aliases produce identical JSON output to their canonical forms.

---

## Dependencies

### Internal Dependencies
- [ ] `src/cli/mod.rs` — add alias attributes and new optional fields on `CookieSetArgs` / `TabsCloseArgs`
- [ ] `src/cookie.rs` — post-parse: if `--url` was supplied, extract host and use as domain
- [ ] `src/tabs.rs` — post-parse: merge `--tab` values into the target list
- [ ] `src/examples/commands.rs` — confirm examples continue to show only canonical forms
- [ ] `src/capabilities.rs` — confirm aliases are absent from manifest

### External Dependencies
- [ ] `url` crate for URL parsing (add to Cargo.toml if not already transitively available as a first-class dep)

### Blocked By
- None

---

## Out of Scope

- Breaking-change renames of the canonical forms (e.g., renaming `dom select` to `dom query`) — aliases only
- Rewriting the argument parser or introducing a custom parser layer beyond what clap supports natively
- Adding aliases for completely unrelated guesses outside the three documented divergences
- Promoting any of the three aliases to `visible_alias` or canonical status in this release
- Full audit + aliasing of every remaining subcommand (FR6 captures the read-only audit; any further aliases ship in a separate issue)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Self-teaching property restored | 3 of 3 divergences accept the natural guess | BDD scenarios AC1, AC2, AC4 pass |
| Zero canonical-form regressions | 0 behavior changes on canonical invocations | AC5 + existing cookie/tabs/dom BDD suites still pass |
| Zero documentation drift | Aliases absent from help, capabilities, examples | AC6 BDD scenario |

---

## Open Questions

- [ ] FR5 (custom error messages pointing at canonical flag) may require a `try_parse_from` + error-message-rewrite layer. If the implementation cost is high, drop to a `Could` and ship FR1–FR4 alone.
- [ ] For `--url`, should a URL without a `host_str()` (e.g., `file:///foo`) fall back to no domain, or error? Current proposal: error with exit code 1 and a message naming `--domain` as the canonical alternative.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #230 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified (AC7, AC8)
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented
