# File: tests/features/144-fix-spa-same-document-navigate-timeout.feature
#
# Generated from: .claude/specs/144-fix-spa-same-document-navigate-timeout/requirements.md
# Issue: #144
# Type: Defect regression

@regression
Feature: Navigate back/forward works for SPA same-document history navigations
  The navigate back and navigate forward commands previously timed out when
  navigating through history entries created by SPA client-side routing
  (pushState). This was fixed by subscribing to both Page.frameNavigated
  and Page.navigatedWithinDocument CDP events.

  Background:
    Given chrome-cli is built

  # --- Bug Is Fixed ---

  @regression
  Scenario: AC1 — SPA same-document navigate back succeeds
    Given a tab has navigated through multiple SPA pages via pushState routing
    When I run "chrome-cli navigate back"
    Then the exit code should be 0
    And the JSON output has key "url" containing the previous page URL
    And the JSON output has key "title"

  @regression
  Scenario: AC2 — SPA same-document navigate forward succeeds
    Given a tab has navigated through SPA pages and then navigated back
    When I run "chrome-cli navigate forward"
    Then the exit code should be 0
    And the JSON output has key "url" containing the forward destination URL
    And the JSON output has key "title"

  # --- No Regression ---

  @regression
  Scenario: AC3 — Cross-document navigate back still works
    Given a tab has navigated between two pages via full page loads
    When I run "chrome-cli navigate back"
    Then the exit code should be 0
    And the JSON output has key "url" containing the previous page URL
    And the JSON output has key "title"

  @regression
  Scenario: AC4 — Cross-origin navigate back still works
    Given a tab has navigated across origins via full page loads
    When I run "chrome-cli navigate back"
    Then the exit code should be 0
    And the JSON output has key "url" containing the previous origin URL
    And the JSON output has key "title"
