# Requirements: Configuration File Support

**Issue**: #24
**Date**: 2026-02-14
**Status**: Draft
**Author**: Claude (writing-specs)

---

## User Story

**As a** developer or automation engineer using chrome-cli repeatedly
**I want** to set default values for flags in a configuration file
**So that** I don't have to repeat common flags on every invocation, reducing overhead for scripted and AI-agent workflows

---

## Background

chrome-cli is frequently invoked by AI agents and automation scripts. Each invocation currently requires explicit flags for host, port, timeout, output format, and Chrome launch settings. A configuration file allows users to set project-level or user-level defaults once, making every subsequent invocation shorter and more consistent. The priority chain (CLI flags > env vars > project config > user config > built-in defaults) follows established CLI conventions.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Load config from explicit --config path

**Given** a valid TOML config file exists at `/tmp/my-config.toml`
**When** the user runs `chrome-cli --config /tmp/my-config.toml config show`
**Then** the resolved configuration reflects values from that file

**Example**:
- Given: `/tmp/my-config.toml` contains `[connection]\nport = 9333`
- When: `chrome-cli --config /tmp/my-config.toml config show`
- Then: output shows `port = 9333`

### AC2: Load config from CHROME_CLI_CONFIG environment variable

**Given** `CHROME_CLI_CONFIG` is set to a path containing a valid TOML config
**And** no `--config` flag is provided
**When** the user runs `chrome-cli config show`
**Then** the resolved configuration reflects values from the env-var-specified file

### AC3: Load config from project-local file

**Given** `./.chrome-cli.toml` exists in the current working directory
**And** no `--config` flag or `CHROME_CLI_CONFIG` env var is set
**When** the user runs `chrome-cli config show`
**Then** the resolved configuration reflects values from `./.chrome-cli.toml`

### AC4: Load config from XDG standard path

**Given** `~/.config/chrome-cli/config.toml` exists
**And** no higher-priority config source is present
**When** the user runs `chrome-cli config show`
**Then** the resolved configuration reflects values from the XDG path

### AC5: Load config from home directory fallback

**Given** `~/.chrome-cli.toml` exists
**And** no higher-priority config source is present
**When** the user runs `chrome-cli config show`
**Then** the resolved configuration reflects values from `~/.chrome-cli.toml`

### AC6: Config file priority order

**Given** config files exist at multiple locations (project-local and home directory)
**When** the user runs `chrome-cli config show`
**Then** the project-local file takes precedence over the home directory file
**And** only the highest-priority file is used

### AC7: CLI flags override config file values

**Given** a config file sets `port = 9333`
**When** the user runs `chrome-cli --port 9444 config show`
**Then** the resolved port is `9444` (CLI flag wins)

### AC8: Environment variables override config file values

**Given** a config file sets `port = 9333`
**And** `CHROME_CLI_PORT` is set to `9555`
**When** the user runs `chrome-cli config show`
**Then** the resolved port is `9555` (env var wins)

### AC9: Connection defaults in config

**Given** a config file contains `[connection]` section with `host`, `port`, and `timeout_ms`
**When** the user runs a command without specifying those flags
**Then** the connection uses the values from the config file

### AC10: Chrome launch defaults in config

**Given** a config file contains `[launch]` section with `executable`, `channel`, `headless`, and `extra_args`
**When** the user runs `chrome-cli connect --launch`
**Then** Chrome is launched with the config file defaults

### AC11: Output format defaults in config

**Given** a config file contains `[output]\nformat = "json"`
**When** the user runs a command without specifying `--json`, `--pretty`, or `--plain`
**Then** the output uses JSON format

### AC12: Tab behavior defaults in config

**Given** a config file contains `[tabs]` section with `auto_activate` and `filter_internal`
**When** the user runs tab-related commands
**Then** the tab behavior uses the config file defaults

### AC13: config show — display resolved configuration

**Given** a config file exists with custom values
**When** the user runs `chrome-cli config show`
**Then** the output displays the fully resolved configuration merged from all sources
**And** the output format respects `--json`/`--pretty`/`--plain` flags

### AC14: config init — create default config file

**Given** no config file exists at `~/.config/chrome-cli/config.toml`
**When** the user runs `chrome-cli config init`
**Then** a default config file is created with commented example values
**And** the file path is printed to stdout

### AC15: config init — refuse to overwrite existing file

**Given** a config file already exists at the target path
**When** the user runs `chrome-cli config init`
**Then** the tool prints a warning that the file already exists
**And** does not overwrite it
**And** exits with a non-zero exit code

### AC16: config path — show active config file path

**Given** a config file is being loaded from `~/.chrome-cli.toml`
**When** the user runs `chrome-cli config path`
**Then** the output shows `~/.chrome-cli.toml` (the resolved path)

### AC17: config path — no config file found

**Given** no config file exists at any search location
**When** the user runs `chrome-cli config path`
**Then** the output indicates no config file is in use

### AC18: Invalid config file — graceful degradation

