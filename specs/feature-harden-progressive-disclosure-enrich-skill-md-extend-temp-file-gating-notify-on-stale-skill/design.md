# Design: Harden Progressive Disclosure — Enrich SKILL.md, Extend Temp-File Gating, Notify on Stale Skill

**Issues**: #220
**Date**: 2026-04-22
**Status**: Draft
**Author**: Claude (AI-assisted)

---

## Overview

Three coordinated changes land in a single PR because they are interdependent: advertising a response pattern that hasn't been rolled out, or expanding coverage a skill never mentions, would defeat the purpose of either change alone.

1. **SKILL.md template rewrite** (`src/skill.rs`) — add YAML frontmatter with rich trigger phrases and enrich the body with the three high-leverage discovery paths (`diagnose`, `examples strategies`, `--include-snapshot`) plus a one-sentence explanation of the temp-file response pattern.
2. **`output::emit` coverage extension** — wire the existing `emit`/`emit_plain` helpers into `audit`, `dom select/attributes/events`, `page analyze`, `page find`, `console read`, every `--include-snapshot` code path in `interact.rs`/`form.rs`/`navigate.rs`, and (when #218 lands) `capabilities <command>`. A new `emit_with_snapshot` helper handles the compound schema so interaction confirmation fields stay inline even when the embedded snapshot triggers the gate.
3. **Skill-staleness check** — a new `src/skill_check.rs` module runs at the top of `run()` in `src/main.rs`, stats each installed skill against the seven-tool registry, parses an embedded version marker, and emits a single aggregated stderr line when any tool's marker trails `CARGO_PKG_VERSION`. Suppressible via `AGENTCHROME_NO_SKILL_CHECK=1` or `skill.check_enabled = false` in config.

All three changes are additive — no existing AC of the large-response feature is modified, no existing skill-command-group behavior is broken. The compound `--include-snapshot` schema is documented here as an **approved extension** to AC21 of the original large-response spec: the inner `snapshot` object reuses the `{output_file, size_bytes, command, summary}` shape unchanged, and interaction-confirmation fields are additive top-level keys on the outer object.

---

## Architecture

### Component Diagram

Reference `steering/structure.md` for the project's layer architecture.

```
┌───────────────────────────────────────────────────────────────┐
│                     CLI Layer (cli/mod.rs)                      │
│  No structural changes. SKILL.md template authorship is data,  │
│  not clap metadata. No new flags for the staleness check —    │
│  suppression is env/config only.                              │
└───────────────────────────┬───────────────────────────────────┘
                            ▼
┌───────────────────────────────────────────────────────────────┐
│                    Dispatch (main.rs `run()`)                  │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  NEW: skill_check::emit_stale_notice_if_any(&config)    │  │
│  │  runs before the `match cli.command` dispatch, after    │  │
│  │  config load. Best-effort; never aborts.                │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────┬───────────────────────────────────┘
                            ▼
┌───────────────────────────────────────────────────────────────┐
│              Command Modules (one per command group)           │
│                                                                │
│  audit.rs ──┐                                                  │
│  dom.rs    ─┤                                                  │
│  page/*.rs ─┼──▶ output::emit(...) (replaces print_output)     │
│  console.rs ┤                                                  │
│  capabilities_cli.rs ◀── gated when #218 detail path lands     │
│                                                                │
│  interact.rs ┐                                                 │
│  form.rs    ─┼──▶ output::emit_with_snapshot(...)              │
│  navigate.rs ┘   (NEW helper — compound schema)                │
└───────────────────────────┬───────────────────────────────────┘
                            ▼
┌───────────────────────────────────────────────────────────────┐
│           output.rs — shared output layer (existing)            │
│  Existing: emit(), emit_plain(), TempFileOutput                │
│  NEW:      emit_with_snapshot()                                │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│                   skill.rs (existing module)                    │
│  Existing: TOOLS, InstallMode, install/uninstall/update/list   │
│  CHANGED:  SKILL_TEMPLATE — YAML frontmatter + new body        │
│  CHANGED:  AppendSection writer embeds                          │
│            <!-- agentchrome-version: X.Y.Z --> inside markers   │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│                   NEW: skill_check.rs                          │
│  - pub fn emit_stale_notice_if_any(config: &ConfigFile)        │
│  - fn stale_tools() -> Vec<StaleTool>                          │
│  - fn read_version_marker(path) -> Option<Version>             │
│  Silent on error; single-line stderr notice; aggregates.       │
└───────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Invocation start (main())
    ↓
clap parsing (unchanged)
    ↓
run(cli)
    ↓
config::load_config  →  ConfigFile (including new [skill] section)
    ↓
apply_config_defaults  →  GlobalOpts
    ↓
┌─────────────────────────────────────────────────────────┐
│  NEW: skill_check::emit_stale_notice_if_any(&config)    │
│    1. Short-circuit if AGENTCHROME_NO_SKILL_CHECK=1     │
│    2. Short-circuit if config.skill.check_enabled       │
│       is Some(false)                                     │
│    3. For each ToolInfo in TOOLS:                        │
│       resolve_path → stat → if exists, read & parse      │
│       version marker (YAML / Version: / HTML comment).   │
│       Failures are swallowed silently.                   │
│    4. If any version < CARGO_PKG_VERSION, collect        │
│       (tool.name, version) pairs.                        │
│    5. If stale list non-empty, print one aggregated      │
│       stderr line (see notice grammar below).            │
│  Never returns an error — staleness never blocks the    │
│  user's actual command.                                  │
└─────────────────────────────────────────────────────────┘
    ↓
match cli.command → command module (unchanged dispatch)
    ↓
Command module formats result
    ↓
Small result:   output::print_output OR emit  → stdout (≤16 KB)
Large result:   output::emit                    → TempFileOutput
Compound:       output::emit_with_snapshot     → {...inline, snapshot: TempFileOutput or inline}
    ↓
Exit with command's exit code
```

---

## API / Interface Changes

### New `output::emit_with_snapshot` helper

This is the only new function on the shared output layer. It is needed because `--include-snapshot` code paths today build a single in-memory struct with interaction-confirmation fields (small) plus a `snapshot` field (potentially large). The existing `emit` helper can only choose "all inline" vs. "whole thing to temp file" — which violates AC5 (interaction fields must remain inline).

**Signature:**

```rust
// In src/output.rs

/// Emit a compound result that carries a small interaction-confirmation
/// payload plus a potentially large `snapshot` field.
///
/// If the serialized form of the whole value fits under the threshold,
/// the full inline JSON is printed (identical to `emit`).
///
/// Otherwise, the `snapshot` field is extracted, serialized, written to
/// a UUID-named temp file, and replaced in the outer object with a
/// `TempFileOutput` whose `summary` is produced by `snapshot_summary_fn`.
/// The interaction-confirmation fields (everything other than `snapshot`)
/// remain inline.
///
/// `command_name` is the full subcommand path (e.g., "interact click").
/// `snapshot_field` is the JSON key on the outer object that refers to
/// the snapshot payload — typically "snapshot".
///
/// # Errors
///
/// Propagates `AppError` from serialization and temp-file writes.
pub fn emit_with_snapshot<T, S, F>(
    value: &T,
    output: &OutputFormat,
    command_name: &str,
    snapshot_field: &'static str,
    snapshot_summary_fn: F,
) -> Result<(), AppError>
where
    T: Serialize,
    F: FnOnce(&serde_json::Value) -> serde_json::Value,
{
    // 1. Serialize `value` to serde_json::Value (not a string)
    // 2. Compute the inline-size of the whole thing; if under threshold,
    //    print as JSON and return (equivalent to emit's small-path)
    // 3. Extract the snapshot field by key; if absent, fall back to emit()
    // 4. Serialize the snapshot alone, write to temp file
    // 5. Build TempFileOutput for the snapshot with summary_fn(&snapshot_value)
    // 6. Replace value[snapshot_field] with the TempFileOutput
    // 7. Print the modified outer object
}
```

**Output shapes (stdout):**

Below threshold — fully inline (unchanged from today):
```json
{
  "success": true,
  "uid": "s12",
  "navigation": { "url": "https://example.com", "committed": true },
  "snapshot": { "total_nodes": 80, "nodes": [...] }
}
```

Above threshold — snapshot offloaded, interaction fields inline:
```json
{
  "success": true,
  "uid": "s12",
  "navigation": { "url": "https://example.com", "committed": true },
  "snapshot": {
    "output_file": "/tmp/agentchrome-<uuid>.json",
    "size_bytes": 182400,
    "command": "interact click",
    "summary": { "total_nodes": 5420, "top_roles": ["main", "navigation"] }
  }
}
```

### Summary-shape helpers (per command)

Each newly gated command needs a `summary_fn` that extracts structural metadata from its result type. These are per-command `fn summary_of_<cmd>(result: &Result) -> serde_json::Value` helpers co-located with the command module — they do not belong in `output.rs` because they embed command-specific shape knowledge.

Minimum shapes (mirrors AC4):

| Command | Module | Summary builder |
|---------|--------|-----------------|
| `audit` | `src/audit.rs` | `{categories: [{id, score}], total_issues, failing_audit_ids}` |
| `dom select` | `src/dom.rs` | `{match_count, first_match: {tag, role, uid}}` |
| `dom get-style` | `src/dom.rs` | `{attribute_count, keys_seen}` (keys are CSS property names; fills the AC3 "full-attribute read" slot) |
| `dom events` | `src/dom.rs` | `{listener_count, event_types}` |
| `page analyze` | `src/page/analyze.rs` | `{iframe_count, overlay_count, framework, has_shadow_dom}` |
| `page find` | `src/page/find.rs` | `{match_count, roles_seen}` |
| `console read` | `src/console.rs` | `{message_count, error_count, warning_count, levels_seen}` |
| `capabilities <command>` | `src/capabilities_cli.rs` | `{subcommand_count, top_level_flags_count}` |
| `--include-snapshot` sites | `src/interact.rs`, `src/form.rs`, `src/navigate.rs` | reuse `page snapshot`'s existing summary shape `{total_nodes, top_roles}` |

Each summary builder treats unmeasurable fields as `serde_json::Value::Null` (per retrospective.md:58 — distinguish "measured as zero" from "could not measure"). Example: `page analyze` emits `framework: null` when no framework is detected, not `framework: "none"` or omitting the key.

### SKILL.md template rewrite

`SKILL_TEMPLATE` in `src/skill.rs` is replaced with:

```
---
name: agentchrome
description: Use agentchrome when you need to automate a browser, fill a form, test a login, scrape a page, take a screenshot, or inspect console / network.
version: "{version}"
---

# agentchrome — Browser Automation CLI

agentchrome gives you browser superpowers via the Chrome DevTools Protocol. It is the right tool whenever the task involves driving a real Chromium instance non-interactively.

## When to Use

Reach for agentchrome when you need to:
- Navigate to URLs, inspect pages, fill forms, click elements
- Take screenshots or capture accessibility trees
- Monitor console output or network requests
- Automate browser workflows (testing, scraping, verification, auditing)

## How to Discover Commands

agentchrome is self-documenting. Start here before guessing:

- `agentchrome --help` — overview of all commands
- `agentchrome <command> --help` — detailed help for any command
- `agentchrome capabilities` — machine-readable JSON manifest of all commands
- `agentchrome capabilities <command>` — detail for one command (large; may return a temp-file object — see below)
- `agentchrome examples` — practical usage examples for every command
- `agentchrome examples strategies` — scenario-based guides (iframes, shadow DOM, SPA waits, ...)
- `agentchrome examples strategies <name>` — the full guide for one scenario
- `agentchrome man <command>` — full man page for any command

## Before You Automate

- `agentchrome diagnose <url>` — scan a page for iframes, dialogs, overlays, and framework quirks *before* trying to automate it.
- `agentchrome diagnose --current` — run the same scan against whatever tab is already attached.

If `diagnose` flags an iframe, SPA, or shadow DOM, run `agentchrome examples strategies <topic>` for the matching playbook.

## After You Act

Interaction commands (`interact click`, `interact hover`, `form fill`, `form fill-many`, `navigate`, ...) accept `--include-snapshot`. Pass it to get the post-action accessibility snapshot back in the same invocation — one round trip instead of two.

## Large Responses

Any response larger than ~16 KB returns a `{output_file, size_bytes, command, summary}` object on stdout and writes the full payload to a temp file. Read the `summary` first; only open the file if the summary does not answer your question. Streaming commands (`network follow`, `console follow`) are exempt — they stream directly.

For compound results (interaction + `--include-snapshot` above the threshold), the interaction confirmation stays inline and only the `snapshot` field is offloaded to a file.

## Quick Start

```sh
agentchrome connect --launch --headless
agentchrome navigate <url>
agentchrome diagnose --current
agentchrome page snapshot
```
```

**`AppendSection`-mode variant** (Windsurf, Copilot-JB): the section is wrapped in the existing `<!-- agentchrome:start --> ... <!-- agentchrome:end -->` markers, and the version marker is embedded as an HTML comment *inside* the markers:

```
<!-- agentchrome:start -->
<!-- agentchrome-version: 1.42.0 -->

# agentchrome — Browser Automation CLI
...
<!-- agentchrome:end -->
```

The host tool ignores HTML comments; our staleness check parses them.

### Staleness notice grammar (stderr)

```
single-tool stale:
    note: installed agentchrome skill for <tool> is v<ver> but binary is v<binary_ver> — run 'agentchrome skill update' to refresh

multi-tool stale:
    note: installed agentchrome skills for <tool1>, <tool2> are stale (oldest v<oldest_ver>, binary v<binary_ver>) — run 'agentchrome skill update' to refresh
```

The line is always terminated by a single `\n`. It is written before *any* other stderr output from the command, so agents parsing stderr line-by-line can recognize it as a prefix and decide to filter.

### New config key

`ConfigFile` grows a new section:

```toml
# In src/config.rs
[skill]
check_enabled = true   # default — suppresses the staleness notice when set to false
```

Added via a new `#[derive(Debug, Default, Clone, Deserialize, Serialize)] struct SkillConfig { check_enabled: Option<bool> }` field on `ConfigFile`. `Option<bool>` keeps the default-unset path backward-compatible.

### CLI surface additions

None. The staleness check is implicit. The config key is read, not surfaced as a flag. The SKILL.md template change is data-only.

(The only clap-facing effect is that existing `skill install`/`skill update` continue to work — no new subcommands, no new flags.)

---

## Database / Storage Changes

None. No persistent state added; the staleness check reads existing on-disk skill files (managed by the existing `install_skill`/`update_skill` code paths) and compares against the compile-time `CARGO_PKG_VERSION`.

---

## State Management

### Per-invocation state (staleness check)

Transient, stack-local, never cached to disk. Reference `steering/structure.md` — this project's "state management" is limited to session persistence and config; no global state.

```rust
// Conceptual, in src/skill_check.rs

struct StaleTool {
    name: &'static str,
    installed_version: Version,
    binary_version: Version,
}

fn stale_tools(tools: &[ToolInfo]) -> Vec<StaleTool> {
    tools
        .iter()
        .filter_map(|tool| check_one(tool).ok().flatten())
        .filter(|st| st.installed_version < st.binary_version)
        .collect()
}
```

### State transitions

```
Invocation start
    │
    ├─▶ env AGENTCHROME_NO_SKILL_CHECK=1?  ──YES──▶ Skip (no stderr)
    │
    ├─▶ config.skill.check_enabled = false? ──YES──▶ Skip (no stderr)
    │
    ▼
For each tool in TOOLS registry:
    │
    ├─▶ Install path stat fails?  ──YES──▶ Skip this tool (silent)
    │
    ├─▶ Version marker unparseable? ──YES──▶ Skip this tool (silent)
    │
    ▼
Compare installed_version < CARGO_PKG_VERSION
    │
    ├─▶ Equal/newer                ──▶ Tool is fresh, skip
    │
    └─▶ Older                      ──▶ Append to stale list

If stale list non-empty:
    Format aggregated notice → stderr → \n
```

**Invariant**: the check never surfaces an error to the caller. All failure modes (bad path resolution, unreadable file, malformed marker) are silently swallowed so the user's actual command always runs.

---

## UI Components

Not applicable — CLI tool. The only user-visible additions are:

1. Richer content in the installed SKILL.md file (for AI-agent consumption)
2. A conditional single-line stderr notice (for users whose skill has gone stale)

Both are documented in the Output shapes sections above.

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: One PR per gap** | Split into three issues (SKILL.md / emit extension / staleness check) | Smaller PRs, independent review | Intermediate states lie to users — e.g., SKILL.md says "large responses return a temp-file object" while `audit` still spills full JSON | **Rejected** — the issue explicitly calls this out: "Treat this as a single bundled issue rather than splitting per gap — the gaps are interdependent." |
| **B: Single PR (all three gaps)** | Bundle into one spec, one branch, one PR | Skill + response layer stay in sync, reviewers see the full hardening story at once | Larger diff | **Selected** |
| **C: Auto-run `skill update` on staleness** | Binary silently re-writes the installed skill when it detects drift | No user action required | Changes user-level files without consent; breaks the "skill is user-managed" trust boundary; surprising to users who intentionally edit their skill | **Rejected** — notice points at `skill update`; command remains user-initiated |
| **D: Cache staleness decision for session** | Remember "already warned" in a lock file or env var | Cheaper per-invocation | Cross-session agents (Claude Code spawns fresh processes) would never see a warning once any warning was shown; also violates retrospective.md:24 (state must persist/visibility across invocations) | **Rejected** — each invocation checks independently |
| **E: Use `semver` crate for comparison** | Parse via the `semver` crate for full semver ordering | Correct for pre-release / build-metadata cases | Adds a dependency; `CARGO_PKG_VERSION` is always a plain `X.Y.Z` in this project | **Rejected for now** — tuple comparison on three `u32`s is sufficient; revisit if we ever cut pre-release versions |
| **F: HTML comment marker for all tools** | Use `<!-- agentchrome-version -->` everywhere, not YAML frontmatter | One code path for all tools | YAML frontmatter is the right *native* discovery signal for Claude Code / Cursor / Gemini / Continue — they parse it for name/description matching | **Rejected** — YAML for Standalone, HTML comment inside markers for AppendSection (dual format; parser reads both) |
| **G: Fail-closed on skill-check error** | If version parsing fails, warn the user about the skill being corrupt | Surfaces install problems | Noisy on any partial write; risks user running `skill update` for no real reason | **Rejected** — fail-open (silent skip) is the safer default for a non-essential check |

---

## Security Considerations

- [x] **Authentication**: N/A — local CLI tool, no remote trust boundary added.
- [x] **Authorization**: N/A — user's own files only.
- [x] **Input Validation**: Skill marker parsing rejects malformed semver (treated as "missing marker" → silent skip). No unsanitized filename interpolation in the stderr notice (tool names come from the compile-time `TOOLS` registry, not user input).
- [x] **Data Sanitization**: Version strings are constrained to `X.Y.Z` ASCII digits + dots before being embedded in stderr output. Any other shape is rejected at parse time.
- [x] **Sensitive Data**: None. Staleness notice contains only the tool name and two semver strings — both non-sensitive.
- [x] **Env var parse**: `AGENTCHROME_NO_SKILL_CHECK` is checked for exact string `"1"` only (not `"true"`, `"yes"`, etc.) for consistency with other agentchrome env vars.

---

## Performance Considerations

- [x] **Startup budget**: Staleness check is on the hot path (every invocation). Budget: < 1 ms average. Implementation strategy:
  - Seven `stat()` calls (one per tool) worst case, each ~10 μs on warm FS = ~70 μs baseline.
  - For existing files, read only the first ~20 lines (small, fits in one page cache line) to find the version marker, not the full file.
  - Early-exit on `AGENTCHROME_NO_SKILL_CHECK=1` before touching the filesystem at all (fast path for automation loops).
  - No sorting, no allocation beyond the stale list.
- [x] **Temp-file writes**: No new overhead for below-threshold responses (AC9). For above-threshold responses, the cost is dominated by the JSON serialization that was already happening plus one additional disk write. No change to the existing `write_temp_file` helper's complexity.
- [x] **Compound schema**: `emit_with_snapshot` serializes the outer value once to a `serde_json::Value` (not a string), does a size check via re-serialization of the whole tree, and only if above threshold does a second serialization of the extracted snapshot. This is one extra allocation in the large-response path; acceptable.
- [x] **Memory**: No new long-lived allocations. Stale-list capacity bounded at 7 (TOOLS.len()).

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| `output::emit_with_snapshot` | Unit (in `src/output.rs`) | Below/above threshold paths; snapshot-field-missing fallback to `emit` |
| Per-command summary builders | Unit (inline `#[cfg(test)] mod tests`) | One test per summary, asserting shape + null-safety |
| SKILL.md rendering | Unit | Installed content starts with YAML frontmatter; names all three paths + temp-file pattern |
| `AppendSection` version marker | Unit | Written content contains `<!-- agentchrome-version: X.Y.Z -->` inside section markers |
| `skill_check::read_version_marker` | Unit | Parses YAML `version:` (quoted + unquoted); parses legacy `Version: X.Y.Z`; parses HTML comment form; returns `None` on garbage |
| `skill_check::stale_tools` | Unit | Single-stale, multi-stale, all-fresh, mixed-with-missing-files |
| Staleness notice formatting | Unit | Single-tool grammar; multi-tool aggregated grammar; no trailing whitespace |
| Feature end-to-end (BDD) | Integration (cucumber-rs, `tests/features/skill-staleness.feature`) | AC6, AC7, AC8, AC10 |
| Large-response extension (BDD) | Integration (`tests/features/large-response-detection.feature`) | One scenario per newly gated command + compound-schema scenario |
| Smoke test against real Chrome | Manual verification (`/verify-code`) | Each AC3 command with a pathological fixture producing >16 KB; compound `--include-snapshot` on a large page |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Staleness check adds startup latency on cold FS | Low | Medium | Short-circuit on `AGENTCHROME_NO_SKILL_CHECK=1`; stat-only per tool; <1 ms budget enforced in benchmark (see Success Metrics) |
| `AppendSection` host tool (Windsurf / Copilot-JB) strips HTML comments and we can never read the version marker back | Medium | Medium | Confirm during smoke-test: manually install via `skill install --tool windsurf`, read back the file, confirm the comment survived. If the host strips it, fall back to a plain-text `Version: X.Y.Z` line inside the markers (the host renders it but doesn't execute it — harmless). |
| Parsing version markers on malformed user-edited files yields false-positive stale notices | Low | Low | Fail-open: any parse failure is silently skipped (see `skill_check` state transitions) |
| Compound schema breaks agents that parse `--include-snapshot` output positionally | Low | High | Agents documented (in SKILL.md rewrite) to read the `snapshot` key and check whether it is a `TempFileOutput` vs. inline snapshot. BDD scenarios assert both shapes. |
| #218 lands late and FR7 (`capabilities <command>` gating) cannot ship with the rest | Medium | Low | FR7 is **Should**, not Must. If #218 is unmerged at branch-cut, drop FR7 to a follow-up amendment; the rest of the feature ships independently. |
| `skill update` idempotency regression (rewrite corrupts frontmatter) | Low | Medium | AC8 has a dedicated test that asserts `action: "updated"` and parses the rewritten frontmatter successfully |
| Retrospective.md:24 (cross-invocation state) violated by accidentally caching staleness state | Low | Medium | AC10 explicitly tests that two successive invocations both run the check independently |

---

## Rollout

Single bundled PR per the issue's own directive: "Treat this as a single bundled issue rather than splitting per gap." One branch, one PR, one version bump. No child issues required.

---

## Open Questions

- [ ] Does Windsurf's memory-file renderer preserve HTML comments when the file is loaded into the agent context? (Answered during smoke-test; fallback in Risks table.)
- [ ] Is `capabilities <command>`'s detail path guaranteed to be an object serializable by `emit` (not a pre-formatted string)? — Confirm when #218's design lands. If it returns plain text, use `emit_plain` instead.
- [ ] Should the staleness notice include the install path for the stale tool so the user can find the file? — Decision: no for now. The notice already tells them to run `skill update`; adding paths makes the line long and leaks home-directory structure.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #220 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

Before moving to TASKS phase:

- [x] Architecture follows existing project patterns (per `structure.md`) — staleness check lives in its own module; output layer grows one helper; no cross-layer leakage
- [x] All API/interface changes documented with schemas — compound output shape, staleness grammar, new `emit_with_snapshot` signature, config key
- [x] Database/storage changes planned — none needed; documented as such
- [x] State management approach is clear — stack-local per invocation, no cache
- [x] UI components and hierarchy defined — N/A for CLI
- [x] Security considerations addressed — input validation, env var parse strictness, no new sensitive data
- [x] Performance impact analyzed — < 1 ms staleness budget with concrete strategy
- [x] Testing strategy defined — per-layer coverage table
- [x] Alternatives were considered and documented — seven alternatives, each with decision rationale
- [x] Risks identified with mitigations — seven risks with mitigations
- [x] Retrospective.md patterns applied: cross-invocation state (AC10), optional-field provenance (null-safe summaries), path audit (enumerated every AC3 candidate)
