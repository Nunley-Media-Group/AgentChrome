# Tasks: Harden Progressive Disclosure — Enrich SKILL.md, Extend Temp-File Gating, Notify on Stale Skill

**Issues**: #220
**Date**: 2026-04-22
**Status**: Planning
**Author**: Claude (AI-assisted)

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Setup | 2 | [ ] |
| Backend (output layer + skill template) | 4 | [ ] |
| Backend (command-site gating) | 7 | [ ] |
| Backend (staleness check + config) | 3 | [ ] |
| Integration | 2 | [ ] |
| Testing | 5 | [ ] |
| **Total** | **23 tasks** | |

---

## Task Format

Each task:

```
### T[NNN]: [Task Title]
**File(s)**: `path/to/file`
**Type**: Create | Modify
**Depends**: T[NNN], ... (or None)
**Acceptance**:
- [ ] [Verifiable criterion]
**Notes**: [Optional implementation hints]
```

File paths follow `steering/structure.md` — `src/*.rs` for command modules, `src/page/*.rs` for page subcommands, `tests/features/*.feature` for Gherkin, `tests/bdd.rs` for step definitions.

---

## Phase 1: Setup

### T001: Add `[skill]` section to config schema

**File(s)**: `src/config.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `ConfigFile` grows a `pub skill: SkillConfigFile` field
- [ ] New `SkillConfigFile` struct has `pub check_enabled: Option<bool>`, derives `Debug, Default, Clone, Deserialize, Serialize`, uses `#[serde(default)]`
- [ ] A TOML file with `[skill]\ncheck_enabled = false` round-trips through the config loader and the resulting `ConfigFile::skill::check_enabled == Some(false)`
- [ ] Absent `[skill]` section → `config.skill.check_enabled == None` (backward compatible)

**Notes**: Mirror the existing pattern of `OutputConfig` / `KeepaliveConfigFile`. No changes to `ResolvedConfig` because the skill check reads `ConfigFile` directly, not the resolved form.

### T002: Add fixture HTML pages for large-response smoke tests

**File(s)**: `tests/fixtures/harden-progressive-disclosure.html`
**Type**: Create
**Depends**: None
**Acceptance**:
- [ ] File is self-contained (no external assets, no network requests)
- [ ] HTML comment at top enumerates which ACs it covers (AC3 each command, AC5 compound)
- [ ] Contains enough DOM nodes that `page analyze` / `page find` / `dom select '*'` / a `--include-snapshot`-driven click all produce >16 KB output
- [ ] Contains elements with rich attributes, inline event listeners (for `dom events`), and overlays (for `page analyze`)
- [ ] Contains a script that emits >200 console messages (for `console read`)

**Notes**: This is the feature-exercise fixture per `steering/tech.md` § Feature Exercise Gate. One file covers most of AC3; `audit` uses its own fixture because Lighthouse is external.

---

## Phase 2: Backend — Output layer + SKILL template

### T003: Implement `output::emit_with_snapshot` helper

**File(s)**: `src/output.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] New `pub fn emit_with_snapshot<T, F>(value, output, command_name, snapshot_field, snapshot_summary_fn) -> Result<(), AppError>` with the signature from design.md
- [ ] Below-threshold branch: full inline JSON printed, identical to `emit`
- [ ] Above-threshold branch: outer object printed with `[snapshot_field]` replaced by a `TempFileOutput` object; everything else inline
- [ ] Missing-snapshot-field fallback: if `value[snapshot_field]` is absent after serialization, delegate to `emit` (never panic)
- [ ] Unit test: `emit_with_snapshot_below_threshold_is_inline`
- [ ] Unit test: `emit_with_snapshot_above_threshold_offloads_snapshot_only`
- [ ] Unit test: `emit_with_snapshot_missing_field_falls_back_to_emit`
- [ ] Unit test: serialized output is valid JSON in both branches

**Notes**: Serialize the outer value once to `serde_json::Value`. Compute size via string re-serialization. Only if above threshold do a second serialization of the extracted `snapshot_field` alone.

### T004: Rewrite SKILL_TEMPLATE with YAML frontmatter and new body

**File(s)**: `src/skill.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] `SKILL_TEMPLATE` constant matches the body from design.md § SKILL.md template rewrite
- [ ] Template begins with `---\nname: agentchrome\ndescription: ...\nversion: "{version}"\n---\n`
- [ ] Description names the six trigger phrases verbatim (AC1): `automate a browser`, `fill a form`, `test a login`, `scrape a page`, `take a screenshot`, `inspect console / network`
- [ ] Body names `agentchrome diagnose <url>`, `agentchrome diagnose --current`, `agentchrome examples strategies`, `--include-snapshot`, and the 16 KB temp-file pattern (AC2)
- [ ] Streaming-command exemption mentioned in the "Large Responses" section
- [ ] `skill_content()` still substitutes `{version}` with `env!("CARGO_PKG_VERSION")`
- [ ] Unit test: rendered `skill_content()` starts with `---\n` and contains every required phrase

