# agentchrome

**A CLI tool for browser automation via the Chrome DevTools Protocol.**

![CI](https://github.com/Nunley-Media-Group/AgentChrome/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue)
<!-- ![Crates.io](https://img.shields.io/crates/v/agentchrome) TODO: uncomment when published -->

A fast, standalone command-line tool for automating Chrome and Chromium browsers. No Node.js, no Python — just a single native binary that speaks the Chrome DevTools Protocol (CDP) directly over WebSocket.

## Features

- **Tab management** — list, create, close, and activate browser tabs
- **URL navigation** — navigate to URLs, go back/forward, reload, and manage history
- **Page inspection** — capture accessibility trees, extract text, find elements
- **Screenshots** — full-page and viewport screenshots to file or stdout
- **JavaScript execution** — run scripts in the page context, return results as JSON
- **Form filling** — fill inputs, select options, and submit forms by accessibility UID
- **Network monitoring** — follow requests in real time, intercept and block URLs
- **Console capture** — read and follow console messages with type filtering
- **Performance tracing** — start/stop Chrome trace recordings, collect metrics
- **Device emulation** — emulate mobile devices, throttle network/CPU, set geolocation
- **Dialog handling** — accept, dismiss, or respond to alert/confirm/prompt dialogs
- **Shell integration** — completion scripts for Bash, Zsh, Fish, PowerShell, and Elvish
- **Man pages** — built-in man page viewer via `agentchrome man`

### How does agentchrome compare?

| | agentchrome | Puppeteer / Playwright | Chrome DevTools MCP |
|---|---|---|---|
| **Runtime** | No Node.js — native Rust binary | Node.js | Node.js |
| **Install** | Single binary, `cargo install` | `npm install` | `npx` |
| **Interface** | CLI / shell scripts | JavaScript API | MCP protocol |
| **Startup time** | < 50ms | ~500ms+ | Varies |
| **Binary size** | < 10 MB | ~100 MB+ (with deps) | Varies |
| **Shell pipelines** | First-class (`| jq`, `| grep`) | Requires wrapper scripts | Not designed for CLI |

## Installation

### Pre-built binaries

Download the latest release for your platform from [GitHub Releases](https://github.com/Nunley-Media-Group/AgentChrome/releases).

<details>
<summary>Quick install via curl (macOS / Linux)</summary>

```sh
# macOS (Apple Silicon)
curl -fsSL https://github.com/Nunley-Media-Group/AgentChrome/releases/latest/download/agentchrome-aarch64-apple-darwin.tar.gz \
  | tar xz && mv agentchrome-*/agentchrome /usr/local/bin/

# macOS (Intel)
curl -fsSL https://github.com/Nunley-Media-Group/AgentChrome/releases/latest/download/agentchrome-x86_64-apple-darwin.tar.gz \
  | tar xz && mv agentchrome-*/agentchrome /usr/local/bin/

# Linux (x86_64)
curl -fsSL https://github.com/Nunley-Media-Group/AgentChrome/releases/latest/download/agentchrome-x86_64-unknown-linux-gnu.tar.gz \
  | tar xz && mv agentchrome-*/agentchrome /usr/local/bin/

# Linux (ARM64)
curl -fsSL https://github.com/Nunley-Media-Group/AgentChrome/releases/latest/download/agentchrome-aarch64-unknown-linux-gnu.tar.gz \
  | tar xz && mv agentchrome-*/agentchrome /usr/local/bin/
```

</details>

### Cargo install

```sh
cargo install agentchrome
```

### Build from source

```sh
git clone https://github.com/Nunley-Media-Group/AgentChrome.git
cd agentchrome
cargo build --release
# Binary is at target/release/agentchrome
```

### Supported platforms

| Platform | Target | Archive |
|---|---|---|
| macOS (Apple Silicon) | `aarch64-apple-darwin` | `.tar.gz` |
| macOS (Intel) | `x86_64-apple-darwin` | `.tar.gz` |
| Linux (x86_64) | `x86_64-unknown-linux-gnu` | `.tar.gz` |
| Linux (ARM64) | `aarch64-unknown-linux-gnu` | `.tar.gz` |
| Windows (x86_64) | `x86_64-pc-windows-msvc` | `.zip` |

## Quick Start

**1. Install agentchrome** (see [Installation](#installation) above)

**2. Start Chrome with remote debugging enabled:**

```sh
# macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222

# Linux
google-chrome --remote-debugging-port=9222

# Or launch headless Chrome directly via agentchrome:
agentchrome connect --launch --headless
```

**3. Connect to Chrome:**

```sh
agentchrome connect
```

**4. Navigate to a URL:**

```sh
agentchrome navigate https://example.com
```

**5. Inspect the page:**

```sh
agentchrome page snapshot
```

## Usage Examples

<details>
<summary><strong>Taking a screenshot</strong></summary>

```sh
# Viewport screenshot
agentchrome page screenshot --file screenshot.png

# Full-page screenshot
agentchrome page screenshot --full-page --file full-page.png
```

</details>

<details>
<summary><strong>Extracting page text</strong></summary>

```sh
# Get the visible text content of the page
agentchrome page text
```

</details>

<details>
<summary><strong>Executing JavaScript</strong></summary>

```sh
# Run a JavaScript expression and get the result
agentchrome js exec "document.title"

# Run JavaScript from a file
agentchrome js exec --file script.js
```

</details>

<details>
<summary><strong>Filling forms</strong></summary>

```sh
# First, capture the accessibility tree to find UIDs
agentchrome page snapshot

# Fill a single field by accessibility UID
agentchrome form fill s5 "hello@example.com"

# Fill multiple fields at once
agentchrome form fill-many s5="hello@example.com" s8="MyPassword123"

# Submit a form
agentchrome form submit s10
```

</details>

<details>
<summary><strong>Monitoring network requests</strong></summary>

```sh
# Follow network requests in real time
agentchrome network follow --timeout 5000

# Block specific URLs
agentchrome network block "*.ads.example.com"
```

</details>

<details>
<summary><strong>Performance tracing</strong></summary>

```sh
# Record a trace for 5 seconds
agentchrome perf record --duration 5000

# Record until Ctrl+C, with page reload
agentchrome perf record --reload

# Save to a specific file
agentchrome perf record --duration 5000 --file trace.json

# Get Core Web Vitals
agentchrome perf vitals
```

</details>

## Command Reference

| Command | Description |
|---|---|
| `connect` | Connect to or launch a Chrome instance |
| `tabs` | Tab management (list, create, close, activate) |
| `navigate` | URL navigation and history |
| `page` | Page inspection (screenshot, text, accessibility tree, find) |
| `dom` | DOM inspection and manipulation |
| `js` | JavaScript execution in page context |
| `console` | Console message reading and monitoring |
| `network` | Network request monitoring and interception |
| `interact` | Mouse, keyboard, and scroll interactions |
| `form` | Form input and submission |
| `emulate` | Device and network emulation |
| `perf` | Performance tracing and metrics |
| `dialog` | Browser dialog handling (alert, confirm, prompt, beforeunload) |
| `config` | Configuration file management (show, init, path) |
| `completions` | Generate shell completion scripts |
| `man` | Display man pages for agentchrome commands |

Run `agentchrome <command> --help` for detailed usage of any command, or `agentchrome man <command>` to view its man page.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    agentchrome                         │
│                                                      │
│  ┌────────────┐   ┌─────────────┐   ┌────────────┐  │
│  │  CLI Layer  │──▶│  Command    │──▶│ CDP Client │  │
│  │  (clap)     │   │  Dispatch   │   │ (WebSocket)│  │
│  └────────────┘   └─────────────┘   └─────┬──────┘  │
│                                            │         │
└────────────────────────────────────────────┼─────────┘
                                             │ JSON-RPC
                                             ▼
                                    ┌─────────────────┐
                                    │  Chrome Browser  │
                                    │  (DevTools       │
                                    │   Protocol)      │
                                    └─────────────────┘
```

**How it works:** agentchrome communicates with Chrome using the [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) (CDP) over a WebSocket connection. Commands are sent as JSON-RPC messages; responses and events flow back on the same connection.

**Session management:** When you run `agentchrome connect`, a session file is created with the WebSocket URL. Subsequent commands reuse this connection automatically. The session persists until you run `agentchrome connect disconnect` or Chrome exits.

**Performance:** agentchrome is a native Rust binary with sub-50ms startup time. There is no interpreter, no runtime, and no JIT warmup — it goes straight from your shell to Chrome.

## Claude Code Integration

agentchrome is designed for AI agent consumption. See the full
[Claude Code Integration Guide](docs/claude-code.md) for discovery mechanisms,
common workflows, best practices, and error handling patterns.

Drop the [CLAUDE.md template](examples/CLAUDE.md.example) into your project to
give Claude Code browser automation capabilities out of the box.

## Related Projects

- **[Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp)** — The official Chrome DevTools MCP server by Google, providing browser automation for AI coding agents via the Model Context Protocol. If you're looking for MCP-based browser control rather than a CLI tool, check it out.

## Contributing

All contributions must follow the [NMG-SDLC](https://github.com/Nunley-Media-Group/nmg-plugins) workflow without deviation. NMG-SDLC is a BDD spec-driven development toolkit that enforces a structured delivery lifecycle: issue creation, specification writing, implementation, verification, and PR creation. Contributions that bypass the SDLC process will not be accepted.

### Prerequisites

- [Rust](https://rustup.rs/) 1.85.0 or later (pinned via `rust-toolchain.toml`)
- Chrome or Chromium (for integration testing)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the [NMG-SDLC plugin](https://github.com/Nunley-Media-Group/nmg-plugins) installed

### Build and test

```sh
git clone https://github.com/Nunley-Media-Group/AgentChrome.git
cd agentchrome

# Build
cargo build

# Run tests
cargo test

# Lint
cargo clippy -- -D warnings
cargo fmt --check

# Generate man pages
cargo xtask man
```

### Code style

This project uses strict Clippy configuration (`all = "deny"`, `pedantic = "warn"`) and rustfmt with the 2024 edition. All warnings must be resolved before merging.

## License

Licensed under either of [MIT License](LICENSE-MIT) or [Apache License, Version 2.0](LICENSE-APACHE) at your option.
