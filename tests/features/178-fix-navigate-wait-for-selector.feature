# File: tests/features/178-fix-navigate-wait-for-selector.feature
#
# Generated from: specs/bug-navigate-returns-before-spa-email-list-renders/requirements.md
# Issue: #178
# Type: Defect regression

@regression
Feature: navigate --wait-for-selector blocks until CSS selector matches
  The navigate command previously returned as soon as Page.loadEventFired,
  which was insufficient for SPA sites where dynamic content renders after
  the load event. This was fixed by adding a --wait-for-selector flag that
  polls for a CSS selector after the primary wait strategy completes.

  # --- Bug Is Fixed ---

  @regression
  Scenario: navigate with --wait-for-selector waits for matching element
    Given a Chrome session is connected
    When I run navigate with --wait-for-selector ".login_logo" to "https://www.saucedemo.com/"
    Then the command should succeed with exit code 0
    And the JSON output should contain a "url" field
    And the JSON output should contain a "title" field

  # --- Related Behavior Still Works ---

  @regression
  Scenario: navigate without --wait-for-selector uses default load strategy
    Given a Chrome session is connected
    When I run navigate to "https://www.saucedemo.com/" without --wait-for-selector
    Then the command should succeed with exit code 0
    And the JSON output should contain a "url" field
    And the JSON output should contain a "title" field

  # --- Timeout Edge Case ---

  @regression
  Scenario: navigate with --wait-for-selector times out for missing selector
    Given a Chrome session is connected
    When I run navigate with --wait-for-selector ".nonexistent-element-xyz" and --timeout 2000 to "https://www.saucedemo.com/"
    Then the command should fail with exit code 4
    And the stderr should contain "timed out"
    And the stderr should contain ".nonexistent-element-xyz"
