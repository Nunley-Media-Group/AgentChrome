# Root Cause Analysis: dialog handle --accept misleading clap error

**Issue**: #250
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley

---

## Root Cause

`DialogHandleArgs` (`src/cli/mod.rs:1830`) declares `action: DialogAction` as a bare positional backed by a `ValueEnum`. When a user writes `dialog handle --accept`, clap sees an unknown long flag and raises `ErrorKind::UnknownArgument` with its built-in "tip: to pass '--accept' as a value, use '-- --accept'". That generic tip is correct for free-form positional strings but actively misleading here, because `DialogAction` is a closed enum — the literal string `--accept` is not a valid variant, so the follow-up invocation also fails.

The project already has a targeted "did you mean" path for this class of mistake: `syntax_hint` in `src/main.rs:106` converts `--uid <v>` / `--selector <v>` errors on positional-target subcommands into `Did you mean: agentchrome <sub> <value>` suffixes on the JSON error. The function is scoped to a fixed allowlist of flags and derives the subcommand path from argv via `resolve_subcommand_path`. It currently does not recognize `--accept` / `--dismiss`.

The fix is to extend that same allowlist with two new entries for `--accept` and `--dismiss`, gated to the `dialog handle` subcommand path, and to emit a hint that uses the flag name (with the leading dashes stripped) as the suggested positional value. No new code path, no refactor — only additional cases in the existing match.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/main.rs` | 106–126 | `syntax_hint` — the function that maps clap's `UnknownArgument` errors to targeted "Did you mean" suffixes. |
| `src/main.rs` | 56–91 | `main` clap error branch — consumes `syntax_hint`'s return value; no change needed here. |
| `src/cli/mod.rs` | 1828–1846 | `DialogHandleArgs` / `DialogAction` — not modified; the fix intentionally keeps the positional-only shape. |

### Triggering Conditions

- The subcommand being invoked is `dialog handle`.
- The user passes `--accept` or `--dismiss` as a long flag instead of the positional value.
- Clap raises `ErrorKind::UnknownArgument` with `InvalidArg = "--accept"` (or `--dismiss`).
- Prior to this fix, the existing `syntax_hint` returned `None` for these flags, so the JSON error contained clap's misleading generic tip and nothing else.

---

## Fix Strategy

### Approach

Extend `syntax_hint` to recognize two additional flags, `--accept` and `--dismiss`, and scope them to the `dialog handle` subcommand path. For these flags the "value" is not read from argv (unlike `--uid <v>`); instead, the suggested positional is derived from the flag name itself by stripping the `--` prefix. The emitted hint reuses the existing format string: `Did you mean: agentchrome dialog handle <accept|dismiss>`.

This is the minimal correct fix because (a) it reuses the hint pipeline that already wraps the JSON error cleanly, (b) it does not touch the clap derive types and therefore cannot regress valid positional parsing or man-page generation, and (c) it preserves the CLI's one-way-to-invoke convention (no new flag aliases introduced).

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/main.rs` | In `syntax_hint`, add a branch: if `bare` is `--accept` or `--dismiss` **and** `resolve_subcommand_path(argv) == "dialog handle"`, return `Some("Did you mean: agentchrome dialog handle <action>")` where `<action>` is `bare.trim_start_matches('-')`. | Directly maps the misleading error to the correct invocation. The subcommand-path guard prevents accidental firing on any future subcommand that genuinely accepts `--accept`/`--dismiss`. |
| `src/main.rs` tests | Add unit tests analogous to `syntax_hint_click_uid_produces_did_you_mean` covering both `--accept` and `--dismiss`, plus a guard test confirming the hint does not fire on a different subcommand. | Locks in the behavior and protects against the misleading tip regressing. |

### Blast Radius

- **Direct impact**: `syntax_hint` in `src/main.rs`. The function's input contract (clap error + argv) and output contract (`Option<String>` suffix) are unchanged — only the set of inputs producing `Some(...)` expands.
- **Indirect impact**: The `main` clap-error branch that consumes the returned suffix is unchanged; any caller receiving the new suffix gets the same JSON-on-stderr shape as today's `--uid` hint.
- **Risk level**: Low. The change is additive, fully covered by new unit tests, and cannot affect successful parses because `syntax_hint` is only reached after `Cli::try_parse()` already returned `Err`.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Hint fires on an unrelated subcommand that legitimately uses `--accept` / `--dismiss` in the future. | Low | The fix guards on `resolve_subcommand_path(argv) == "dialog handle"`; any new subcommand with these flags would not match. A dedicated unit test exercises the negative case. |
| Valid invocation `dialog handle accept` / `dismiss` breaks. | Very Low | No change to `DialogHandleArgs` or `DialogAction`. `syntax_hint` only runs on parse failure, so successful parses are untouched. An explicit BDD scenario (AC3) covers this. |
| Existing `--uid` / `--selector` hint regresses. | Very Low | Additive match arm; existing arms and their tests remain. The existing `syntax_hint_click_uid_produces_did_you_mean` test continues to pass. |
| Output shape of the JSON error changes (breaks AI-agent consumers). | Very Low | The new hint is appended to the existing `clean` message using the same `. {hint}` pattern as today's `--uid` path; `AppError::print_json_stderr` serialization is unchanged. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Add `--accept` / `--dismiss` as real boolean flag aliases that populate `action`. | Declare two `#[arg(long, conflicts_with_all = ["action"])]` booleans and map them in a `value_parser` or in the command executor. | Breaks the CLI's one-way-to-invoke convention, inflates the argument surface (accept, dismiss, --accept, --dismiss, plus the `action` positional) and complicates man-page / completion generation. The reported user pain is discoverability of the correct form, which the hint resolves without expanding the surface. |
| Custom clap `error_format` / `mut_arg` hook that rewrites clap's tip text. | Intercept clap's error rendering before our JSON wrapper sees it. | Would require maintaining a parallel error formatter against a moving clap API, with no clear benefit over the existing `syntax_hint` helper that's already proven on `--uid`/`--selector`. |

---

## Validation Checklist

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (extends `syntax_hint` per `structure.md`'s "CLI layer")

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #250 | 2026-04-23 | Initial defect design |
