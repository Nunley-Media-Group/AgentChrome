# Design: Configuration File Support

**Issue**: #24
**Date**: 2026-02-14
**Status**: Draft
**Author**: Claude (writing-specs)

---

## Overview

This feature adds TOML-based configuration file support to chrome-cli, allowing users to set persistent defaults for connection, launch, output, and tab behavior settings. A new `src/config.rs` module handles config file discovery, parsing, and merging. A new `Config` command group (`config show`, `config init`, `config path`) is added to the CLI.

The config module follows the same patterns as the existing `session.rs` module: standalone file I/O with typed error handling, no external dependencies beyond `toml` and `dirs` crates, and testable `_to`/`_from` variants for path-independent testing.

The precedence chain is: CLI flags > environment variables > config file > built-in defaults. Config values are applied by pre-populating `GlobalOpts` fields before clap processes CLI arguments, so clap's existing defaulting and override behavior is preserved.

---

## Architecture

### Component Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    CLI Layer (clap)                        │
├──────────────────────────────────────────────────────────┤
│  ┌──────────┐    ┌──────────┐    ┌──────────┐           │
│  │GlobalOpts│    │ Command  │    │ Config   │           │
│  │ (flags)  │    │(dispatch)│    │ Command  │           │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘           │
│       │               │               │                  │
│       └───────┬───────┘               │                  │
│               ▼                       ▼                  │
│  ┌─────────────────────┐  ┌────────────────────┐        │
│  │  Command Modules    │  │  config subcommands │        │
│  │ (tabs, navigate..)  │  │ (show, init, path)  │        │
│  └─────────────────────┘  └────────────────────┘        │
└──────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│                Library Layer (lib.rs)                      │
├──────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ config   │  │ session  │  │connection│  │  error  │ │
│  │ (NEW)    │  │          │  │          │  │         │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│                                                          │
│  ┌──────────┐  ┌──────────┐                              │
│  │   cdp    │  │  chrome   │                              │
│  └──────────┘  └──────────┘                              │
└──────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. main() calls config::load_config(cli_config_path)
2. config module searches priority-ordered locations for first existing .toml
3. If found, parses TOML into ConfigFile struct (warns on error, returns defaults)
4. Cli::parse() runs, clap populates GlobalOpts from CLI flags
5. main() calls config::resolve(config_file, &cli.global) to produce ResolvedConfig
6. ResolvedConfig is passed to command handlers (or used to patch GlobalOpts)
7. For `config show/init/path`: dedicated handlers use config module directly
```

### Config Resolution Priority

```
CLI flags (highest)
    ↓  override
Environment variables (CHROME_CLI_PORT, etc.)
    ↓  override
Config file (first found in search order)
    ↓  override
Built-in defaults (lowest)
```

### Config File Search Order

```
1. --config <PATH>         (explicit flag)
2. $CHROME_CLI_CONFIG      (environment variable)
3. ./.chrome-cli.toml      (project-local)
4. ~/.config/chrome-cli/config.toml  (XDG on Unix, %APPDATA% on Windows)
5. ~/.chrome-cli.toml      (home directory fallback)
```

---

## API / Interface Changes

### New CLI Command: `config`

| Subcommand | Purpose |
|------------|---------|
| `config show` | Display resolved configuration from all sources |
| `config init` | Create a default config file with comments |
| `config path` | Show which config file is active (or "none") |

### New Global Flag: `--config`

```
--config <PATH>    Path to configuration file (overrides default search)
```

Added to `GlobalOpts` as `Option<PathBuf>`, `global = true`.

### New Environment Variables

| Variable | Maps to | Description |
|----------|---------|-------------|
| `CHROME_CLI_CONFIG` | `--config` | Path to config file |
| `CHROME_CLI_HOST` | `--host` | CDP host address |
| `CHROME_CLI_PORT` | `--port` | CDP port number |
| `CHROME_CLI_TIMEOUT` | `--timeout` | Command timeout ms |

Note: clap's `env` feature is already enabled in Cargo.toml but not used on any flags. We will add `env = "CHROME_CLI_*"` attributes to the relevant `GlobalOpts` fields.

### Request / Response Schemas

#### `config show`

**Output (JSON):**
```json
{
  "config_path": "/home/user/.chrome-cli.toml",
  "connection": {
    "host": "127.0.0.1",
    "port": 9222,
    "timeout_ms": 30000
  },
  "launch": {
    "executable": null,
    "channel": "stable",
    "headless": false,
    "extra_args": []
  },
  "output": {
    "format": "json"
  },
  "tabs": {
    "auto_activate": true,
    "filter_internal": true
  }
}
```

#### `config init`

**Output (success):**
```json
{
  "created": "/home/user/.config/chrome-cli/config.toml"
}
```

**Output (already exists):**
```json
{
  "error": "Config file already exists: /home/user/.config/chrome-cli/config.toml",
  "code": 1
}
```

#### `config path`

**Output (found):**
```json
{
  "config_path": "/home/user/.chrome-cli.toml"
}
```

**Output (none):**
```json
{
  "config_path": null
}
```

---

## Database / Storage Changes

No database. Config files are read-only TOML files on the local filesystem.

### Config File Schema

```toml
# Connection defaults
[connection]
host = "127.0.0.1"
port = 9222
timeout_ms = 30000

