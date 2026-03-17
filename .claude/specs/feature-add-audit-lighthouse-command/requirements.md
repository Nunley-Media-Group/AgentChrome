# Requirements: Add `audit lighthouse` Command

**Issues**: #169
**Date**: 2026-03-15
**Status**: Draft
**Author**: Claude

---

## User Story

**As an** AI agent or automation engineer using agentchrome
**I want** to run Google Lighthouse audits directly through the CLI
**So that** I can get structured performance, accessibility, SEO, and best-practice scores as part of automated browser workflows and CI pipelines without leaving the agentchrome tool

---

## Background

agentchrome already provides Core Web Vitals measurement via `perf vitals` (LCP, CLS, TTFB) by parsing raw Chrome Trace Event data. However, Lighthouse provides a much richer audit surface: scored categories (Performance, Accessibility, Best Practices, SEO, PWA), individual audit items, and improvement suggestions — all via the well-known `lighthouse` CLI binary.

This issue adds a new `audit` command group with a `lighthouse` subcommand that shells out to the `lighthouse` binary, connecting it to the already-managed Chrome session via `--port`, and returns structured JSON scores on stdout. This is a greenfield `audit` command group; the existing `perf` group is not modified.

---

## Acceptance Criteria

**IMPORTANT: Each criterion becomes a Gherkin BDD test scenario.**

### AC1: Run a full Lighthouse audit on the current page

**Given** agentchrome is connected to a Chrome instance with an active page
**When** the user runs `agentchrome audit lighthouse`
**Then** a full Lighthouse audit is executed against the current page URL
**And** a JSON object containing scores for Performance, Accessibility, Best Practices, SEO, and PWA categories is returned on stdout

**Example**:
- Given: connected Chrome on port 9222 with `https://example.com` loaded
- When: `agentchrome audit lighthouse`
- Then: stdout contains `{"url":"https://example.com","performance":0.91,"accessibility":0.87,"best-practices":0.93,"seo":0.90,"pwa":0.30}`

### AC2: Run a targeted audit for specific categories

**Given** agentchrome is connected to a Chrome instance
**When** the user runs `agentchrome audit lighthouse --only performance,accessibility`
**Then** only the specified categories are audited and their scores are returned as JSON on stdout
**And** categories not specified in `--only` are omitted from the output

**Example**:
- Given: connected Chrome on port 9222
- When: `agentchrome audit lighthouse --only performance,accessibility`
- Then: stdout contains `{"url":"...","performance":0.91,"accessibility":0.87}` with no `seo`, `best-practices`, or `pwa` keys

### AC3: Save the full report to a file

**Given** agentchrome is connected to a Chrome instance
**When** the user runs `agentchrome audit lighthouse --output-file ./report.json`
**Then** the full Lighthouse JSON report is saved to the specified path
**And** the category scores summary is still returned on stdout

**Example**:
- Given: connected Chrome on port 9222
- When: `agentchrome audit lighthouse --output-file ./report.json`
- Then: `./report.json` contains the full Lighthouse report and stdout contains the scores summary

### AC4: Explicit URL argument overrides the active page

**Given** agentchrome is connected to a Chrome instance viewing `https://other.com`
**When** the user runs `agentchrome audit lighthouse https://example.com`
**Then** the Lighthouse audit runs against `https://example.com` rather than the current active page's URL

**Example**:
- Given: Chrome is connected and viewing `https://other.com`
- When: `agentchrome audit lighthouse https://example.com`
- Then: the result JSON `url` field is `https://example.com`

### AC5: Lighthouse binary not found returns a structured error

**Given** the `lighthouse` binary is not installed or not in `PATH`
**When** the user runs `agentchrome audit lighthouse`
**Then** a structured JSON error is written to stderr explaining that Lighthouse must be installed (`npm install -g lighthouse`)
**And** the process exits with a non-zero exit code

**Example**:
- Given: `lighthouse` is not on `PATH`
- When: `agentchrome audit lighthouse`
- Then: stderr contains `{"error":"lighthouse binary not found. Install it with: npm install -g lighthouse","code":1}` and exit code is 1

### AC6: No active session returns a connection error

**Given** agentchrome has no active session (no Chrome connected)
**When** the user runs `agentchrome audit lighthouse`
**Then** a structured JSON error is written to stderr indicating no active session
**And** the process exits with exit code 2 (connection error)

### AC7: Lighthouse execution failure returns a structured error

**Given** agentchrome is connected to a Chrome instance
**And** the `lighthouse` binary is on `PATH` but fails during execution (e.g., invalid URL, Chrome timeout)
**When** the user runs `agentchrome audit lighthouse`
**Then** a structured JSON error is written to stderr with the Lighthouse error message
**And** the process exits with exit code 1

### AC8: The `--port` global flag is respected

**Given** agentchrome is connected to Chrome on a non-default port (e.g., 9333)
**When** the user runs `agentchrome --port 9333 audit lighthouse`
**Then** Lighthouse is invoked with `--port 9333` to connect to the correct Chrome instance

