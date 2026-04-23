# Requirements: Harden Progressive Disclosure — Enrich SKILL.md, Extend Temp-File Gating, Notify on Stale Skill

**Issues**: #220
**Date**: 2026-04-22
**Status**: Draft
**Author**: Claude (AI-assisted)

---

## User Story

**As an** AI agent (or the human running one) using agentchrome
**I want** the installed skill to advertise every discovery path, every large command response to stay under my context budget, and to be notified when my installed skill drifts behind the binary
**So that** I can discover capabilities, exercise them safely, and act on structured summaries without wasting tokens or operating against stale guidance

---

## Background

agentchrome uses two layers of progressive disclosure:

1. **Documentation layer** — installed `SKILL.md` → `capabilities` manifest → `examples` → `examples strategies` → `man` → `diagnose` runtime bridge.
2. **Response layer** — outputs exceeding `DEFAULT_THRESHOLD` (16 KB, `src/output.rs:18`) are written to a temp file via `output::emit`, and stdout carries a `{output_file, size_bytes, command, summary}` object instead (`src/output.rs:330-375`).

A gap analysis against v1.42.0 found holes in both layers. The installed SKILL.md template (`src/skill.rs:119-151`) names only the generic CLI verbs (`--help`, `capabilities`, `examples`, `man`) and never mentions `diagnose`, `examples strategies`, `--include-snapshot`, or the temp-file response pattern. On the response side, only five command paths gate through `output::emit` today (`page snapshot`, `page text`, `js exec`, `network list`, `network get`) while several others (`audit`, `dom` subcommands, `page analyze`, `page find`, `console read`, every `--include-snapshot` site) can realistically produce >16 KB output and spill unbounded JSON onto stdout. A third gap is that an installed skill never tells the user it has gone stale relative to the binary, so advice drifts silently as the tool evolves.

Closing these three gaps together is what makes "agent discovers a capability → exercises it safely → acts on the result" trustable end-to-end. The gaps are interdependent: advertising features the response layer hasn't rolled out misleads agents; expanding response-layer coverage the skill never mentions wastes the hardening. This feature treats them as a single bundled delivery rather than splitting per gap.

### Related open work

- **#218** (Retrofit examples and capabilities listings to comply with Progressive Disclosure steering rule) shrinks the `examples --json` and `capabilities --json` *listing* payloads to <4 KB and introduces a `capabilities <command>` detail path. That is the orthogonal *listing-shape* axis (tech.md:167-203); this issue is the *response-size* axis. They are interdependent on the `capabilities` / `examples` command surface — see Dependencies below.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: SKILL.md Template Has YAML Frontmatter With Rich Trigger Phrases

**Given** the SKILL.md template in `src/skill.rs`
**When** `agentchrome skill install --tool claude-code` writes the skill
**Then** the installed file begins with a YAML frontmatter block containing `name`, `description`, and `version` keys
**And** the `description` value names the trigger phrases: `"automate a browser"`, `"fill a form"`, `"test a login"`, `"scrape a page"`, `"take a screenshot"`, `"inspect console / network"`
**And** `agentchrome skill install --tool cursor` writes a `.mdc` file whose frontmatter is compatible with Cursor's rules format
**And** subsequent `skill install` / `skill update` runs preserve the frontmatter shape (no duplicate or drifted blocks)

**Example** (claude-code install):
- Given: no skill is installed at `~/.claude/skills/agentchrome/SKILL.md`
- When: `agentchrome skill install --tool claude-code` runs
- Then: the file starts with `---\nname: agentchrome\ndescription: Use agentchrome when you need to automate a browser, fill a form, test a login, scrape a page, take a screenshot, or inspect console / network.\nversion: {CARGO_PKG_VERSION}\n---\n`

### AC2: SKILL.md Names the Uniquely High-Leverage Discovery Paths

