# Tasks: Configuration File Support

**Issue**: #24
**Date**: 2026-02-14
**Status**: Planning
**Author**: Claude (writing-specs)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend | 4 | [ ] |
| Integration | 2 | [ ] |
| Testing | 3 | [ ] |
| **Total** | **11** | |

---

## Phase 1: Setup

### T001: Add `toml` and `dirs` dependencies

**File(s)**: `Cargo.toml`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `toml` crate added to `[dependencies]` with `derive` feature
- [ ] `dirs` crate added to `[dependencies]`
- [ ] `cargo check` succeeds with new dependencies
- [ ] No version conflicts with existing dependencies

**Notes**: `toml = { version = "0.8", features = ["parse"] }` and `dirs = "6"` (or latest stable). The `toml` crate provides TOML parsing; `dirs` provides cross-platform config directory paths.

### T002: Define config types and structs

**File(s)**: `src/config.rs`
**Type**: Create
**Depends**: T001
**Acceptance**:
- [ ] `ConfigFile` struct with `connection`, `launch`, `output`, `tabs` sections — all optional via `#[serde(default)]`
- [ ] `ConnectionConfig`, `LaunchConfig`, `OutputConfig`, `TabsConfig` section structs
- [ ] `ResolvedConfig` struct with all defaults filled in
- [ ] `ConfigError` enum for error handling (follows `SessionError` pattern)
- [ ] All structs derive `Debug`, `Serialize`, `Deserialize` as appropriate
- [ ] `ConfigError` implements `Display`, `Error`, and `From<ConfigError> for AppError`
- [ ] File compiles without warnings

**Notes**: Follow the pattern in `session.rs` for error types. Use `#[serde(default)]` on section structs so missing sections parse as defaults. Use `#[serde(deny_unknown_fields)]` on `ConfigFile` to catch typos (handle gracefully via two-pass parse: try strict, fall back to lenient with warning).

---

## Phase 2: Backend Implementation

### T003: Implement config file search and loading

**File(s)**: `src/config.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `find_config_file(explicit_path: Option<&Path>) -> Option<PathBuf>` checks 5 locations in priority order
- [ ] `load_config(explicit_path: Option<&Path>) -> (Option<PathBuf>, ConfigFile)` loads and parses, returns defaults on error
- [ ] Uses `dirs::config_dir()` for XDG/platform path
- [ ] Checks `CHROME_CLI_CONFIG` environment variable
- [ ] Invalid TOML prints warning to stderr and returns `ConfigFile::default()`
- [ ] Unknown keys print warning to stderr (two-pass: strict then lenient)
- [ ] Testable `_from` variants that accept explicit search paths
- [ ] Unit tests for each search location, priority order, missing file, invalid TOML, unknown keys

**Notes**: Search order: `explicit_path` → `$CHROME_CLI_CONFIG` → `./.chrome-cli.toml` → `dirs::config_dir()/chrome-cli/config.toml` → `home_dir()/.chrome-cli.toml`. Stop at first found file.

### T004: Implement config resolution (merge with CLI flags)

**File(s)**: `src/config.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] `resolve_config(file: &ConfigFile, path: Option<PathBuf>) -> ResolvedConfig` fills in all defaults
- [ ] Helper function to apply config defaults to `GlobalOpts` where CLI flags are `None`/unset
- [ ] Correctly handles: CLI flag set → use flag; CLI flag unset + config set → use config; both unset → use default
- [ ] Port validation: 1-65535 range (warn and ignore invalid)
- [ ] Output format validation: must be "json", "pretty", or "plain"
- [ ] Unit tests for each merge scenario

**Notes**: The merge function should be called after `Cli::parse()` in `main.rs`. It patches unset `GlobalOpts` fields from the config file.

### T005: Implement `config init` — generate default config file

