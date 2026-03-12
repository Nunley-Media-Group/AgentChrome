# File: tests/features/form-submit.feature
#
# Generated from: .claude/specs/feature-add-form-submit-subcommand-for-programmatic-form-submission/requirements.md
# Issue: #147

Feature: Form submit subcommand
  As an AI agent automating form-based workflows
  I want a form submit subcommand to programmatically submit a form
  So that I can trigger form submission without needing to locate and click a submit button

  # --- CLI Argument Validation (no Chrome required) ---

  Scenario: Submit help displays usage
    Given agentchrome is built
    When I run "agentchrome form submit --help"
    Then the exit code should be 0
    And stdout should contain "TARGET"
    And stdout should contain "--include-snapshot"

  Scenario: Submit without required target argument
    Given agentchrome is built
    When I run "agentchrome form submit"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Form help lists submit subcommand
    Given agentchrome is built
    When I run "agentchrome form --help"
    Then the exit code should be 0
    And stdout should contain "submit"

  # --- Chrome-Required Scenarios ---
  # These scenarios require a running Chrome instance with CDP enabled.
  # They are documented here for completeness but run only when integration
  # test infrastructure is available.

  # Scenario: Submit form by UID targeting the form element
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form element with UID "s3"
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit s3"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "s3"

  # Scenario: Submit form by CSS selector
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form with id "login-form"
  #   When I run "agentchrome form submit css:#login-form"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "css:#login-form"

  # Scenario: Submit element inside a form resolves parent form
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with an input inside a form
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <INPUT_UID>"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "<INPUT_UID>"

  # Scenario: Submit triggers navigation when form has action URL
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form that has an action URL
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <FORM_UID>"
  #   Then the exit code should be 0
  #   And the output JSON should contain "url"

  # Scenario: Submit non-navigating form
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form that submits via AJAX
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <FORM_UID>"
  #   Then the exit code should be 0
  #   And the output JSON "submitted" should be "<FORM_UID>"
  #   And the output JSON should not contain "url"

  # Scenario: Error when target is not a form or inside a form
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a standalone element not inside a form
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <NON_FORM_UID>"
  #   Then the exit code should be nonzero
  #   And stderr should contain "not a form"

  # Scenario: Include snapshot flag returns updated accessibility tree
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <FORM_UID> --include-snapshot"
  #   Then the exit code should be 0
  #   And the output JSON should contain a "snapshot" object

  # Scenario: Submit respects browser validation
  #   Given Chrome is running with CDP enabled
  #   And a page is loaded with a form containing a required field that is empty
  #   And an accessibility snapshot has been taken
  #   When I run "agentchrome form submit <FORM_UID>"
  #   Then the form submission is attempted via requestSubmit()
  #   And the browser's built-in validation prevents submission
