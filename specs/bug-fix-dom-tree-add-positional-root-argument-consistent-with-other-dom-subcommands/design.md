# Root Cause Analysis: `dom tree` missing positional ROOT argument

**Issue**: #251
**Date**: 2026-04-23
**Status**: Draft
**Author**: Rich Nunley

---

## Root Cause

The `DomTreeArgs` struct in `src/cli/mod.rs` defines `root` as a `#[arg(long)]`-only option, while every sibling `dom` subcommand that targets a node uses the shared `DomNodeIdArgs` struct whose `node_id` field is a plain positional. When the user follows the established sibling pattern (`dom tree "css:table"`), clap has no positional slot to bind the argument to, and emits `error: unexpected argument 'css:table' found`.

This is an API-shape inconsistency introduced when `dom tree` was originally scaffolded — the author modeled it after `page snapshot` (all flags) rather than after `dom get-text`, `dom children`, etc. (positional target). There is no functional reason the target needs to be flag-only; `execute_tree` already accepts the resolved root uniformly via `args.root`.

### Affected Code

| File | Lines | Role |
|------|-------|------|
| `src/cli/mod.rs` | 3554–3564 | `DomTreeArgs` struct — declares `root: Option<String>` as `#[arg(long)]` only. This is the root cause. |
| `src/cli/mod.rs` | 3443–3459 | `Tree` variant's `after_long_help` EXAMPLES — documents only the `--root` form. |
| `src/dom.rs` | 2005–2055 | `execute_tree` — reads `args.root`; no change needed once the struct is updated. |
| `src/examples_data.rs` | 284–288 | `dom tree --depth 3` example entry — does not show the positional form. |
| `man/agentchrome-dom-tree.1` | (whole file) | Auto-generated from clap; must be regenerated after the struct change. |

### Triggering Conditions

- User invokes `agentchrome dom tree <target>` following the sibling-subcommand pattern.
- clap's derive parser has no positional in `DomTreeArgs`, so any non-flag token is rejected.
- This wasn't caught because the original clap tests for `dom tree` only exercised `--root` and the no-argument form, mirroring the (incomplete) EXAMPLES block.

---

## Fix Strategy

### Approach

Add an optional positional `root_positional: Option<String>` field to `DomTreeArgs` alongside the existing `root: Option<String>` flag, with `conflicts_with = "root"` on the positional so clap enforces mutual exclusion natively. In `execute_tree`, resolve the effective root as `args.root_positional.as_ref().or(args.root.as_ref())` — a one-line change that preserves every existing code path. This is the minimal correct fix because it:

- Matches the sibling-subcommand API without introducing a new shared args struct.
- Relies on clap's built-in `conflicts_with` for the conflict error (AC4) rather than ad-hoc runtime validation.
- Leaves `--root` working unchanged so existing scripts and `DOM.describeNode` resolution behavior are byte-identical (AC2).

### Changes

| File | Change | Rationale |
|------|--------|-----------|
| `src/cli/mod.rs` (`DomTreeArgs`) | Add `#[arg(value_name = "ROOT", conflicts_with = "root")] pub root_positional: Option<String>` positional field. | Exposes the positional slot; clap handles the conflict error. |
| `src/cli/mod.rs` (`Tree` variant `after_long_help`) | Add an EXAMPLES entry demonstrating `agentchrome dom tree css:div.content` (positional form). | Keeps help text aligned with the new shape per `tech.md` "Clap Help Entries" rule. |
| `src/dom.rs` (`execute_tree`) | Resolve `let target = args.root_positional.as_ref().or(args.root.as_ref());` and use `target` in place of `args.root`. | Single-line wiring; preserves behavior. |
| `src/examples_data.rs` | Add an entry showing `agentchrome dom tree css:table --depth 3`. | Surfaces the canonical positional form in `agentchrome examples dom`. |
| `man/agentchrome-dom-tree.1` | Regenerate via the project's man-page generator (e.g., `cargo xtask man`). | Man pages are clap-driven — must stay in sync. |

### Blast Radius

- **Direct impact**: `DomTreeArgs` struct layout, `execute_tree` root resolution, `dom tree` help text.
- **Indirect impact**: `agentchrome capabilities` (clap-driven manifest) will now advertise the new positional; `agentchrome examples dom` listing gains one entry; generated man page and shell completions regenerate on next build.
- **Risk level**: Low. The positional is additive and optional; all three existing invocation shapes (`dom tree`, `dom tree --root X`, `dom tree --depth N`) remain valid with unchanged semantics.

---

## Regression Risk

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Existing `--root` callers break due to renamed field | Low | `root` field name and its `--root` long flag are unchanged; only an additional positional is added. AC2 regression test covers this. |
| No-argument form accidentally requires positional | Low | Positional is declared `Option<String>`; AC3 regression test exercises the no-arg form. |
| Conflict error has wrong shape (stderr/exit code) | Low | AC4 asserts clap-native conflict error — same shape as other `conflicts_with` cases in the binary. |
| Capabilities manifest / man page drift | Medium | Regenerate man page in T001; verification gate's build step recompiles clap-driven artifacts. |

---

## Alternatives Considered

| Option | Description | Why Not Selected |
|--------|-------------|------------------|
| Reuse `DomNodeIdArgs` and add a separate `--depth` flag wrapper | Replace `DomTreeArgs` with `{ node_args: DomNodeIdArgs, depth: Option<u32> }`. | Would make the target **required** (breaking AC3's no-argument form) unless `DomNodeIdArgs` is forked to an optional variant — more churn than adding one field. |
| Runtime validation of conflict instead of `conflicts_with` | Check both fields in `execute_tree` and return a custom `AppError`. | Duplicates functionality clap already provides, produces a less consistent error format, and requires an extra unit test. |

---

## Validation Checklist

- [x] Root cause is identified with specific code references
- [x] Fix is minimal — no unrelated refactoring
- [x] Blast radius is assessed
- [x] Regression risks are documented with mitigations
- [x] Fix follows existing project patterns (per `structure.md`)

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #251 | 2026-04-23 | Initial defect design |
