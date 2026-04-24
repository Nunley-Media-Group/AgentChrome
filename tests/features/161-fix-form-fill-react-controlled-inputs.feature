# File: tests/features/161-fix-form-fill-react-controlled-inputs.feature
#
# Generated from: specs/bug-fix-form-fill-react-controlled-inputs/requirements.md
# Issue: #161
# Type: Defect regression

@regression
Feature: Form fill on React-controlled inputs
  The form fill command previously set values using native JavaScript setters
  which bypassed React's fiber reconciliation, causing values to silently reset.
  Additionally, DOM.resolveNode calls invalidated cached accessibility tree node IDs.
  This was fixed by using CDP keyboard simulation for text-type inputs.

  Background:
    Given agentchrome is built

  # --- Chrome-dependent scenarios (documented for completeness) ---

  # @regression
  # Scenario: AC1 — Form fill sets value on React-controlled inputs
  #   Given a connected Chrome session
  #   And a React-based page with controlled input elements is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill on a text input UID with value "standard_user"
  #   Then the DOM value of the input is "standard_user"
  #   And js exec verification confirms the value is "standard_user"

  # @regression
  # Scenario: AC2 — Form fill does not invalidate node references
  #   Given a connected Chrome session
  #   And a page with form elements is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill on a text input UID with value "test_value"
  #   Then a subsequent interact click on the same UID succeeds
  #   And a subsequent interact click on a different UID from the same snapshot succeeds

  # @regression
  # Scenario: AC3 — Form fill still works on vanilla HTML inputs
  #   Given a connected Chrome session
  #   And a page with standard HTML input elements is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill on a text input UID with value "vanilla_value"
  #   Then the DOM value of the input is "vanilla_value"
  #   And js exec verification confirms the value is "vanilla_value"

  # @regression
  # Scenario: AC4 — Form fill still works on select elements
  #   Given a connected Chrome session
  #   And a page with a select dropdown is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill on the select UID with value matching an option
  #   Then the select element's selected option matches the filled value

  # @regression
  # Scenario: AC5 — Form fill still works on textarea elements
  #   Given a connected Chrome session
  #   And a page with a textarea element is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill on the textarea UID with value "multiline text"
  #   Then the DOM value of the textarea is "multiline text"
  #   And js exec verification confirms the value is "multiline text"

  # @regression
  # Scenario: AC6 — Form fill-many inherits the fix for React inputs
  #   Given a connected Chrome session
  #   And a React-based page with multiple controlled input elements is loaded
  #   And an accessibility snapshot has been taken
  #   When I run form fill-many with entries for two text input UIDs
  #   Then both fields have their values set correctly
  #   And js exec verification confirms both values

  # @regression
  # Scenario: AC7 — Form clear still works on text inputs
  #   Given a connected Chrome session
  #   And a page with a text input that has a value set
  #   And an accessibility snapshot has been taken
  #   When I run form clear on the text input UID
  #   Then the DOM value of the input is ""
  #   And js exec verification confirms the value is empty

  # --- Source-level regression tests (no Chrome required) ---

  @regression
  Scenario: fill_element uses describe_element to branch on element type
    Given agentchrome is built
    When I check the fill_element implementation
    Then it should call describe_element to detect element type
    And it should call is_text_input to classify the element
    And it should call fill_element_keyboard for text inputs

  @regression
  Scenario: clear_element uses describe_element to branch on element type
    Given agentchrome is built
    When I check the clear_element implementation
    Then it should call describe_element to detect element type
    And it should call is_text_input to classify the element
    And it should call clear_element_keyboard for text inputs

  @regression
  Scenario: fill_element_keyboard uses DOM.focus and Input.dispatchKeyEvent
    Given agentchrome is built
    When I check the fill_element_keyboard implementation
    Then it should call DOM.focus to focus the element
    And it should select all text using activeElement.select()
    And it should dispatch char key events to type the value

  @regression
  Scenario: clear_element_keyboard uses DOM.focus and React-compatible InputEvent
    Given agentchrome is built
    When I check the clear_element_keyboard implementation
    Then it should call DOM.focus to focus the element
    And it should clear using React-compatible InputEvent
