# File: tests/features/230-normalize-flag-shapes.feature
#
# Generated from: specs/feature-normalize-flag-shapes/requirements.md
# Issue: #230
#
# Scenarios here are CLI-only (parsing, help text, capabilities, examples,
# error shape). Chrome-dependent behavior (cookie set actually writing a
# cookie, tabs close actually closing a tab, dom query matching elements) is
# covered by unit tests in src/cli/mod.rs and src/cookie.rs, and by the manual
# smoke test per tech.md.

Feature: Normalize flag shapes across subcommands
  As a first-time user or AI agent extrapolating flag shapes from one
  agentchrome subcommand to another, I want hidden aliases that accept the
  natural guesses so I don't fail before discovering the canonical form.

  Background:
    Given agentchrome is built

  # --- AC6: Aliases are hidden from help, capabilities, and examples ---

  Scenario: cookie set --help does not mention the --url alias
    When I run "cookie set --help"
    Then the exit code should be 0
    And stdout should not contain "--url"
    And stdout should contain "--domain"

  Scenario: tabs close --help does not mention the --tab alias
    When I run "tabs close --help"
    Then the exit code should be 0
    And stdout should not contain "--tab <ID>"

  Scenario: dom --help does not list the query alias
    When I run "dom --help"
    Then the exit code should be 0
    And stdout should contain "select"
    And stdout should not contain "  query"

  Scenario: examples tabs output shows only canonical positional
    When I run "examples tabs"
    Then the exit code should be 0
    And stdout should not contain "--tab "

  Scenario: capabilities manifest does not list the aliases
    When I run "capabilities --json"
    Then the exit code should be 0
    And stdout should not contain "\"--url\""
    And stdout should not contain "\"query\""

  # --- AC7: Conflict between canonical and alias is rejected clearly ---

  Scenario: cookie set rejects --url and --domain together
    When I run "cookie set session_id abc123 --url https://example.com/ --domain other.com"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"

  # --- AC8: Unrelated wrong shapes still get errors ---

  Scenario: cookie set --host errors and exits nonzero
    When I run "cookie set n v --host example.com"
    Then the exit code should not be 0
    And stderr should be valid JSON

  Scenario: tabs close with neither positional nor --tab errors clearly
    When I run "tabs close"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr should contain "at least one target"
