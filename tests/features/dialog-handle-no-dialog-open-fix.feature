# File: tests/features/dialog-handle-no-dialog-open-fix.feature
#
# Generated from: .claude/specs/99-fix-dialog-handle-no-dialog-open/requirements.md
# Issue: #99
# Type: Defect regression

@regression
Feature: Dialog handle and info work for pre-existing dialogs
  The dialog info command previously reported type "unknown" and message ""
  for dialogs that were already open, and dialog handle failed with
  "No dialog is currently open" because each CLI invocation creates a new
  CDP session that never received the Page.javascriptDialogOpening event.
  This was fixed by sending Page.enable with a timeout during dialog session
  setup, triggering Chrome to re-emit the dialog event to the new session.

  Background:
    Given chrome-cli is built

  # --- Bug Is Fixed ---

  @regression
  Scenario: AC1 — dialog info reports correct type and message for pre-existing alert
    Given a page has triggered an alert dialog with message "test alert"
    When I run "chrome-cli dialog info"
    Then the output JSON should contain "open" equal to true
    And the output JSON should contain "type" equal to "alert"
    And the output JSON should contain "message" equal to "test alert"
    And the exit code should be 0

  @regression
  Scenario: AC2 — dialog handle accept dismisses pre-existing alert
    Given a page has triggered an alert dialog with message "test alert"
    When I run "chrome-cli dialog handle accept"
    Then the output JSON should contain "action" equal to "accept"
    And the output JSON should contain "dialog_type" equal to "alert"
    And the output JSON should contain "message" equal to "test alert"
    And the exit code should be 0

  @regression
  Scenario: AC3 — dialog handle dismiss works for pre-existing confirm
    Given a page has triggered a confirm dialog with message "sure?"
    When I run "chrome-cli dialog handle dismiss"
    Then the output JSON should contain "action" equal to "dismiss"
    And the output JSON should contain "dialog_type" equal to "confirm"
    And the output JSON should contain "message" equal to "sure?"
    And the exit code should be 0

  @regression
  Scenario: AC4 — auto-dismiss-dialogs clears pre-existing blocking dialog
    Given a page has triggered an alert dialog with message "blocking"
    When I run "chrome-cli navigate https://www.google.com --auto-dismiss-dialogs --wait-until load"
    Then the exit code should be 0

  @regression
  Scenario: AC5 — dialog handle accept with text works for pre-existing prompt
    Given a page has triggered a prompt dialog with message "name?"
    When I run "chrome-cli dialog handle accept --text Alice"
    Then the output JSON should contain "action" equal to "accept"
    And the output JSON should contain "dialog_type" equal to "prompt"
    And the output JSON should contain "text" equal to "Alice"
    And the exit code should be 0

  # --- Related Behavior Still Works ---

  @regression
  Scenario: dialog info still reports no dialog when none is open
    Given no dialog is currently open
    When I run "chrome-cli dialog info"
    Then the output JSON should contain "open" equal to false
    And the exit code should be 0

  @regression
  Scenario: dialog handle still errors when no dialog is open
    Given no dialog is currently open
    When I run "chrome-cli dialog handle accept"
    Then the exit code should be non-zero
    And stderr should contain an error about no dialog being open