**Notes**: Keep the template under 80 lines. The body is the marketing material for agentchrome's discovery surface — every sentence should earn its place.

### T005: Embed version marker in `AppendSection` writer

**File(s)**: `src/skill.rs`
**Type**: Modify
**Depends**: T004
**Acceptance**:
- [ ] `write_section` (or the matching writer) prepends `<!-- agentchrome-version: {CARGO_PKG_VERSION} -->\n\n` immediately after `SECTION_START`
- [ ] Re-installing (overwrite) replaces the old marker — no duplicate markers accumulate
- [ ] `remove_section` (uninstall) removes the marker with the rest of the section
- [ ] Unit test: install via `AppendSection` mode writes `<!-- agentchrome-version: X.Y.Z -->` inside the markers
- [ ] Unit test: two successive installs do not accumulate duplicate markers

**Notes**: Only touches the `AppendSection` branch. `Standalone` and `StandaloneWithConfig` rely on the YAML frontmatter from T004 for their version data.

### T006: Add summary builders for newly gated commands (helper layer)

**File(s)**: `src/audit.rs`, `src/dom.rs`, `src/page/analyze.rs`, `src/page/find.rs`, `src/console.rs`
**Type**: Modify
**Depends**: None
**Acceptance**:
- [ ] Each module exposes (module-private) `fn summary_of_<cmd>(result) -> serde_json::Value` per AC4's shape table
- [ ] Unmeasurable fields serialize as `serde_json::Value::Null`, not omitted or `"none"` (retrospective.md:58)
- [ ] Unit test per summary builder: happy-path shape assertion + null-field assertion
- [ ] No summary builder inspects `output::*` internals — summary computation is decoupled from the emit helper

**Notes**: These helpers exist separately from the call-site changes (T007–T013) so the unit tests can cover shape without pulling in the full CDP path. Keep summary builders `const`-adjacent near the top of each module, above the `execute_*` functions.

---

## Phase 3: Backend — Command-site gating

### T007: Gate `audit` output through `output::emit`

**File(s)**: `src/audit.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] The stdout-producing path in `execute_lighthouse` replaces `print_output(&result, ...)` (or equivalent) with `output::emit(&result, &global.output, "audit lighthouse", summary_of_audit)`
- [ ] The `--file` path (writing the full Lighthouse report to a user-chosen path) is unchanged
- [ ] Below-threshold invocations: stdout JSON identical to pre-feature behavior (AC9)
- [ ] Above-threshold invocations: stdout is a `TempFileOutput` with `summary` matching AC4 shape

### T008: Gate `dom select / attributes / events` output through `output::emit`

**File(s)**: `src/dom.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] `execute_select`, the attribute-read path, and the event-listener path each call `output::emit` with the appropriate summary builder
- [ ] Command names are `"dom select"`, `"dom get-style"`, `"dom events"` respectively (match real `capabilities` subcommand paths — `dom get-style` fills the "full-attribute read" slot since there is no `dom attributes` verb)
- [ ] Write-oriented DOM subcommands (`set-attribute`, `set-text`, `set-style`, `remove`, `get-text`, `get-html`) remain on `print_output` — they are out of scope (not listed in AC3)
- [ ] Below-threshold behavior unchanged for every touched command

**Notes**: `dom.rs` has many subcommands. Touch only the three named in AC3. Leave others untouched to keep the diff reviewable.

### T009: Gate `page analyze` output through `output::emit`

**File(s)**: `src/page/analyze.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] `execute_analyze` replaces `print_output(&result, ...)` with `output::emit(&result, ..., "page analyze", summary_of_analyze)`
- [ ] `framework` is `null` when no framework is detected, not `"none"` / `""` / omitted
- [ ] Below-threshold behavior unchanged

### T010: Gate `page find` output through `output::emit`

**File(s)**: `src/page/find.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] `execute_find` replaces `print_output(&matches, ...)` with `output::emit(&matches, ..., "page find", summary_of_find)`
- [ ] `roles_seen` is an array of unique role strings observed across matches
- [ ] Below-threshold behavior unchanged

