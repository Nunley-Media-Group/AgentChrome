# Design: Normalize Flag Shapes

**Issues**: #230
**Date**: 2026-04-22
**Status**: Draft
**Author**: Rich Nunley

---

## Overview

Three CLI surfaces diverge from the intuitive flag shape that a first-time user or AI agent guesses: `cookie set --url`, `tabs close --tab`, and `dom query`. Rather than renaming the canonical forms (breaking change) or only improving error messages (still fails first), this design adds **hidden clap aliases** so the guessed forms parse successfully, while keeping canonical forms as the only publicly documented shape.

The design uses clap's native aliasing primitives (`alias` for commands, `alias` on `#[arg]` for flags) in two patterns: a direct subcommand alias (`dom query`), and two "pseudo-alias" flags that sit beside the canonical argument and are post-processed into it (`--url` folds into `--domain`, `--tab` folds into the positional `targets`). Post-processing lives in `src/cookie.rs` and `src/tabs.rs` respectively, keeping `src/cli/mod.rs` as a pure clap schema.

Downstream documentation surfaces (help text, `capabilities` manifest, `examples` subcommand) remain unchanged because clap's `alias` attribute is hidden by default. No changes are needed to capabilities or examples code — the test strategy verifies they do not leak the aliases.

---

## Architecture

### Component Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    clap layer (src/cli/mod.rs)             │
├──────────────────────────────────────────────────────────┤
│  CookieSetArgs: adds --url <URL> (hidden alias, Option<String>) │
│  TabsCloseArgs: adds --tab <ID>... (hidden alias, Vec<String>)  │
│  DomCommand::Select: #[command(alias = "query")]                │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│             Command handler layer                          │
├──────────────────────────────────────────────────────────┤
│  src/cookie.rs::execute_set                                │
│    ├─ if args.url.is_some() && args.domain.is_some() → err│
│    └─ if args.url → parse URL, extract host, set domain   │
│                                                            │
│  src/tabs.rs::execute_close                                │
│    └─ merge positional targets + args.tab into one Vec    │
└───────────────────────────┬──────────────────────────────┘
                            │
                            ▼
      Existing CDP client / Network.setCookie / Target.closeTarget
```

### Data Flow

```
1. User invokes `cookie set NAME VAL --url https://example.com/path`
2. clap parses: CookieSetArgs { name, value, url: Some(...), domain: None, ... }
3. execute_set detects url.is_some(), calls Url::parse, extracts host_str()
4. If both url and domain are Some → AppError { code: GeneralError }
5. Otherwise domain is set to extracted host; flow continues unchanged
6. Same final CDP Network.setCookie call as canonical form
```

---

## API / Interface Changes

### New CLI Surfaces (hidden)

| Surface | Type | Behavior |
|---------|------|----------|
| `cookie set --url <URL>` | Hidden flag alias | URL is parsed; host component becomes the cookie domain. Mutually exclusive with `--domain`. |
| `tabs close --tab <ID>` (repeatable) | Hidden flag alias | Values merged with positional `targets`. At least one of positional or `--tab` required. |
| `dom query <SELECTOR>` | Hidden subcommand alias | Behaves identically to `dom select`; supports all the same flags (e.g., `--xpath`). |

### clap attributes

```rust
// src/cli/mod.rs

pub struct CookieSetArgs {
    pub name: String,
    pub value: String,

    /// Cookie domain (strongly recommended)
    #[arg(long)]
    pub domain: Option<String>,

    /// Hidden: --url accepts a full URL; host is used as domain.
    /// Mutually exclusive with --domain.
    #[arg(long, hide = true, conflicts_with = "domain")]
    pub url: Option<String>,

    // ... existing fields unchanged
}

pub struct TabsCloseArgs {
    /// Tab ID(s) or index(es) to close
    pub targets: Vec<String>,  // drop `required = true`; see post-parse check

    /// Hidden: --tab <ID> may be repeated as an alias for the positional.
    #[arg(long, hide = true, action = ArgAction::Append)]
    pub tab: Vec<String>,
}

pub enum DomCommand {
    #[command(alias = "query", /* existing long_about etc. */)]
    Select(DomSelectArgs),
    // ...
}
```

**Why `hide = true` and not `visible_alias`:** the one-canonical-form story for documentation (help, capabilities, examples) must remain intact. `hide = true` omits the flag from `--help` while still accepting it at parse time. For subcommands, clap's `alias` attribute is hidden by default; `visible_alias` would expose it.

### Post-parse handlers

```rust
// src/cookie.rs::execute_set

let domain = match (&args.url, &args.domain) {
    (Some(_), Some(_)) => unreachable!("clap conflicts_with"),  // belt + suspenders
    (Some(url_str), None) => Some(extract_host(url_str)?),
    (None, maybe_domain) => maybe_domain.clone(),
};
// ... use `domain` in CDP params instead of args.domain
```

```rust
// src/tabs.rs

