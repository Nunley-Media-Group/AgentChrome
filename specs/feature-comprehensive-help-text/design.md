# Design: Comprehensive Help Text

**Issue**: #26
**Date**: 2026-02-14
**Status**: Approved
**Author**: Claude (automated)

---

## Overview

This feature adds rich, AI-agent-optimized `--help` documentation to every command, subcommand, and flag in agentchrome. The implementation is purely additive — it modifies the clap derive attributes in `src/cli/mod.rs` to add `after_help`, `after_long_help`, and enhanced `long_about` strings. No runtime behavior changes. No new files are created. The entire change is confined to compile-time string literals in the existing CLI definition module.

The design leverages clap 4's attribute system: `about` (short), `long_about` (detailed), `after_help` (shown after options in short help), and `after_long_help` (shown after options in long help). We use `after_long_help` for usage examples so they appear with `--help` but not with `-h`, keeping short help concise.

---

## Architecture

### Component Diagram

This is a documentation-only change. No new components are introduced.

```
src/cli/mod.rs (MODIFIED)
├── Cli struct          ← Add after_long_help with quick-start + exit codes
├── Command enum        ← Enhance long_about on each variant
│   ├── Connect         ← Add after_long_help with examples
│   ├── Tabs            ← Add after_long_help with examples
│   ├── Navigate        ← Add after_long_help with examples
│   ├── Page            ← Add after_long_help with examples
│   ├── Js              ← Add after_long_help with examples
│   ├── Console         ← Add after_long_help with examples
│   ├── Network         ← Add after_long_help with examples
│   ├── Interact        ← Add after_long_help with examples
│   ├── Form            ← Add after_long_help with examples
│   ├── Emulate         ← Add after_long_help with examples
│   ├── Perf            ← Add after_long_help with examples
│   ├── Dialog          ← Add after_long_help with examples
│   ├── Config          ← Add after_long_help with examples
│   └── Completions     ← Already has installation examples
├── Leaf subcommands    ← Add long_about + after_long_help to each
└── Arg/flag fields     ← Review and enhance help strings
```

### Data Flow

No data flow changes. Help text is rendered by clap at parse-time when `--help` or `-h` is passed. The text is embedded as `&'static str` literals in the binary.

---

## API / Interface Changes

### CLI Help Output Changes

No API changes. The only user-visible change is richer `--help` output.

**Before:**
```
$ agentchrome tabs --help
Tab management (list, create, close, activate)

Usage: agentchrome tabs <COMMAND>

Commands:
  list      List open tabs
  create    Create a new tab
  close     Close one or more tabs
  activate  Activate (focus) a tab
```

**After:**
```
$ agentchrome tabs --help
Tab management commands: list open tabs, create new tabs, close tabs, and
activate (focus) a specific tab. Each operation returns structured JSON with
tab IDs and metadata.

Usage: agentchrome tabs <COMMAND>

Commands:
  list      List open tabs
  create    Create a new tab
  close     Close one or more tabs
  activate  Activate (focus) a tab

EXAMPLES:
  # List all open tabs
  agentchrome tabs list

  # Open a new tab and get its ID
  agentchrome tabs create https://example.com

  # Close tabs by ID
  agentchrome tabs close ABC123 DEF456
```

---

## Database / Storage Changes

None.

---

## State Management

None — stateless string literals.

---

## UI Components

None — this is a CLI tool, not a GUI application.

---

## Help Text Architecture

### Attribute Strategy

| Level | `about` | `long_about` | `after_long_help` |
|-------|---------|-------------|-------------------|
| Root (`Cli`) | One-line tool description | Multi-paragraph overview | Quick-start workflows + exit codes |
| Command group | One-line group description | What the group does + return format | 2–4 group-level examples |
| Leaf command | One-line summary | Detailed: what it does, return JSON, use cases, related commands | 2–3 concrete examples |
| Flag/arg | `help` string via doc comment | N/A | N/A |

### Why `after_long_help` Instead of `after_help`

Using `after_long_help` ensures examples only appear with `--help` (verbose), not `-h` (brief). This keeps the short help output concise for users who just need a quick reminder, while giving AI agents comprehensive detail with `--help`.

