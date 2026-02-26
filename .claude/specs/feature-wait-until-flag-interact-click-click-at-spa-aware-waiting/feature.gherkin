# File: tests/features/wait-until-click.feature
#
# Generated from: .claude/specs/feature-wait-until-flag-interact-click-click-at-spa-aware-waiting/requirements.md
# Issue: #148

Feature: Wait-until flag for interact click commands
  As a AI agent or automation engineer
  I want to wait for page content to settle after clicking an element that triggers SPA navigation
  So that I can reliably read the updated page content without race conditions or arbitrary sleeps

  # --- CLI Argument Validation (no Chrome required) ---

  Scenario: Click help displays wait-until option
    Given agentchrome is built
    When I run "agentchrome interact click --help"
    Then the exit code should be 0
    And stdout should contain "--wait-until"

  Scenario: Click-at help displays wait-until option
    Given agentchrome is built
    When I run "agentchrome interact click-at --help"
    Then the exit code should be 0
    And stdout should contain "--wait-until"

  Scenario: Click accepts valid wait-until values
    Given agentchrome is built
    When I run "agentchrome interact click s1 --wait-until networkidle"
    Then stderr should not contain "invalid value"

  Scenario: Click rejects invalid wait-until values
    Given agentchrome is built
    When I run "agentchrome interact click s1 --wait-until invalid"
    Then the exit code should be nonzero
    And stderr should contain "invalid value"

  # --- Happy Path ---

  # AC1: Click with wait-until networkidle on SPA page
  Scenario: Click with wait-until networkidle waits for network idle
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    And a snapshot has been taken with UIDs assigned
    And the page has a link with UID "s1" that triggers network activity
    When I run "agentchrome interact click s1 --wait-until networkidle"
    Then the output JSON should contain "navigated"
    And the output JSON should contain "url"
    And the exit code should be 0

  # --- Alternative Paths ---

  # AC2: Click with wait-until load on full-page navigation
  Scenario: Click with wait-until load waits for load event
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    And a snapshot has been taken with UIDs assigned
    And the page has a link with UID "s1" that navigates to "/about"
    When I run "agentchrome interact click s1 --wait-until load"
    Then the output JSON should contain "navigated" equal to true
    And the output JSON "url" should contain "/about"
    And the exit code should be 0

  # AC3: Click-at with wait-until networkidle
  Scenario: Click-at with wait-until networkidle waits for network idle
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact click-at 100 200 --wait-until networkidle"
    Then the output JSON should contain "clicked_at"
    And the exit code should be 0

  # --- Backward Compatibility ---

  # AC4: Click without wait-until preserves existing behavior
  Scenario: Click without wait-until uses legacy grace period
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    And a snapshot has been taken with UIDs assigned
    And the page has a button with snapshot UID "s1"
    When I run "agentchrome interact click s1"
    Then the output JSON should contain "clicked" equal to "s1"
    And the output JSON should contain "navigated" equal to false
    And the output JSON should contain "url"
    And the exit code should be 0

  Scenario: Click-at without wait-until uses legacy behavior
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact click-at 100 200"
    Then the output JSON "clicked_at.x" should be 100
    And the output JSON "clicked_at.y" should be 200
    And the output JSON should not contain "navigated"
    And the output JSON should not contain "url"
    And the exit code should be 0

  # --- Error Handling ---

  # AC5: Click with wait-until times out
  Scenario: Click with wait-until timeout exits with code 4
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    And a snapshot has been taken with UIDs assigned
    And the page has a button with snapshot UID "s1" that triggers continuous network activity
    When I run "agentchrome interact click s1 --wait-until networkidle --timeout 1000"
    Then the exit code should be 4
    And stderr should contain "timeout"

  # --- Cross-command State Visibility ---

  # AC6: Page state visible to subsequent commands after wait
  Scenario: Page snapshot after click with wait-until reflects updated content
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    And a snapshot has been taken with UIDs assigned
    And the page has a link with UID "s1" that navigates to "/about"
    When I run "agentchrome interact click s1 --wait-until load"
    And I run "agentchrome page snapshot"
    Then the snapshot should contain elements from the new page
    And the exit code should be 0