TabsCommand::Close(close_args) => {
    let mut all_targets = close_args.targets.clone();
    all_targets.extend(close_args.tab.iter().cloned());
    if all_targets.is_empty() {
        return Err(AppError {
            message: "tabs close requires at least one target (positional ID or --tab <ID>)".into(),
            code: ExitCode::GeneralError,
            custom_json: None,
        });
    }
    execute_close(global, &all_targets).await
}
```

### URL host extraction

Use the `url` crate (add as direct dep in `Cargo.toml`):

```rust
fn extract_host(url_str: &str) -> Result<String, AppError> {
    let parsed = url::Url::parse(url_str).map_err(|e| AppError {
        message: format!(
            "--url value '{url_str}' is not a valid URL: {e}. Use --domain <D> to set the cookie domain directly."
        ),
        code: ExitCode::GeneralError,
        custom_json: None,
    })?;
    parsed.host_str().map(|s| s.to_string()).ok_or_else(|| AppError {
        message: format!(
            "--url '{url_str}' has no host component. Use --domain <D> to set the cookie domain directly."
        ),
        code: ExitCode::GeneralError,
        custom_json: None,
    })
}
```

---

## Alternatives Considered

| Option | Description | Pros | Cons | Decision |
|--------|-------------|------|------|----------|
| **A: Rename canonical forms** | Rename `--domain` → `--url`, positional → `--tab`, `select` → `query` | Matches first guess exactly | Breaking change; all agent training data, examples, and existing scripts break | Rejected — out of scope per issue |
| **B: Only improve error messages** | Leave parsing unchanged; rewrite error text to point at canonical forms | No parsing changes | User still fails once per divergence before reading the better error | Rejected — does not restore the self-teaching property |
| **C: Visible aliases** | Use `visible_alias` so aliases appear in help | Discoverable | Dilutes the one-canonical-form story; agents may learn the alias as canonical | Rejected per FR4 |
| **D: Hidden clap aliases (this design)** | `alias` / `hide = true` with post-parse folding | Accepts the guess; canonical form remains sole documented shape; minimal code | `--url` requires a small post-parse step (URL parse + host extract) | **Selected** |
| **E: Custom clap error handler (FR5-only)** | Intercept `UnknownArgument` / `InvalidSubcommand` and rewrite | Works for any misguess, not just the 3 documented | Fragile to clap version bumps; large surface area; ships alongside D at most | Deferred — FR5 scope TBD during implementation |

---

## Security Considerations

- **URL parsing**: `--url` input is parsed via `url::Url::parse` before host extraction. No shell interpolation, no unescaped user input in CDP params. Host string becomes the cookie domain — the same surface that `--domain` already accepts.
- **No auth or permission change**: aliases do not grant access to any new behavior; they only accept a new spelling of existing inputs.
- **Input validation**: malformed URLs or URLs without a host component produce a structured JSON error with exit code 1. Error message explicitly names `--domain` as the alternative.

---

## Performance Considerations

- **Startup time**: adding hidden aliases is zero-cost at parse time. URL parsing runs only when `--url` is passed.
- **No CDP round-trips**: all alias handling is local to the CLI process; no change to the number of CDP messages per command.

---

## Testing Strategy

| Layer | Type | Coverage |
|-------|------|----------|
| CLI parsing | Unit (`cargo test --lib`) | `CookieSetArgs` parses `--url`, rejects `--url` + `--domain` combo; `TabsCloseArgs` parses `--tab` and combines with positional; `DomCommand` accepts `query` |
| Cookie set handler | Unit | `extract_host` returns expected host for common URL shapes; errors on malformed URL and on URL without host |
| Tabs close handler | BDD (cucumber) | `tabs close --tab <ID>` closes the right tab; `tabs close --tab A --tab B` closes both; missing-target case errors |
| Dom query alias | BDD | `dom query` produces same output as `dom select` for identical input |
| Help / capabilities / examples | BDD | `cookie set --help` does not contain `--url`; `tabs close --help` does not contain `--tab`; `dom --help` does not list `query`; `capabilities` JSON does not include alias names |
| Canonical regression | Existing BDD suites | Existing cookie/tabs/dom feature files continue to pass unchanged |
| Smoke test | Manual (per tech.md) | Exercise all 3 aliases against a real headless Chrome |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `--url` and `--domain` both passed, clap `conflicts_with` regresses on a future clap upgrade | Low | Medium | Redundant post-parse check in `execute_set` (belt + suspenders) |
| Hidden alias leaks into `capabilities` JSON via a future clap reflection change | Low | Medium | BDD test asserts aliases absent from capabilities manifest; regression-guarded |
| `dom query` collides with a future canonical `query` subcommand | Low | Low | Before adding any new `dom` subcommand, check this alias; documented in Change History |
| Users learn `--url` / `--tab` / `query` as canonical and rely on them | Medium | Low | Examples and capabilities continue to teach only canonical forms; aliases remain hidden |
| `tabs close` with neither positional nor `--tab` previously errored via clap `required = true`; dropping that requirement shifts the error to the handler | Low | Low | Post-parse check produces an equivalent structured error; BDD scenario covers it |

---

## Open Questions

- [ ] Should FR5 (custom error rewrite for related-but-unaliased flags like `--host`) ship in this release or defer? Current plan: implement for the 3 affected commands only if feasible within the task budget; otherwise ship FR1–FR4 and file a follow-up.
- [ ] Is it worth adding `--url` to `cookie delete` too, symmetrically? Not in scope for this issue — file a follow-up only if user feedback requests it.

---

## Change History

| Issue | Date | Summary |
|-------|------|---------|
| #230 | 2026-04-22 | Initial feature spec |

---

## Validation Checklist

- [x] Architecture follows existing project patterns (clap derive in `src/cli/mod.rs`, handlers in per-command modules)
- [x] All interface changes documented
- [x] Post-parse handler approach is clear for `--url` → `--domain` folding
- [x] Security considerations addressed (URL parsing, input validation)
- [x] Performance impact analyzed (zero-cost at parse)
- [x] Testing strategy defined
- [x] Alternatives were considered and documented
- [x] Risks identified with mitigations
