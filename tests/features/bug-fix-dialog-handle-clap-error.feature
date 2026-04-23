# File: tests/features/bug-fix-dialog-handle-clap-error.feature
#
# Generated from: specs/bug-fix-dialog-handle-clap-error/requirements.md
# Issue: #250
# Type: Defect regression

@regression
Feature: dialog handle rejects --accept/--dismiss with a corrected hint
  The `agentchrome dialog handle` command takes an `<ACTION>` positional
  (`accept` | `dismiss`). Previously, invoking it with `--accept` or `--dismiss`
  as a long flag produced clap's generic tip suggesting `-- --accept`, which is
  also invalid. The fix extends `syntax_hint` in `src/main.rs` to recognize
  these flags on the `dialog handle` subcommand and emit
  `Did you mean: agentchrome dialog handle <action>`.

  # --- Bug Is Fixed ---

  @regression
  Scenario: --accept flag yields a corrected positional hint
    Given agentchrome is built
    When I run "agentchrome dialog handle --accept"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr should contain "Did you mean: agentchrome dialog handle accept"

  @regression
  Scenario: --dismiss flag yields a corrected positional hint
    Given agentchrome is built
    When I run "agentchrome dialog handle --dismiss"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr should contain "Did you mean: agentchrome dialog handle dismiss"

  # --- Related Behavior Still Works ---

  @regression
  Scenario: valid positional usage parses successfully (no clap error)
    Given agentchrome is built
    When I run "agentchrome dialog handle accept"
    Then stderr should not contain "Did you mean"
    And stderr should not contain "unexpected argument"