**File(s)**: `src/config.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `init_config(target_path: Option<&Path>) -> Result<PathBuf, ConfigError>` creates a default config file
- [ ] Default path: `dirs::config_dir()/chrome-cli/config.toml` (or `~/.config/chrome-cli/config.toml`)
- [ ] Generated file includes all sections with commented-out example values
- [ ] Refuses to overwrite existing file (returns error)
- [ ] Creates parent directories if needed
- [ ] Sets file permissions to 0o600 on Unix
- [ ] Unit tests for create, already-exists, and custom path

**Notes**: The generated file should be a hand-crafted TOML template string (not serde-serialized), so that comments explaining each key are included.

### T006: Register config module in lib.rs

**File(s)**: `src/lib.rs`
**Type**: Modify
**Depends**: T002
**Acceptance**:
- [ ] `pub mod config;` added to `src/lib.rs`
- [ ] Module is accessible from `main.rs` and tests
- [ ] `cargo check` passes

---

## Phase 3: Integration

### T007: Add `Config` command and `--config` flag to CLI

**File(s)**: `src/cli/mod.rs`, `src/main.rs`
**Type**: Modify
**Depends**: T003, T004, T005, T006
**Acceptance**:
- [ ] `--config <PATH>` global flag added to `GlobalOpts`
- [ ] `Config` variant added to `Command` enum with `ConfigArgs` / `ConfigCommand` subcommand
- [ ] `ConfigCommand` has `Show`, `Init`, `Path` variants
- [ ] `Init` variant has optional `--path <PATH>` flag
- [ ] `env = "CHROME_CLI_HOST"` added to `--host` arg attribute
- [ ] `env = "CHROME_CLI_PORT"` added to `--port` arg attribute
- [ ] `env = "CHROME_CLI_TIMEOUT"` added to `--timeout` arg attribute
- [ ] Command dispatch in `run()` handles `Command::Config(args)` and delegates to config subcommand handlers
- [ ] Config is loaded early in `main()` / `run()` and applied to `GlobalOpts` before other commands execute
- [ ] `config show` outputs resolved config as JSON
- [ ] `config init` creates default config file or errors if exists
- [ ] `config path` outputs the active config file path or null
- [ ] All output follows existing JSON output pattern (`print_json`)

**Notes**: The config loading must happen after `Cli::parse()` but before command dispatch, so that all commands benefit from config defaults. For `config show`, the resolved config itself is the output.

### T008: Wire config defaults into existing command handlers

**File(s)**: `src/main.rs`
**Type**: Modify
**Depends**: T007
**Acceptance**:
- [ ] `execute_connect` uses config defaults for `headless`, `channel`, `chrome_path`, `extra_args` when not explicitly set via CLI
- [ ] `execute_launch` uses config `[launch]` defaults
- [ ] `GlobalOpts.host` uses config `[connection].host` when not overridden
- [ ] `GlobalOpts.port` uses config `[connection].port` when not overridden
- [ ] `GlobalOpts.timeout` uses config `[connection].timeout_ms` when not overridden
- [ ] Output format defaults from config `[output].format` when no `--json`/`--pretty`/`--plain` flag
- [ ] Tab behavior defaults from config `[tabs]` section
- [ ] No regressions: existing behavior unchanged when no config file exists

---

## Phase 4: BDD Testing

**Every acceptance criterion MUST have a Gherkin test.**

### T009: Create BDD feature file

**File(s)**: `tests/features/config/config.feature`
**Type**: Create
**Depends**: T007, T008
**Acceptance**:
- [ ] All 19 acceptance criteria from requirements.md are scenarios
- [ ] Uses Given/When/Then format
- [ ] Includes happy paths, error handling, and edge cases
- [ ] Feature file is valid Gherkin syntax
- [ ] Organized with comments for scenario grouping

### T010: Implement BDD step definitions

**File(s)**: `tests/bdd.rs` (modify existing)
**Type**: Modify
**Depends**: T009
**Acceptance**:
- [ ] Step definitions for config-related Given/When/Then steps
- [ ] Test fixtures create temporary config files
- [ ] Tests clean up temporary files after execution
- [ ] All scenarios pass
- [ ] Steps follow existing cucumber-rs patterns in bdd.rs

### T011: Unit tests for config module

**File(s)**: `src/config.rs` (inline `#[cfg(test)]` module)
**Type**: Modify
**Depends**: T003, T004, T005
**Acceptance**:
- [ ] Parse valid TOML with all sections
- [ ] Parse TOML with missing sections (defaults used)
- [ ] Parse empty TOML file (all defaults)
- [ ] Invalid TOML returns defaults with warning
- [ ] Unknown keys handled gracefully
- [ ] Config search priority (explicit > env > project > XDG > home)
- [ ] Merge: CLI flag overrides config
- [ ] Merge: config overrides defaults
- [ ] Merge: env var overrides config (via clap env feature)
- [ ] `config init` creates file with expected content
- [ ] `config init` refuses to overwrite
- [ ] Port validation (0, 65535, 65536)
- [ ] Output format validation

---

## Dependency Graph

```
T001 ──▶ T002 ──┬──▶ T003 ──▶ T004 ──┐
                │                      ├──▶ T007 ──▶ T008
                ├──▶ T005 ────────────┘       │
                └──▶ T006 ────────────────────┘
                                               │
                                               ├──▶ T009 ──▶ T010
                                               └──▶ T011
```

---

## Validation Checklist

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included for each layer
- [x] No circular dependencies
- [x] Tasks are in logical execution order