# Chrome launch defaults
[launch]
executable = "/path/to/chrome"
channel = "stable"        # stable, beta, dev, canary
headless = false
extra_args = ["--disable-gpu"]

# Output defaults
[output]
format = "json"           # json, pretty, plain

# Default tab behavior
[tabs]
auto_activate = true
filter_internal = true
```

All sections and keys are optional. Missing keys use built-in defaults.

---

## State Management

No runtime state management needed. Config is loaded once at startup and passed immutably to command handlers.

### Config Structs

```rust
/// Represents the parsed TOML config file. All fields optional.
#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct ConfigFile {
    pub connection: ConnectionConfig,
    pub launch: LaunchConfig,
    pub output: OutputConfig,
    pub tabs: TabsConfig,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct ConnectionConfig {
    pub host: Option<String>,
    pub port: Option<u16>,
    pub timeout_ms: Option<u64>,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct LaunchConfig {
    pub executable: Option<String>,
    pub channel: Option<String>,
    pub headless: Option<bool>,
    pub extra_args: Option<Vec<String>>,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct OutputConfig {
    pub format: Option<String>,
}

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct TabsConfig {
    pub auto_activate: Option<bool>,
    pub filter_internal: Option<bool>,
}
```

### Resolved Config

```rust
/// Fully resolved configuration with all defaults filled in.
/// Used by command handlers.
#[derive(Debug, Serialize)]
pub struct ResolvedConfig {
    pub config_path: Option<PathBuf>,
    pub connection: ResolvedConnection,
    pub launch: ResolvedLaunch,
    pub output: ResolvedOutput,
    pub tabs: ResolvedTabs,
}
```

---

## UI Components

N/A — this is a CLI tool. Output follows the existing JSON/plain output pattern.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: Pre-populate clap defaults from config** | Read config before `Cli::parse()`, inject as clap defaults | Config values show in `--help`, seamless override | Requires building clap `Command` manually before parse, complex | Rejected — over-engineered |
| **B: Post-parse merge** | Parse CLI first, then merge config values for unset fields | Simple, clap stays unchanged, clear precedence | Config values don't appear in `--help` | **Selected** |
| **C: Use clap's `env` feature for everything** | Map all config to env vars, use clap `env = "..."` | Zero new code for merging | Can't support file-based config, env-only | Rejected — doesn't satisfy file requirement |

**Decision**: Option B — post-parse merge. After `Cli::parse()`, load the config file and fill in any `GlobalOpts` fields that weren't explicitly set by the user. This is the simplest approach and matches how tools like `cargo`, `gh`, and `rustfmt` handle config. The `env` feature on clap attributes is used for environment variable overrides (CHROME_CLI_PORT, etc.), which composes naturally with Option B.

---

## Security Considerations

- [x] **Authentication**: N/A — local filesystem only
- [x] **Authorization**: Config files should be user-readable; `config init` creates with 0o600 permissions on Unix
- [x] **Input Validation**: TOML parsing with `deny_unknown_fields` to catch typos; port range validation (1-65535)
- [x] **Data Sanitization**: Config values are used as connection parameters, not executed — no injection risk
- [x] **Sensitive Data**: Config files may contain host/port but no credentials. No secrets in config.

---

## Performance Considerations

- [x] **Config loading**: Single file read + TOML parse — < 1ms for typical config files
- [x] **Search path**: At most 5 `fs::metadata` checks to find config file — negligible
- [x] **No caching needed**: Config is loaded once at startup
- [x] **Binary size**: `toml` crate adds ~100-200KB; `dirs` crate is minimal

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| Config parsing | Unit | Parse valid TOML, missing sections, invalid TOML, unknown keys |
| Config search | Unit | Priority order, explicit path, env var, project-local, XDG, home |
| Config merging | Unit | CLI overrides config, env overrides config, defaults |
| Config commands | Unit | show, init, path output format |
| End-to-end | BDD (cucumber-rs) | All acceptance criteria as Gherkin scenarios |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `toml` crate adds binary bloat | Low | Low | Crate is lightweight (~100KB); acceptable |
| `deny_unknown_fields` breaks forward compat | Med | Low | Use `deny_unknown_fields` on outer `ConfigFile` only; warn on unknown keys but don't fail hard (catch serde error, warn, re-parse without deny) |
| Config file discovery too slow on network mounts | Low | Low | Only stat 5 paths; short-circuit on first found |
| Windows XDG path differs | Med | Med | Use `dirs` crate which handles platform differences |

---

## Open Questions

- (none — all resolved)

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All API/interface changes documented with schemas
- [x] No database changes needed
- [x] State management approach is clear (stateless — load once at startup)
- [x] N/A for UI components (CLI tool)
- [x] Security considerations addressed
- [x] Performance impact analyzed
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
