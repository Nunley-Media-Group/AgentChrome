# File: tests/features/dom-tree-positional-root.feature
#
# Generated from: specs/bug-fix-dom-tree-add-positional-root-argument-consistent-with-other-dom-subcommands/requirements.md
# Issue: #251
# Type: Defect regression
#
# AC1 and AC2 assert runtime output against a live Chrome/page fixture and are
# verified via the manual smoke test in T003's Feature Exercise Gate. The
# CLI-only half of AC1 (clap no longer rejects the positional) is covered by
# the "positional parses" scenario below — that is the direct bug regression.

@regression
Feature: dom tree accepts a positional ROOT argument
  The `dom tree` subcommand previously rejected positional target arguments
  (`agentchrome dom tree css:table` -> "unexpected argument"), diverging from
  every sibling `dom` subcommand. This was fixed by adding an optional
  positional `ROOT` to `DomTreeArgs` that shares semantics with `--root` and
  conflicts with it via clap's `conflicts_with`.

  # --- AC1 (CLI half): the positional no longer trips clap ---

  @regression
  Scenario: AC1 — positional ROOT parses without a clap error
    Given agentchrome is built
    When I run "agentchrome dom tree css:table --depth 3"
    Then stderr should not contain "unexpected argument"

  # --- AC4: mutual exclusion via clap's conflicts_with ---

  @regression
  Scenario: AC4 — positional and --root together produce a conflict error
    Given agentchrome is built
    When I run "agentchrome dom tree css:table --root css:div"
    Then the exit code should not be 0
    And stderr should be valid JSON
    And stderr should contain "--root"
    And stderr should contain "cannot be used with"

  # --- AC5: help text advertises the positional ---

  @regression
  Scenario: AC5 — help text advertises the positional in the usage line
    Given agentchrome is built
    When I run "agentchrome dom tree --help"
    Then the exit code should be 0
    And stdout should contain "[ROOT]"

  @regression
  Scenario: AC5 — help text includes a positional-form EXAMPLES entry
    Given agentchrome is built
    When I run "agentchrome dom tree --help"
    Then the exit code should be 0
    And stdout should contain "dom tree css:div.content"
