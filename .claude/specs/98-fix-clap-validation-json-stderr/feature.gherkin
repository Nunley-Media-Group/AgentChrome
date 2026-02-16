# File: tests/features/98-fix-clap-validation-json-stderr.feature
#
# Generated from: .claude/specs/98-fix-clap-validation-json-stderr/requirements.md
# Issue: #98
# Type: Defect regression

@regression
Feature: Clap validation errors produce JSON on stderr with exit code 1
  The CLI previously emitted clap's default plain-text error messages on stderr
  and used exit code 2 (connection error) for argument validation failures.
  This was fixed by intercepting clap errors via try_parse() and formatting
  them as JSON through the standard AppError path.

  # --- Bug Is Fixed ---

  @regression
  Scenario: Mutually exclusive flags produce JSON error
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --to-top --to-bottom"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"
    And stderr JSON should have key "code"

  @regression
  Scenario: Invalid enum value produces JSON error
    Given chrome-cli is built
    When I run "chrome-cli emulate set --network invalid-profile"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"
    And stderr JSON should have key "code"

  @regression
  Scenario: Out-of-range value produces JSON error
    Given chrome-cli is built
    When I run "chrome-cli emulate set --cpu 0"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"
    And stderr JSON should have key "code"

  # --- Related Behavior Still Works ---

  @regression
  Scenario: Non-clap application errors still produce JSON on stderr
    Given chrome-cli is built
    When I run "chrome-cli dom"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"
    And stderr JSON should have key "code"

  @regression
  Scenario: Help flag still works normally
    Given chrome-cli is built
    When I run "chrome-cli --help"
    Then the exit code should be 0
    And stdout should contain "chrome-cli"

  @regression
  Scenario: Version flag still works normally
    Given chrome-cli is built
    When I run "chrome-cli --version"
    Then the exit code should be 0
    And stdout should contain "chrome-cli"