### Style Guide

| Element | Convention | Example |
|---------|-----------|---------|
| Command descriptions | Imperative voice, present tense | "List open browser tabs" |
| Flag descriptions | Sentence fragment, lowercase start | "target tab ID (defaults to the active tab)" |
| Examples | Shell comment + command | `# List all tabs` / `agentchrome tabs list` |
| Return value docs | "Returns JSON with..." | "Returns JSON with tab ID, title, and URL" |
| Cross-references | "See also: agentchrome ..." | "See also: agentchrome tabs activate" |

### Top-Level `after_long_help` Structure

```
QUICK START:
  # Connect to Chrome and list tabs
  agentchrome connect && agentchrome tabs list

  # Navigate and take a screenshot
  agentchrome navigate https://example.com
  agentchrome page screenshot --file shot.png

  # Execute JavaScript and get the result
  agentchrome js exec "document.title"

  # Fill a form field
  agentchrome page snapshot
  agentchrome form fill s5 "hello@example.com"

  # Monitor console output in real time
  agentchrome console follow --timeout 5000

EXIT CODES:
  0  Success
  1  General error (invalid arguments, internal failure)
  2  Connection error (Chrome not running, session expired)
  3  Target error (tab not found, no page targets)
  4  Timeout error (navigation or trace timeout)
  5  Protocol error (CDP protocol failure, dialog handling error)

ENVIRONMENT VARIABLES:
  AGENTCHROME_PORT     CDP port number (default: 9222)
  AGENTCHROME_HOST     CDP host address (default: 127.0.0.1)
  AGENTCHROME_TIMEOUT  Default command timeout in milliseconds
  AGENTCHROME_CONFIG   Path to configuration file
```

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: External man pages** | Generate man pages with `clap_mangen` | Rich formatting, searchable | Not accessible to AI agents reading `--help` | Rejected — AI agents can't read man pages |
| **B: README-only docs** | Document everything in README.md | Easy to maintain | AI agents don't read READMEs; `--help` is discovery mechanism | Rejected — `--help` is primary |
| **C: Inline `after_long_help` (selected)** | Add examples and docs via clap attributes | Co-located with code, always accurate, AI-accessible | Long string literals in source | **Selected** — best for AI agent discovery |
| **D: Separate help text module** | Move help strings to `src/cli/help_text.rs` | Cleaner `mod.rs` | Indirection, harder to maintain in sync | Rejected — locality is more valuable |

---

## Security Considerations

- [x] **No security impact** — this is purely additive help text documentation
- [x] **No user input** — all text is compile-time string literals
- [x] **No secrets** — no sensitive information in help text

---

## Performance Considerations

- [x] **Zero runtime cost** — all strings are `&'static str` baked into the binary
- [x] **Binary size** — expected ~5–10 KB increase from additional string data (negligible)
- [x] **Compile time** — no measurable impact

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI output | BDD/Integration | Verify `--help` output contains expected sections |
| Build | CI | `cargo build` succeeds with new text |
| Format | CI | `cargo fmt --check` passes |
| Lint | CI | `cargo clippy` passes |

The BDD tests will verify:
1. Top-level help contains quick-start section and exit codes
2. Each command group help contains examples
3. Each leaf command help contains detailed description and examples
4. No placeholder/TODO text remains in any help output

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| String literal typos | Medium | Low | BDD tests verify key phrases; `cargo build` catches syntax errors |
| Inconsistent style | Medium | Low | Style guide in design doc; review pass as final task |
| Line wrapping issues | Low | Low | `term_width = 100` in clap config; manual review |
| Out-of-date examples | Low | Medium | Examples reference existing commands; keep examples simple |

---

## Open Questions

None.

---

## Validation Checklist

- [x] Architecture follows existing project patterns (per `structure.md`)
- [x] All interface changes documented (help output format)
- [x] No database/storage changes
- [x] No state management changes
- [x] No new UI components
- [x] Security considerations addressed (no impact)
- [x] Performance impact analyzed (negligible)
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