### T011: Gate `console read` output through `output::emit`

**File(s)**: `src/console.rs`
**Type**: Modify
**Depends**: T006
**Acceptance**:
- [ ] `execute_read` replaces `print_output` with `output::emit` at both the detail-object path (currently `src/console.rs:408`) and the list-output path (currently `src/console.rs:434`)
- [ ] `execute_follow` remains on the unbuffered streaming path (AC3 exemption; FR15)
- [ ] Summary captures error/warning counts even when the body is offloaded
- [ ] Below-threshold behavior unchanged

### T012: Gate every `--include-snapshot` site via `output::emit_with_snapshot`

**File(s)**: `src/interact.rs`, `src/form.rs`, `src/navigate.rs`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] Every site currently building an `if args.include_snapshot { ... }` result struct and calling `print_output` switches to `emit_with_snapshot(&result, ..., "<command>", "snapshot", summary_of_snapshot)`
- [ ] Sites that do NOT include a snapshot remain on `print_output`
- [ ] Interaction-confirmation fields (e.g., `success`, `uid`, `navigation`) remain inline in both branches (AC5)
- [ ] The `summary_of_snapshot` helper reuses `page snapshot`'s existing `{total_nodes, top_roles}` shape
- [ ] All 15+ call sites referenced in the design's grep output are updated (verified by final grep for `include_snapshot.*print_output`)

**Notes**: This is the largest call-site change. Commit logically (interact, form, navigate as separate commits within the PR) to ease review. Keep behavior identical below threshold.

### T013: Gate `capabilities <command>` detail path through `output::emit` (dependent on #218)

