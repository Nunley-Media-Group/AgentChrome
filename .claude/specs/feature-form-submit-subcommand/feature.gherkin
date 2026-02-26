# File: tests/features/form-submit.feature
#
# Generated from: .claude/specs/feature-form-submit-subcommand/requirements.md
# Issue: #147

Feature: Form submit subcommand
  As an AI agent automating form-based workflows
  I want a form submit subcommand to programmatically submit a form
  So that I can trigger form submission without needing to locate and click a submit button

  # --- CLI Argument Validation (no Chrome required) ---

  Scenario: Submit requires a target argument
    Given agentchrome is built
    When I run "agentchrome form submit"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Submit help displays usage information
    Given agentchrome is built
    When I run "agentchrome form submit --help"
    Then the exit code should be 0
    And stdout should contain "TARGET"
    And stdout should contain "--include-snapshot"

  Scenario: Form help lists submit subcommand
    Given agentchrome is built
    When I run "agentchrome form --help"
    Then the exit code should be 0
    And stdout should contain "submit"

  # --- Chrome-Required Scenarios ---
  # These scenarios require a running Chrome instance with CDP enabled.
  # They are documented here for completeness but run only when integration
  # test infrastructure is available.

  # Scenario: Submit form by targeting the form element directly
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form element with UID "s3"
  #   When I run "agentchrome form submit s3"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "s3"

  # Scenario: Submit form by targeting an element within the form
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with an input field inside a form
  #   And the input field has UID "s5"
  #   When I run "agentchrome form submit s5"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "s5"

  # Scenario: Submit form by CSS selector
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form with id "login-form"
  #   When I run "agentchrome form submit css:#login-form"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "css:#login-form"

  # Scenario: Submit triggers navigation when form has action attribute
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form that has an action attribute
  #   When I run "agentchrome form submit s3"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "s3"
  #   And the output JSON should contain a "url" field

  # Scenario: Submit with --include-snapshot flag
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form element
  #   When I run "agentchrome form submit s3 --include-snapshot"
  #   Then the exit code should be 0
  #   And the output JSON should contain a "snapshot" object

  # Scenario: Error when target is not a form and not inside a form
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a standalone element not inside any form
  #   When I run "agentchrome form submit s10"
  #   Then the exit code should be nonzero
  #   And stderr should contain "No form found"

  # Scenario: Error when target element does not exist
  #   Given Chrome is running with CDP enabled
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit s999"
  #   Then the exit code should be nonzero
  #   And stderr should contain "UID"

  # Scenario: Submit cross-validates via independent read after navigation
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form that navigates to /dashboard on submit
  #   When I run "agentchrome form submit s3"
  #   And I subsequently run "agentchrome navigate current"
  #   Then the URL should contain "/dashboard"