**Given** the SKILL.md template
**When** the template is rendered by `skill install` or `skill update`
**Then** the body explicitly names `agentchrome diagnose <url>` and `agentchrome diagnose --current` for pre-automation page scans
**And** names `agentchrome examples strategies [name]` for scenario-based guides
**And** names `--include-snapshot` as a round-trip saver on interaction commands
**And** explains in one sentence that responses larger than ~16 KB return a `{output_file, size_bytes, command, summary}` object — with the guidance "read the file only if the summary doesn't answer your question"

### AC3: `output::emit` Wired Into Remaining Large-Response Commands

**Given** the list of command paths that can realistically produce >16 KB output today
**When** any of the following commands produces output exceeding the effective threshold, it emits a `TempFileOutput` object with a command-appropriate `summary`:
- `audit` (Lighthouse full report)
- `dom select`
- `dom get-style` (the all-styles read path — the full-attribute-map analog; see Design note)
- `dom events` (DOM event-listener introspection)
- `page analyze`
- `page find`
- `console read`
- Every code path that appends a snapshot via `--include-snapshot` (`interact click`, `interact hover`, `form fill`, `form fill-many`, `navigate`, plus any sibling interact/form subcommand that currently exposes the flag)
- `capabilities <command>` (the detail path introduced by #218; the listing is out of scope here because #218 caps it at <4 KB)

**And** streaming commands (`network follow`, `console follow`) remain exempt and that exemption is documented in the requirements

### AC4: Each Newly Gated Command Defines a Domain-Appropriate `summary`

**Given** a gated command from AC3 that triggers temp-file output
**When** the `TempFileOutput.summary` field is serialized
**Then** it contains structural metadata the agent can act on, not just byte counts. Minimum shapes:

| Command | Summary shape |
|---------|---------------|
| `audit` | `{categories: [{id, score}], total_issues, failing_audit_ids}` |
| `dom select` | `{match_count, first_match: {tag, role, uid}}` |
| `dom get-style` | `{attribute_count, keys_seen}` (keys are CSS property names) |
| `dom events` | `{listener_count, event_types}` |
| `page analyze` | `{iframe_count, overlay_count, framework, has_shadow_dom}` |
| `page find` | `{match_count, roles_seen}` |
| `console read` | `{message_count, error_count, warning_count, levels_seen}` |
| `capabilities <command>` | `{subcommand_count, top_level_flags_count}` |
| `--include-snapshot` paths | see AC5 (compound schema) |

**And** when a field cannot be determined (e.g., `framework` when no framework is detected), the field appears as `null` per the retrospective learning on optional-field provenance (retrospective.md:58)

### AC5: Compound `--include-snapshot` Results Preserve Interaction Confirmation

**Given** a command like `interact click <uid> --include-snapshot` where the interaction result is small (<1 KB) but the snapshot payload exceeds the threshold
**When** the command is executed
**Then** the stdout object preserves the interaction confirmation fields inline (e.g., `success`, target `uid`, `navigation` info) so the agent can act on the outcome without reading the temp file
**And** the large snapshot portion is the part written to a temp file, referenced as `snapshot_file`
**And** the compound object shape is:

```json
{
  "success": true,
  "uid": "s12",
  "navigation": { "url": "...", "committed": true },
  "snapshot": {
    "output_file": "/tmp/agentchrome-<uuid>.json",
    "size_bytes": 182400,
    "command": "interact click",
    "summary": { "total_nodes": 5420, "top_roles": ["main", "navigation"] }
  }
}
```

**And** the compound schema is documented in `design.md` as an **approved extension** to AC21 of the original large-response spec — the inner `snapshot` object uses the existing `{output_file, size_bytes, command, summary}` shape unchanged, and the interaction-confirmation fields are additive top-level keys on the outer object

**And** when the combined payload fits under the threshold, no temp file is written and stdout carries the fully inline object (the snapshot appears as its normal in-memory representation, not wrapped in a `snapshot` key referencing a file)

### AC6: Skill-Staleness Notice on Binary Invocation

**Given** an installed skill file whose embedded version marker is less than `CARGO_PKG_VERSION`
**When** any `agentchrome` command is invoked
**Then** exactly one line is written to stderr, before any other stderr output from the command, in the form:

```
note: installed agentchrome skill is vX.Y.Z but binary is vA.B.C — run 'agentchrome skill update' to refresh
```

**And** the check adds < 1 ms of startup overhead (single file stat + one line read per known install location)
**And** the notice is suppressible via the env var `AGENTCHROME_NO_SKILL_CHECK=1`
**And** the notice is suppressible via the config key `skill_check_enabled = false`
**And** the notice never fires when no skill is installed, when versions match, or when suppression is active

### AC7: Skill-Staleness Check Detects Multi-Tool Installs

**Given** skills installed for multiple tools (e.g., `claude-code`, `cursor`, `gemini`)
**When** the staleness check runs
**Then** each of the seven known install locations from the `TOOLS` registry (`src/skill.rs:62-113`) is checked at most once per invocation
**And** at most one staleness notice is emitted per invocation
**And** if exactly one tool's skill is stale, the notice names that tool: `note: installed agentchrome skill for <tool> is vX.Y.Z but binary is vA.B.C — …`
**And** if multiple tools are stale, the notice aggregates them: `note: installed agentchrome skills for <tool1>, <tool2> are stale (oldest vX.Y.Z, binary vA.B.C) — …`

### AC8: `skill update` Remains Idempotent

**Given** an installed skill whose version already matches the binary
**When** the user runs `agentchrome skill update`
**Then** the command exits 0 with `action: "updated"` in the output object
**And** the file content is rewritten (no stat-diff required — rewriting is cheap and catches partial-write recovery)
**And** subsequent staleness checks against the same file do not fire

### AC9: Existing Behavior Is Preserved for Below-Threshold Responses

**Given** any gated command (existing five + newly added in AC3) producing output under the effective threshold
**When** the command is executed
**Then** stdout is the full inline JSON response, unchanged from pre-feature behavior
**And** no temp file is written
**And** the exit code matches the pre-feature behavior for that command's success and error paths

### AC10: Cross-Invocation Consistency of the Staleness Check

**Given** the staleness check runs on every `agentchrome` invocation
**When** two successive invocations are run in the same shell session (e.g., `agentchrome tabs list` then `agentchrome navigate <url>`)
**Then** each invocation runs the check independently (there is no cached "already warned this session" state that would hide a stale skill across sessions)
**And** the check is environment-variable-suppressible at a per-invocation granularity so an agent running `AGENTCHROME_NO_SKILL_CHECK=1 agentchrome ...` sees no notice even if stale
**And** the check runs regardless of the command being a streaming command (`network follow`, `console follow`) — the notice fires at invocation start, before any streaming begins

### AC11: BDD Coverage

**Given** the feature is implemented
**When** `cargo test --test bdd` is run
**Then** a new feature file `tests/features/skill-staleness.feature` covers AC6, AC7, AC8, and AC10
**And** `tests/features/large-response-detection.feature` (or an equivalent dedicated file) is extended with scenarios for each command path added in AC3
**And** at least one scenario asserts the SKILL.md YAML frontmatter shape (AC1) and body content (AC2)
**And** at least one scenario asserts the compound `--include-snapshot` schema (AC5), covering both the above-threshold (temp file) and below-threshold (fully inline) branches
**And** at least one scenario asserts that a `bug`-labelled smoke test for streaming commands still emits the staleness notice while streaming proceeds unchanged

### Generated Gherkin Preview

```gherkin
Feature: Harden progressive disclosure (skill enrichment, temp-file gating, staleness)
  As an AI agent using agentchrome
  I want the skill to advertise every path, large responses to stay in budget, and to be notified when my skill is stale
  So that I can discover, exercise, and act on capabilities without wasting tokens or running against stale guidance

  Scenario: SKILL.md frontmatter shape on claude-code install
    Given no skill is installed for claude-code
    When I run "agentchrome skill install --tool claude-code"
    Then the installed SKILL.md begins with a YAML frontmatter block
    And the frontmatter contains name, description, version
    And the description names the six trigger phrases

  Scenario: SKILL.md names the high-leverage discovery paths
    Given the SKILL.md template is rendered
    Then the body names "agentchrome diagnose <url>", "examples strategies", "--include-snapshot", and the temp-file response pattern

  Scenario Outline: Newly gated commands emit TempFileOutput above threshold
    Given a page that will produce more than 16 KB of output for <command>
    When I run "agentchrome <command>"
    Then stdout is a TempFileOutput object
    And the summary matches the shape for <command>

    Examples:
      | command                       |
      | audit                         |
      | dom select ...                |
      | page analyze                  |
      | page find --role button       |
      | console read                  |
      | capabilities navigate         |

  Scenario: Compound include-snapshot preserves interaction fields
    Given a clickable element exists on a page producing a large snapshot
    When I run "agentchrome interact click <uid> --include-snapshot"
    Then stdout contains success, uid, navigation top-level fields
    And the snapshot payload is offloaded to a file under a "snapshot" key

  Scenario: Stale skill emits a single note line on stderr
    Given an installed skill with version 1.40.0 and a binary of version 1.42.0
    When I run any agentchrome command
    Then stderr contains exactly one line "note: installed agentchrome skill ... is v1.40.0 but binary is v1.42.0 ..."

  Scenario: Staleness notice is suppressed by env var
    Given an installed skill with a stale version
    When I run "AGENTCHROME_NO_SKILL_CHECK=1 agentchrome tabs list"
    Then no staleness note appears on stderr

  Scenario: skill update is idempotent when versions match
    Given an installed skill whose version already matches the binary
    When I run "agentchrome skill update"
    Then exit code is 0
    And the output has action "updated"
```

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | SKILL.md template grows a YAML frontmatter block with `name`, `description`, `version` | Must | `description` must embed the six trigger phrases from AC1 |
| FR2 | SKILL.md body names `diagnose`, `examples strategies`, `--include-snapshot`, and the temp-file response pattern | Must | One sentence per path minimum; keep the template compact |
| FR3 | `output::emit` gating added to `audit` | Must | Summary: `{categories, total_issues, failing_audit_ids}` |
| FR4 | `output::emit` gating added to `dom select`, `dom get-style`, `dom events` | Must | See AC4 for each summary shape. `dom get-style` fills the AC3 "full-attribute read" slot — there is no `dom attributes` verb; `dom get-attribute` only reads a single named attribute, so the styles-map path is the closest structural match. |
| FR5 | `output::emit` gating added to `page analyze`, `page find`, `console read` | Must | See AC4 for each summary shape |
| FR6 | `output::emit` gating added to every `--include-snapshot` code path | Must | Covers `interact click/hover/...`, `form fill/fill-many/submit`, `navigate` |
| FR7 | `capabilities <command>` detail path (introduced by #218) is gated by `output::emit` | Should | Can land in the same PR as #218 merge or immediately after |
| FR8 | Each gated command defines a domain-appropriate `summary` shape (see AC4 table) | Must | Null-safe per retrospective.md:58 — unmeasurable fields serialize as `null`, not omitted |
| FR9 | Compound `--include-snapshot` results keep interaction fields inline while offloading the snapshot payload under a `snapshot` key | Must | Documented as an approved extension to AC21 of the original large-response spec |
| FR10 | Skill-staleness check runs on every invocation with < 1 ms overhead, emits a single stderr line, is suppressible | Must | Check happens at binary entry, before any other stderr output |
| FR11 | Staleness check iterates the seven-tool registry (`claude-code`, `windsurf`, `aider`, `continue`, `copilot-jb`, `cursor`, `gemini`) and aggregates stale tools into a single notice | Must | One line per invocation, regardless of count |
| FR12 | `AGENTCHROME_NO_SKILL_CHECK=1` env var suppresses the staleness notice | Must | Env-level suppression is the cheapest for automation loops |
| FR13 | Config key `skill_check_enabled = false` suppresses the staleness notice | Should | Persistent preference for interactive users |
| FR14 | `skill update` remains idempotent when versions already match (exit 0, `action: "updated"`, file rewritten) | Must | Rewrite always — catches partial-write recovery |
| FR15 | Streaming commands (`network follow`, `console follow`) documented as exempt from temp-file gating; staleness notice still fires before streaming begins | Must | Exemption must appear in this spec, in `tech.md`'s Progressive Disclosure section, and in the SKILL.md template's one-sentence explanation |
| FR16 | BDD coverage for all new ACs, including compound-schema and staleness scenarios | Must | New `tests/features/skill-staleness.feature`; extend existing `large-response-detection.feature` |
| FR17 | When no skill is installed for a given tool, the staleness check emits nothing for that tool (silent) | Must | Installed absent != stale |
| FR18 | `skill install` and `skill update` record the binary version in the written file in a machine-parseable form (`version: X.Y.Z` in YAML frontmatter for `.md`/`.mdc` targets; the `<!-- agentchrome:start -->`-wrapped section for `AppendSection` targets carries the same `version:` line inside the wrapper) | Must | This is the data the staleness check reads |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Staleness check adds < 1 ms to startup (target: single `stat` + first-line read per install location; lazy-stop on first stale match when possible; still overall bounded by seven `stat` calls in worst case). Temp-file writes add no new overhead for below-threshold responses. |
| **Security** | No telemetry added. Env var / config suppression must not be bypassable without source change. No secrets logged in the staleness notice. |
| **Reliability** | Staleness check never aborts a command if it fails — any parse/stat failure is silently ignored so the user's actual invocation always completes. `skill update` must be safe to run repeatedly (idempotent per AC8). |
| **Accessibility** | N/A — non-interactive CLI output. Notice is structured text suitable for screen readers by default. |
| **Platforms** | macOS, Linux, Windows — path resolution uses existing `resolve_path` / `dirs::home_dir` helpers in `src/skill.rs`. |

---

## Data Requirements

### Input Data (staleness check)

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| Installed skill file path | PathBuf | Resolved via existing `resolve_path` helper | Yes |
| Installed skill version marker | `x.y.z` semver string (from YAML `version:` or legacy `Version: X.Y.Z` line) | semver parse; failure = silent skip | Yes |
| Binary version | `CARGO_PKG_VERSION` compile-time constant | baked in | Yes |
| `AGENTCHROME_NO_SKILL_CHECK` env var | `"1"` suppresses | any other value or absence = enabled | No |
| `skill_check_enabled` config key | bool | TOML parse via existing `src/config.rs` | No |

### Output Data (new / modified)

| Field | Type | Description |
|-------|------|-------------|
| `TempFileOutput.summary` (per newly gated command) | object | Command-specific shape per AC4 |
| Compound `--include-snapshot` stdout object | object | `{success, uid, navigation, snapshot: {output_file, size_bytes, command, summary}}` when snapshot is offloaded; fully inline when under threshold |
| Staleness notice (stderr) | UTF-8 text line | `note: installed agentchrome skill[s] [for <tool>[,<tool>]] is/are v<ver>[,v<ver>] but binary is v<binary_ver> — run 'agentchrome skill update' to refresh\n` |
| SKILL.md YAML frontmatter | YAML block | `name`, `description`, `version` keys |

---

## Dependencies

### Internal Dependencies
- [x] `output::emit` / `output::emit_plain` helpers (`src/output.rs`) — reused as-is
- [x] `TempFileOutput` struct and AC21 schema from the large-response feature — used as-is for newly gated commands, extended compound-wise for `--include-snapshot`
- [x] `skill` command group and seven-tool registry (`src/skill.rs`) — extended with a staleness-check module

### External Dependencies
- None — all changes are internal. No new crates required (semver parsing can use a simple tuple-compare since the version marker is always `X.Y.Z` from `CARGO_PKG_VERSION`; adding the `semver` crate is optional and only for future-proofing).

### Blocked By
- [ ] **#218** — The `capabilities <command>` detail path (FR7) must exist before it can be gated. FR3–FR6 and FR10–FR14 are independent of #218 and can land first. If this feature ships ahead of #218, FR7 is deferred to a follow-up amendment.

---

## Out of Scope

- Automatic skill auto-update (the notice points at `agentchrome skill update`; the command remains user-initiated).
- Changing the 16 KB `DEFAULT_THRESHOLD` value — threshold tuning is a separate concern.
- Adding new strategy guides or examples — scope is advertising the existing ones, not authoring new content.
- Regenerating `examples/CLAUDE.md.example` — it is manual-install documentation, not the installed skill.
- Retrofitting `examples --json` or `capabilities --json` *listings* — covered by #218 on the listing-shape axis.
- `page screenshot` output (uses `--file`, not stdout) and `perf record` trace files (already file-based).
- Rebuilding the existing per-command truncation (`MAX_NODES`, `MAX_INLINE_BODY_SIZE`) — they remain as a second layer per the original large-response spec's FR14.
- Future follow-up: temp-file gating for `tabs list` / `cookie list` / `media list` / `page frames` on pages with pathological item counts. Those commands comply with listing shape today; revisit only if a real site is observed blowing past 16 KB on them.

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Gated commands producing >16 KB stdout JSON | 0 (excluding streaming-exempt) | Integration smoke: run each AC3 command against a pathological fixture; assert stdout is a `TempFileOutput` object |
| Stale skill notice detection lag | 0 invocations | After `cargo install` of a newer binary, the next `agentchrome` invocation must warn |
| Startup overhead delta | < 1 ms average | Bench `agentchrome --version` cold with vs. without seven-tool-stale setup |
| Agent-facing context spend on 1 MB snapshot | ≤ 1 KB of stdout bytes | Assert summary size on representative fixture |

---

## Open Questions

- [x] Where is the staleness-check module bolted in? — Answer (see design): in `main.rs` before command dispatch, as a best-effort `fn emit_skill_staleness_if_any()` that silently ignores errors.
- [x] Should the `version` key in YAML frontmatter be quoted? — Answer: yes, as a string (`version: "1.42.0"`) for Cursor's `.mdc` parser compatibility; the check parses both `1.42.0` and `"1.42.0"`.
- [ ] `AppendSection`-mode tools (Windsurf, Copilot-JB) wrap content in `<!-- agentchrome:start --> ... <!-- agentchrome:end -->`. Does the frontmatter need to appear *inside* the markers (ignored by host but parseable by our check), or as a plain `Version:` line? — Design decision: embed a `<!-- agentchrome-version: X.Y.Z -->` HTML comment inside the section markers so the wrapping host tools ignore it while our check still finds it. Confirm this is acceptable with the Windsurf/Copilot-JB workflows during implementation smoke-test.
- [ ] Should the staleness check honor a `--quiet` global flag (if/when one is added)? Currently no such flag exists; punt until it does.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #220 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

Before moving to PLAN phase:

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements (design.md covers those)
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified (below-threshold, no-skill-installed, suppressed)
- [x] Dependencies are identified (#218, internal `output::emit`, `skill` registry)
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
- [x] Cross-invocation persistence covered per retrospective.md:24 (AC10)
- [x] Optional-field provenance covered per retrospective.md:58 (AC4 null-safety)
- [x] Path audit covered per retrospective.md:60 (AC3 enumerates every current emit candidate)