**Given** a config file exists but contains invalid TOML syntax
**When** the user runs any command
**Then** a warning is printed to stderr describing the parse error
**And** the command continues with built-in defaults
**And** the exit code is 0 (success) if the command itself succeeds

### AC19: Config file with unknown keys — warn and ignore

**Given** a config file contains unknown keys (e.g., `[connection]\nfoo = "bar"`)
**When** the user runs any command
**Then** a warning is printed to stderr about the unknown key
**And** the command continues normally

### Generated Gherkin Preview

```gherkin
Feature: Configuration file support
  As a developer or automation engineer
  I want to set default values in a configuration file
  So that I don't repeat common flags on every invocation

  Scenario: Load config from explicit --config path
    Given a valid config file at "/tmp/my-config.toml" with port 9333
    When I run "chrome-cli --config /tmp/my-config.toml config show"
    Then the resolved port should be 9333

  Scenario: Load config from CHROME_CLI_CONFIG env var
    Given a valid config file at "/tmp/env-config.toml"
    And CHROME_CLI_CONFIG is set to "/tmp/env-config.toml"
    When I run "chrome-cli config show"
    Then the config file path should be "/tmp/env-config.toml"

  Scenario: Config file priority order
    Given a project-local config with port 1111
    And a home directory config with port 2222
    When I run "chrome-cli config show"
    Then the resolved port should be 1111

  Scenario: CLI flags override config
    Given a config file with port 9333
    When I run "chrome-cli --port 9444 config show"
    Then the resolved port should be 9444

  Scenario: Invalid config file graceful degradation
    Given a config file with invalid TOML syntax
    When I run "chrome-cli config show"
    Then a warning is printed to stderr
    And the command completes with defaults
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Load and parse TOML config files from a priority-ordered search path | Must | 5 locations in order |
| FR2 | Merge config values with CLI flags and env vars (flags > env > config > defaults) | Must | Core precedence chain |
| FR3 | `config show` subcommand displays resolved configuration | Must | Supports --json output |
| FR4 | `config init` subcommand creates a default config file with comments | Must | XDG path by default |
| FR5 | `config path` subcommand shows which config file is active | Must | |
| FR6 | Support `[connection]`, `[launch]`, `[output]`, and `[tabs]` config sections | Must | Per issue spec |
| FR7 | Warn on invalid TOML and continue with defaults | Must | Don't hard-fail |
| FR8 | Warn on unknown keys in config file | Should | Help users find typos |
| FR9 | `config init --path <PATH>` to create config at a custom location | Could | |
| FR10 | Config file validation command (`config check`) | Won't (this release) | Future enhancement |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Config file loading adds < 1ms to startup time |
| **Security** | Config file permissions should be user-readable only (0o600 recommended, not enforced) |
| **Reliability** | Invalid/missing config files must never prevent command execution |
| **Platforms** | macOS, Linux, and Windows — XDG paths on Unix, %APPDATA% on Windows |

---

## Data Requirements

### Input Data (Config File Schema)

| Section | Key | Type | Validation | Required |
|---------|-----|------|------------|----------|
| `[connection]` | `host` | String | Valid hostname/IP | No |
| `[connection]` | `port` | Integer | 1-65535 | No |
| `[connection]` | `timeout_ms` | Integer | > 0 | No |
| `[launch]` | `executable` | String | Valid file path | No |
| `[launch]` | `channel` | String | "stable", "beta", "dev", "canary" | No |
| `[launch]` | `headless` | Boolean | true/false | No |
| `[launch]` | `extra_args` | Array of Strings | Any Chrome flags | No |
| `[output]` | `format` | String | "json", "pretty", "plain" | No |
| `[tabs]` | `auto_activate` | Boolean | true/false | No |
| `[tabs]` | `filter_internal` | Boolean | true/false | No |

### Output Data (config show)

| Field | Type | Description |
|-------|------|-------------|
| `config_path` | String or null | Path to the active config file |
| `connection` | Object | Resolved connection settings |
| `launch` | Object | Resolved launch settings |
| `output` | Object | Resolved output settings |
| `tabs` | Object | Resolved tab settings |

---

## Dependencies

### Internal Dependencies
- [x] Issue #3 (CLI skeleton) — already implemented

### External Dependencies
- [ ] `toml` crate — TOML parsing
- [ ] `dirs` or `directories` crate — XDG/platform config paths

### Blocked By
- None (CLI skeleton is complete)

---

## Out of Scope

- Config file encryption or secrets management
- Profile/preset support (e.g., `--profile staging`)
- Remote/shared configuration
- Config file validation command (`config check`)
- YAML or JSON config format alternatives
- Config file auto-reload / file watching
- Per-command config sections (e.g., `[screenshot]` defaults)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Config load overhead | < 1ms | Benchmark startup with/without config |
| All AC scenarios pass | 19/19 | BDD test suite |
| No regressions | 0 failures | Existing test suite passes |

---

## Open Questions

- (none — all resolved from issue description)

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