**File(s)**: `src/capabilities_cli.rs`
**Type**: Modify
**Depends**: T006
**Acceptance** (if #218 is merged before branch-cut):
- [ ] The detail path for `capabilities <command>` (the new one #218 introduces) calls `output::emit` with `summary_of_capabilities_detail`
- [ ] The *listing* path for `capabilities` (no arg) remains unchanged — #218 caps it at <4 KB already
- [ ] Below-threshold behavior unchanged

**Notes**: FR7 is **Should**, not Must. If #218 has not merged when this branch cuts, mark T013 as deferred and reopen as a follow-up amendment issue. Do not block the rest of the feature on it.

---

## Phase 4: Backend — Staleness check + config

### T014: Create `src/skill_check.rs` module skeleton

**File(s)**: `src/skill_check.rs`, `src/main.rs`
**Type**: Create + Modify
**Depends**: T001
**Acceptance**:
- [ ] New module file with `pub fn emit_stale_notice_if_any(config: &agentchrome::config::ConfigFile)` — returns `()`, never `Result`
- [ ] `mod skill_check;` added to `src/main.rs` alongside the existing sibling modules
- [ ] Function is a no-op body at this task (empty stub); full logic lands in T015
- [ ] Module compiles with clippy `all=deny, pedantic=warn` clean

### T015: Implement version-marker parsing and stale-tool scan

**File(s)**: `src/skill_check.rs`
**Type**: Modify
**Depends**: T014
**Acceptance**:
- [ ] `fn read_version_marker(path: &Path) -> Option<Version>` parses all three forms: YAML `version:` (quoted or unquoted), legacy `Version: X.Y.Z`, and HTML comment `<!-- agentchrome-version: X.Y.Z -->`
- [ ] `Version` is a `(u32, u32, u32)` tuple — no `semver` crate dependency
- [ ] Garbage input → `None` (silent skip)
- [ ] `fn stale_tools(tools, binary_version) -> Vec<StaleTool>` iterates the TOOLS registry, resolves each path, stats, reads the first ~20 lines, and collects stale entries
- [ ] I/O errors (missing file, permission denied, unreadable) yield `None` for that tool — no propagation
- [ ] Unit tests cover: each marker format; garbage input; missing file; newer installed version (not stale); exact match (not stale)

**Notes**: Reuse `skill::TOOLS` and `skill::resolve_path` / `skill::path_template`. Exposing those as `pub(crate)` is acceptable; they need to be reachable from `skill_check.rs`.

### T016: Wire staleness notice into `run()` with suppression gates

**File(s)**: `src/main.rs`, `src/skill_check.rs`
**Type**: Modify
**Depends**: T015
**Acceptance**:
- [ ] `run()` calls `skill_check::emit_stale_notice_if_any(&config_file)` immediately after `config::load_config` returns and before `apply_config_defaults` (so the notice precedes any per-command stderr output)
- [ ] Env-var short-circuit: `AGENTCHROME_NO_SKILL_CHECK=1` (exact string) skips the check entirely — no stat calls
- [ ] Config-key short-circuit: `config.skill.check_enabled == Some(false)` skips the check
- [ ] Single-tool notice grammar: `note: installed agentchrome skill for <tool> is v<ver> but binary is v<binary_ver> — run 'agentchrome skill update' to refresh\n`
- [ ] Multi-tool notice grammar: `note: installed agentchrome skills for <t1>, <t2> are stale (oldest v<ver>, binary v<binary_ver>) — run 'agentchrome skill update' to refresh\n`
- [ ] Notice is `eprintln!`-ed (single write, single trailing `\n`)
- [ ] Unit tests for each notice format (single / multi / no-stale / suppressed)

---

## Phase 5: Integration

### T017: Verify clap help / capabilities / man reflect any surface additions

**File(s)**: (no code changes expected; verification step)
**Type**: Verify
**Depends**: T004, T014
**Acceptance**:
- [ ] `agentchrome --help` is unchanged (no new flags were added)
- [ ] `agentchrome skill --help` output is unchanged
- [ ] `cargo xtask man` still generates a valid man page set
- [ ] `agentchrome capabilities` output lists the (unchanged) skill subcommands
- [ ] Spot-check: no clippy regression, `cargo fmt --check` clean

**Notes**: Per `steering/tech.md` § Clap Help Entries — if a downstream surface degrades, fix at this task.

### T018: Update retrospective-anchored ACs in existing large-response feature doc

**File(s)**: `specs/feature-add-large-response-detection-with-guided-search-and-full-response-override/requirements.md`
**Type**: Modify
**Depends**: T003
**Acceptance**:
- [ ] Add a pointer in that spec's Change History: `| #220 | 2026-04-22 | Extended temp-file gating + compound schema (see feature-harden-progressive-disclosure-enrich-skill-md-extend-temp-file-gating-notify-on-stale-skill/) |`
- [ ] Add a one-line note after AC21 referencing the compound-schema extension: `Compound interaction+snapshot results use an extension of this shape — see the harden-progressive-disclosure spec.`
- [ ] Append this issue to that spec's `**Issues**` frontmatter (now plural comma-separated)
- [ ] Do NOT rewrite existing ACs — this is an amendment (spec-frontmatter.md amendment rules)

**Notes**: This is the cross-reference that lets `/run-retro` trace compound-schema findings back to the right origin spec.

---

## Phase 6: Testing (Required)

**Every acceptance criterion MUST have a Gherkin test.** Reference `steering/tech.md` for the BDD framework (cucumber-rs 0.21) and `tests/bdd.rs` for the single-file World convention.

### T019: Create `tests/features/skill-staleness.feature`

**File(s)**: `tests/features/skill-staleness.feature`
**Type**: Create
**Depends**: T016
**Acceptance**:
- [ ] Scenarios cover AC6, AC7, AC8, AC10 (eleven ACs total for the feature; AC6–AC8 + AC10 are staleness-specific)
- [ ] Scenarios for: stale single tool → notice; stale multi-tool → aggregated notice; fresh → no notice; missing → silent; env-suppressed → silent; config-suppressed → silent; `skill update` when already fresh is idempotent; staleness notice precedes streaming-command output
- [ ] File is valid Gherkin syntax (checked by `cargo test --test bdd`)

### T020: Extend `tests/features/large-response-detection.feature`

**File(s)**: `tests/features/large-response-detection.feature`
**Type**: Modify
**Depends**: T007, T008, T009, T010, T011, T012
**Acceptance**:
- [ ] One scenario per newly gated command: `audit`, `dom select`, `dom get-style`, `dom events`, `page analyze`, `page find`, `console read`, `interact click --include-snapshot`
- [ ] Each scenario asserts the command's `TempFileOutput.summary` matches its AC4 shape
- [ ] One compound-schema scenario for `--include-snapshot` above threshold (AC5): interaction fields inline, `snapshot` key offloaded
- [ ] One compound-schema scenario for `--include-snapshot` below threshold: fully inline
- [ ] One scenario for below-threshold behavior on any gated command: `AC9 unchanged` (e.g., `page find` on a fixture with three matches → stdout is the raw JSON array, no temp file)

### T021: Add SKILL.md content assertions to `tests/features/skill-command-group.feature`

**File(s)**: `tests/features/skill-command-group.feature`
**Type**: Modify
**Depends**: T004, T005
**Acceptance**:
- [ ] New scenario `SKILL.md has YAML frontmatter on install` — asserts the installed file starts with `---\nname: agentchrome\n` and contains the description with all six trigger phrases
- [ ] New scenario `SKILL.md names high-leverage paths` — asserts the body contains `diagnose`, `examples strategies`, `--include-snapshot`, and `output_file`
- [ ] New scenario `AppendSection install writes version marker` — asserts Windsurf-style install contains `<!-- agentchrome-version: ` inside section markers
- [ ] Existing scenarios unchanged

### T022: Implement step definitions in `tests/bdd.rs`

**File(s)**: `tests/bdd.rs`
**Type**: Modify
**Depends**: T019, T020, T021
**Acceptance**:
- [ ] New World or shared World entries for `StaleSkillWorld` (temp dir with planted skill files) and for compound-schema assertions
- [ ] All new `Given/When/Then` step phrases from T019–T021 have matching step definitions
- [ ] `cargo test --test bdd` passes locally (Chrome-dependent scenarios skip without a live Chrome; logic assertions run unconditionally)
- [ ] No orphan steps (every scenario step has a definition)

### T023: Manual smoke test against real headless Chrome

**File(s)**: `tests/fixtures/harden-progressive-disclosure.html` (used here, no new files)
**Type**: Verify
**Depends**: T007, T008, T009, T010, T011, T012, T016, T022
**Acceptance**:
- [ ] `cargo build` produces a fresh debug binary
- [ ] `./target/debug/agentchrome connect --launch --headless` succeeds
- [ ] `./target/debug/agentchrome navigate file://<abs-path>/tests/fixtures/harden-progressive-disclosure.html` succeeds
- [ ] For each AC3 command, a real invocation produces a `TempFileOutput` object when the fixture pushes output over 16 KB, with summary matching AC4
- [ ] A compound `--include-snapshot` interaction against the fixture emits the compound schema per AC5
- [ ] Install a skill via `skill install --tool claude-code`, manually edit the installed file's version to a lower version, then run any `agentchrome` command and observe the stderr notice exactly once
- [ ] `AGENTCHROME_NO_SKILL_CHECK=1 agentchrome tabs list` emits no notice even when the skill is stale
- [ ] Smoke test manually installs and inspects a Windsurf-mode skill if `~/.codeium/` exists locally — confirms HTML comment version marker round-trips (or falls back to plain-text marker if stripped)
- [ ] Disconnect and verify `pkill -f 'chrome.*--remote-debugging' || true` leaves no orphans

---

## Dependency Graph

```
T001 ──┐
       ├──▶ T014 ──▶ T015 ──▶ T016 ──┐
T002 ──┘                              │
                                      │
T003 ──┬──▶ T012 ────────────────────┤
       │                              │
       └──▶ T018                     │
                                      │
T004 ──▶ T005 ──▶ T021                │
                                      │
T006 ──┬──▶ T007                     │
       ├──▶ T008                     │
       ├──▶ T009                     │
       ├──▶ T010                     │
       ├──▶ T011                     │
       └──▶ T013 (if #218 merged)    │
                                      │
T007,T008,T009,T010,T011,T012 ────▶ T020
                                      │
T019 ──┐                              │
T020 ──┼──▶ T022 ──▶ T023 ◀───────── ┘
T021 ──┘
                                      
T017 ── parallel to T007–T016 (verification gate, no code blocker)
```

**Critical path**: T001 → T014 → T015 → T016 → T022 → T023 (staleness check end-to-end).

The call-site gating tasks (T007–T013) can run fully parallel to the staleness-check branch once T003/T006 land, which shortens overall wall time if multiple hands share the work.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #220 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

Before moving to IMPLEMENT phase:

- [x] Each task has single responsibility
- [x] Dependencies are correctly mapped
- [x] Tasks can be completed independently (given dependencies)
- [x] Acceptance criteria are verifiable
- [x] File paths reference actual project structure (per `structure.md`)
- [x] Test tasks are included for each layer (unit in T003/T006/T015, BDD in T019–T022, smoke in T023)
- [x] No circular dependencies
- [x] Tasks are in logical execution order (setup → output layer → command sites → staleness check → integration → test)
- [x] Manual smoke test task included (T023) per `steering/tech.md` § Manual Smoke Test
- [x] Retrospective-origin spec amendment included (T018) so compound-schema decisions trace back correctly