---

## Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR1 | Shell out to the `lighthouse` CLI binary found in `PATH` | Must | Use `which`/`command -v` equivalent to locate the binary |
| FR2 | Connect Lighthouse to the existing Chrome session via `--port <PORT>` | Must | Port comes from session or `--port` global flag |
| FR3 | Return category scores (Performance, Accessibility, Best Practices, SEO, PWA) as a flat JSON object on stdout | Must | Format: `{"url":"...","performance":0.91,...}` |
| FR4 | Support `--only <categories>` comma-separated list to run a subset of audit categories | Must | Valid values: performance, accessibility, best-practices, seo, pwa |
| FR5 | Return a structured JSON error on stderr when `lighthouse` binary is not found | Must | Include installation hint: `npm install -g lighthouse` |
| FR6 | Support `--output-file <path>` to save the full Lighthouse report to disk | Should | Full report is the complete Lighthouse JSON output |
| FR7 | Use the active tab's URL by default; accept an optional positional `[URL]` argument to override | Should | Retrieve active page URL via CDP `Target.getTargets` or session state |
| FR8 | Respect `AGENTCHROME_PORT` / `--port` global flag when constructing the `--port` argument passed to Lighthouse | Must | Standard global opts resolution chain |
| FR9 | Pass `--output json --chrome-flags="--headless"` to Lighthouse for machine-readable output | Must | Ensures structured JSON output from Lighthouse |
| FR10 | Parse Lighthouse JSON output and extract category scores into the flat summary format | Must | Map `lhr.categories[name].score` to output fields |

---

## Non-Functional Requirements

| Aspect | Requirement |
|--------|-------------|
| **Performance** | Lighthouse audits inherently take 10-60s; the agentchrome overhead should be < 500ms (binary lookup + process spawn + JSON parsing) |
| **Reliability** | Graceful error handling when Lighthouse fails, times out, or produces unexpected output |
| **Platforms** | macOS, Linux, Windows — `lighthouse` binary must be found via platform-appropriate PATH resolution |
| **Output Compliance** | JSON on stdout, JSON errors on stderr, standard exit codes per `tech.md` |

---

## Data Requirements

### Input Data

| Field | Type | Validation | Required |
|-------|------|------------|----------|
| `[URL]` | String (positional) | Must be a valid URL if provided | No — defaults to active page URL |
| `--only` | Comma-separated string | Each value must be one of: performance, accessibility, best-practices, seo, pwa | No — defaults to all categories |
| `--output-file` | File path | Parent directory must exist and be writable | No |

### Output Data (stdout — scores summary)

| Field | Type | Description |
|-------|------|-------------|
| `url` | String | The URL that was audited |
| `performance` | Float (0.0–1.0) or absent | Performance category score |
| `accessibility` | Float (0.0–1.0) or absent | Accessibility category score |
| `best-practices` | Float (0.0–1.0) or absent | Best Practices category score |
| `seo` | Float (0.0–1.0) or absent | SEO category score |
| `pwa` | Float (0.0–1.0) or absent | PWA category score |

When `--only` is used, only the specified categories appear in the output. When a category score is `null` in the Lighthouse output (unmeasurable), the field MUST appear as `null` rather than being omitted — distinguishing "not requested" (absent) from "requested but unmeasurable" (`null`).

---

## Dependencies

### Internal Dependencies
- [x] Session management (`session.rs`) — for reading the active port
- [x] Connection resolution (`connection.rs`) — for resolving the port from global opts
- [x] CLI framework (`cli/mod.rs`) — for adding the `audit` command group
- [x] Error types (`error.rs`) — for structured JSON error output

### External Dependencies
- [ ] `lighthouse` CLI binary — must be installed separately via `npm install -g lighthouse`

### Blocked By
- None

---

## Out of Scope

- PageSpeed Insights (PSI) API integration
- Bundling or auto-installing the `lighthouse` binary
- Custom Lighthouse configuration file support (`--config-path`)
- Comparative / diff audits between runs
- CI threshold assertions (pass/fail based on score cutoffs)
- Modifying or extending the existing `perf` command group
- Lighthouse plugin support
- HTML report generation (only JSON is supported)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Overhead latency | < 500ms | Time from command start to Lighthouse process spawn |
| Output correctness | 100% | Scores in stdout match Lighthouse report categories exactly |
| Error clarity | Install hint in error | Binary-not-found error includes `npm install -g lighthouse` |

---

## Open Questions

- (None — all requirements are derived from the well-specified issue)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #169 | 2026-03-15 | Initial feature spec |

---

## Validation Checklist

- [x] User story follows "As a / I want / So that" format
- [x] All acceptance criteria use Given/When/Then format
- [x] No implementation details in requirements
- [x] All criteria are testable and unambiguous
- [x] Success metrics are measurable
- [x] Edge cases and error states are specified (AC5, AC6, AC7)
- [x] Dependencies are identified
- [x] Out of scope is defined
- [x] Open questions are documented (or resolved)
