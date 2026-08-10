# File: tests/features/290-fix-console-read-missing-uncaught-page-exceptions.feature
#
# Generated from: specs/bug-fix-console-read-missing-uncaught-page-exceptions/requirements.md
# Issue: #290
# Type: Defect regression

@regression
Feature: console read includes uncaught page exceptions
  The `console read --errors-only` command previously returned explicit
  `console.error(...)` messages but omitted uncaught page exceptions delivered
  through `Runtime.exceptionThrown`. This was fixed by collecting exception
  events and normalizing them into the existing console read output contract.

  Background:
    Given Chrome is running with CDP enabled

  # --- Bug Is Fixed ---

  @regression @requires-chrome
  Scenario: Uncaught exceptions appear in errors-only console reads
    Given a page logs an explicit console error and throws an uncaught TypeError
    When I run "agentchrome console read --errors-only"
    Then the output is a JSON array
    And the array contains an error entry for the explicit console error
    And the array contains an error entry for the uncaught TypeError
    And each error entry contains "type", "text", "timestamp", "url", "line", and "column"

  # --- Related Behavior Still Works ---

  @regression @requires-chrome
  Scenario: Existing console filters and pagination still work
    Given a page has generated log, warn, explicit error, and uncaught exception events
    When I run "agentchrome console read --errors-only"
    Then every returned entry has type "error"
    And the output includes the uncaught exception entry
    When I run "agentchrome console read --type warn"
    Then every returned entry has type "warn"
    When I run "agentchrome console read --limit 2"
    Then the output contains at most 2 entries

  # --- Detail Mode ---

  @regression @requires-chrome
  Scenario: Detail mode includes exception source context
    Given "agentchrome console read --errors-only" returned an uncaught exception entry with an id
    When I run "agentchrome console read <id>" for that exception id
    Then the detail output contains the uncaught TypeError text
    And the detail output includes stack trace frames when Chrome provides them
