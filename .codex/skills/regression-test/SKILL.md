---
name: regression-test
description: Run a spec-driven live regression of the AgentChrome debug build. Use when asked to regression test AgentChrome, test a new debug build against the specs, research public sites that exercise the CLI surface, or file current-milestone automatable defect issues for any findings.
---

# Regression Test

## Overview

Build the local debug binary, verify the SDLC spec surface, exercise AgentChrome itself against live public pages according to the `/specs` artifacts created by `$nmg-sdlc:write-spec`, and file every reproducible finding as an automatable defect in the current milestone. Keep the work evidence-based: commands, outputs, exit codes, source/spec references, and GitHub issue links.

Do not stop at research or planning. Continue through build, live execution, issue filing, cleanup, and summary unless the user explicitly redirects.

## Ground Rules

- Use the project checkout's debug binary: `./target/debug/agentchrome`.
- Use AgentChrome itself for browser automation.
- Exercise behavior against `/specs` artifacts created by `$nmg-sdlc:write-spec`, especially `specs/*/requirements.md`; do not run ad hoc demos that are disconnected from a spec expectation.
- Prefer live behavior over assumptions. Verify target availability before relying on a site.
- Run focused or full BDD where it proves the spec surface. If local socket/network sandboxing blocks tests or Chrome, rerun the same command with appropriate approval before treating it as a defect.
- Do not fix findings during regression unless the user explicitly asks. File issues instead.
- File issues in the current active milestone with `bug` and `automatable`; add area labels such as `cli`, `core`, or `docs` when applicable.
- Use `$nmg-sdlc:draft-issue` standards: SDLC-ready issue body, defect classification, concrete reproduction, expected vs actual behavior, Given/When/Then acceptance criteria, functional requirements, scope boundaries, priority, and automation suitability.

## Workflow

### 1. Gather Current Context

1. Check `git status --short --branch`.
2. Read `AGENTS.md`, `steering/product.md`, `steering/tech.md`, and `steering/structure.md`.
3. Inventory command/spec coverage from `/specs`, especially `specs/*/requirements.md`, `design.md`, and `tasks.md` where present.
4. Build a coverage matrix that maps each live command group and scenario to an SDLC spec artifact. Use `tests/features/` only as executable evidence derived from the specs, not as the source of truth. Mark purely local/documentation specs separately from browser-facing specs.
5. Read `./target/debug/agentchrome capabilities --json` after building to confirm the live command surface.

### 2. Research and Select Live Targets

Use current web research or direct availability checks when the user asks to find a site. Prefer broad public practice targets over narrow fixtures.

Default target set:

- `https://qaplayground.vercel.app/` for broad coverage: forms, buttons, checkboxes, dropdowns, waits, tables, alerts, modal, iframe, shadow DOM, drag/drop, hover/tooltips, upload/download, tabs, auth, dynamic list, network delay, keyboard, sliders, dates, resizable UI, and complex DOM.
- `https://www.w3schools.com/html/html5_video.asp` for `media` commands because QA Playground has no media elements.
- `https://the-internet.herokuapp.com/iframe` or other focused pages only when a broad target cannot exercise a specific frame/editor primitive.

If a public site is unavailable, blocked, or too narrow, switch quickly and record why.

### 3. Build and Run Spec Gates

1. Run `cargo build`.
2. Run BDD in a way that matches the risk:
   - Full pass when doing a broad regression: `cargo test --test bdd -- --fail-fast`.
   - Focused proof when isolating a finding: `cargo test --test bdd -- --input tests/features/<feature>.feature --fail-fast`.
3. If the BDD run fails because local mock servers or Chrome cannot bind under sandboxing, rerun outside the sandbox before classifying it.

### 4. Launch an Isolated Browser

1. Start headless Chrome:
   ```sh
   ./target/debug/agentchrome connect --launch --headless --pretty
   ```
2. Capture the returned `port`.
3. Use that port for every live command:
   ```sh
   ./target/debug/agentchrome --port <port> navigate <url> --wait-until networkidle --timeout 30000 --pretty
   ```
4. Always snapshot before UID-targeted actions:
   ```sh
   ./target/debug/agentchrome --port <port> page snapshot --compact --pretty
   ```
5. Refresh snapshots after dialogs, modals, navigation, or dynamic DOM changes. UID maps are stateful and may become stale.

