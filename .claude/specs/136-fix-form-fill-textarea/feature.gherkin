# File: tests/features/136-fix-form-fill-textarea.feature
#
# Generated from: .claude/specs/136-fix-form-fill-textarea/requirements.md
# Issue: #136
# Type: Defect regression

@regression
Feature: Form fill and clear work correctly on textarea elements
  The form fill and clear commands previously failed to set values on
  <textarea> elements because the JavaScript used HTMLInputElement's
  native value setter for all elements via an || short-circuit. This
  was fixed by selecting the correct prototype based on element tag name.

  Background:
    Given agentchrome is built

  # --- Bug Is Fixed ---

  # These scenarios require a running Chrome instance with CDP enabled.
  # They are documented here for completeness but run only when integration
  # test infrastructure is available.

  # @regression
  # Scenario: AC1 — form fill sets textarea value
  #   Given Chrome is running with CDP enabled
  #   And a page with a textarea element is loaded
  #   And an accessibility snapshot has been taken with UIDs assigned
  #   When I run "agentchrome form fill <textarea-uid> 'test value'"
  #   Then the exit code should be 0
  #   And the textarea's value should be "test value"

  # --- Related Behavior Still Works ---

  # @regression
  # Scenario: AC2 — form fill still works on input elements
  #   Given Chrome is running with CDP enabled
  #   And a page with an input element is loaded
  #   And an accessibility snapshot has been taken with UIDs assigned
  #   When I run "agentchrome form fill <input-uid> 'test value'"
  #   Then the exit code should be 0
  #   And the input's value should be "test value"

  # --- Clear Also Fixed ---

  # @regression
  # Scenario: AC3 — form clear works on textarea elements
  #   Given Chrome is running with CDP enabled
  #   And a page with a textarea element containing a value is loaded
  #   And an accessibility snapshot has been taken with UIDs assigned
  #   When I run "agentchrome form clear <textarea-uid>"
  #   Then the exit code should be 0
  #   And the textarea's value should be ""

  # --- Unit-level regression: FILL_JS selects correct prototype ---

  @regression
  Scenario: FILL_JS source contains tagName-based prototype selection
    Given agentchrome is built
    When I check the form fill JavaScript implementation
    Then it should select HTMLTextAreaElement prototype for textarea elements
    And it should select HTMLInputElement prototype for input elements

  @regression
  Scenario: CLEAR_JS source contains tagName-based prototype selection
    Given agentchrome is built
    When I check the form clear JavaScript implementation
    Then it should select HTMLTextAreaElement prototype for textarea elements
    And it should select HTMLInputElement prototype for input elements