### 5. Exercise Command Groups Against Specs

Cover both documentation/discovery commands and browser-facing commands. For each command group, choose live actions that prove the relevant acceptance criteria from `/specs`, especially `specs/*/requirements.md`.

Discovery and local CLI:

- `--help`, `--version`, `capabilities --json`, `capabilities <command>`, `examples`, `examples strategies`, `man`, `completions`, `config show`, `skill list`.

Session/navigation/page:

- `connect`, `connect --status`, `tabs list/create/create --background/activate/close`, `navigate`, `navigate back/forward/reload`, `page text`, `page snapshot`, `page find`, `page wait`, `page analyze`, `page screenshot`, `page coords`, `page frames`.

DOM/JS/console/network:

- `dom select`, `dom tree`, `dom get-html`, `dom get-style`, `dom events`, `js exec`, top-level `await`, `js exec --uid`, `console read`, `console read --errors-only`, `network list`, `network list --type/--url`, `network get`.

Interactions/forms/dialogs:

- `interact click`, `click --double`, `click --right`, `hover`, `scroll`, `click-at`, `drag`, keyboard commands, `form fill`, `form fill-many`, `form clear`, `form upload`, `dialog info`, `dialog handle accept/dismiss`, prompt text.

Advanced surfaces:

- `page --frame N text/snapshot`, `form --frame N fill`, `dom --frame N select`, shadow DOM via snapshot UID targeting, `emulate set/status/reset`, `perf vitals`, `perf record`, `cookie list/set/delete/clear`, `media list/play/pause/seek`.

Validate advertised command examples by running representative examples from `examples`, strategy guides, and man pages. If guidance advertises a command shape the parser rejects, file it as a defect.

When a live action exposes behavior that no spec covers, do not silently invent a product requirement. Classify it as either:

- **Defect**: The behavior contradicts an existing spec, feature, help/man contract, or JSON/exit-code convention.
- **Spec gap**: The behavior appears necessary but is not specified. File or note it as a spec/update need only when the need is obvious and automatable.

### 6. Triage Findings

For every unexpected result:

1. Retry with fresh snapshot or fresh tab if stale UID or page state could explain it.
2. Retry sequentially if a parallel command could have mutated shared browser state.
3. Compare against the relevant `/specs` artifact. Every filed finding must name the SDLC spec it violates, or explicitly state that it is a spec gap. Use BDD feature files only as supporting executable evidence.
4. Read source only enough to identify likely root cause and correct area label.
5. Treat environment failures separately: sandbox socket permissions, DNS/network blocks, site outages, and missing local dependencies are not product defects unless reproducible outside the environment constraint.

### 7. Determine Milestone and File Issues

Before creating issues:

1. Check open issues for duplicates.
2. Determine the current milestone from repository context before filing:
   - Prefer an explicitly active issue branch/spec milestone when the user is already in an SDLC flow.
   - Otherwise inspect open milestones and project context with `gh api repos/:owner/:repo/milestones` and nearby issue/spec metadata.
   - Use `v1` only as a fallback when no current milestone can be determined.
3. Confirm labels and the selected milestone:
   ```sh
   gh label list --limit 100
   gh api repos/:owner/:repo/milestones --jq '.[] | {number,title,state}'
   ```
4. Create each issue in the selected milestone with labels `bug`, `automatable`, and the relevant area label.

Issue body shape:

- `Issue Type`: Bug
- `User Story or Bug/Spike Context`: observed behavior, expected behavior, reproduction notes
- `Current State / Background`: relevant spec and why the behavior matters
- `Acceptance Criteria`: Given/When/Then criteria
- `Functional Requirements`: table with IDs, requirements, priority, notes
- `Scope Boundaries`: in and out of scope
- `Priority`: Must, unless clearly lower
- `Automation Suitability`: Yes
- `Additional Notes`: exact command evidence and compact JSON snippets

### 8. Clean Up and Report

1. Disconnect the launched browser:
   ```sh
   ./target/debug/agentchrome --port <port> connect --disconnect --pretty
   ```
2. Check `git status --short --branch`.
3. Report:
   - target sites used and why
   - build/BDD result
   - command groups exercised
   - issues created with links, labels, and milestone
   - cleanup status and any commands that could not be run
