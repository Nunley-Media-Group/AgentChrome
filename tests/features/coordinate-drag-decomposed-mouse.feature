# File: tests/features/coordinate-drag-decomposed-mouse.feature
#
# Generated from: specs/feature-add-coordinate-drag-and-decomposed-mouse-actions/requirements.md
# Issue: #194

Feature: Coordinate-based Drag and Decomposed Mouse Actions
  As a browser automation engineer
  I want coordinate-based drag commands and decomposed mouse actions
  So that I can automate drag-and-drop, long-press, and multi-step mouse interactions

  # --- CLI Argument Validation (no Chrome required) ---

  Scenario: Drag-at requires four coordinate arguments
    Given agentchrome is built
    When I run "agentchrome interact drag-at"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Drag-at rejects too few coordinate arguments
    Given agentchrome is built
    When I run "agentchrome interact drag-at 100 200"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Mousedown-at requires x and y arguments
    Given agentchrome is built
    When I run "agentchrome interact mousedown-at"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Mouseup-at requires x and y arguments
    Given agentchrome is built
    When I run "agentchrome interact mouseup-at"
    Then the exit code should be nonzero
    And stderr should contain "required"

  Scenario: Interact help displays new subcommands
    Given agentchrome is built
    When I run "agentchrome interact --help"
    Then the exit code should be 0
    And stdout should contain "drag-at"
    And stdout should contain "mousedown-at"
    And stdout should contain "mouseup-at"

  Scenario: Drag-at help displays all options
    Given agentchrome is built
    When I run "agentchrome interact drag-at --help"
    Then the exit code should be 0
    And stdout should contain "--steps"
    And stdout should contain "--include-snapshot"
    And stdout should contain "--compact"

  Scenario: Mousedown-at help displays button option
    Given agentchrome is built
    When I run "agentchrome interact mousedown-at --help"
    Then the exit code should be 0
    And stdout should contain "--button"
    And stdout should contain "--include-snapshot"

  Scenario: Mouseup-at help displays button option
    Given agentchrome is built
    When I run "agentchrome interact mouseup-at --help"
    Then the exit code should be 0
    And stdout should contain "--button"
    And stdout should contain "--include-snapshot"

  Scenario: Examples include new commands
    Given agentchrome is built
    When I run "agentchrome examples interact"
    Then the exit code should be 0
    And stdout should contain "drag-at"
    And stdout should contain "mousedown-at"
    And stdout should contain "mouseup-at"

  # --- Happy Path (require Chrome) ---

  # AC1: Coordinate-based drag
  Scenario: Drag at viewport coordinates
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact drag-at 100 200 300 400"
    Then the exit code should be 0
    And the JSON output should have "dragged_at.from.x" equal to 100.0
    And the JSON output should have "dragged_at.from.y" equal to 200.0
    And the JSON output should have "dragged_at.to.x" equal to 300.0
    And the JSON output should have "dragged_at.to.y" equal to 400.0

  # AC2: Decomposed mousedown
  Scenario: Mousedown at viewport coordinates
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mousedown-at 150 250"
    Then the exit code should be 0
    And the JSON output should have "mousedown_at.x" equal to 150.0
    And the JSON output should have "mousedown_at.y" equal to 250.0

  # AC3: Decomposed mouseup
  Scenario: Mouseup at viewport coordinates
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mouseup-at 300 400"
    Then the exit code should be 0
    And the JSON output should have "mouseup_at.x" equal to 300.0
    And the JSON output should have "mouseup_at.y" equal to 400.0

  # AC4: Decomposed multi-invocation drag sequence
  Scenario: Mousedown followed by mouseup in separate invocations
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mousedown-at 100 200"
    Then the exit code should be 0
    When I run "agentchrome interact mouseup-at 300 400"
    Then the exit code should be 0

  # AC5: Frame-scoped dispatch for drag-at
  Scenario: Drag at coordinates inside an iframe
    Given Chrome is running with CDP enabled
    And a page is loaded with iframes
    When I run "agentchrome interact --frame 1 drag-at 50 60 200 300"
    Then the exit code should be 0

  # AC6: Frame-scoped dispatch for mousedown-at
  Scenario: Mousedown at coordinates inside an iframe
    Given Chrome is running with CDP enabled
    And a page is loaded with iframes
    When I run "agentchrome interact --frame 1 mousedown-at 50 60"
    Then the exit code should be 0

  # AC7: Frame-scoped dispatch for mouseup-at
  Scenario: Mouseup at coordinates inside an iframe
    Given Chrome is running with CDP enabled
    And a page is loaded with iframes
    When I run "agentchrome interact --frame 1 mouseup-at 50 60"
    Then the exit code should be 0

  # AC8: Optional drag steps for interpolated movement
  Scenario: Drag at coordinates with interpolated steps
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact drag-at 0 0 100 100 --steps 5"
    Then the exit code should be 0
    And the JSON output should have "steps" equal to 5

  # AC9: Drag-at default single-step movement
  Scenario: Drag at coordinates with default single step
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact drag-at 0 0 100 100"
    Then the exit code should be 0
    And the JSON output should not have "steps"

  # AC10: Button option on mousedown-at
  Scenario: Mousedown with right button
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mousedown-at 100 200 --button right"
    Then the exit code should be 0
    And the JSON output should have "button" equal to "right"

  # AC11: Button option on mouseup-at
  Scenario: Mouseup with right button
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mouseup-at 100 200 --button right"
    Then the exit code should be 0
    And the JSON output should have "button" equal to "right"

  # AC12: Plain text output for drag-at
  Scenario: Drag at coordinates with plain text output
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome --plain interact drag-at 100 200 300 400"
    Then the exit code should be 0
    And stdout should contain "Dragged from (100, 200) to (300, 400)"

  # AC13: Plain text output for mousedown-at
  Scenario: Mousedown at coordinates with plain text output
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome --plain interact mousedown-at 100 200"
    Then the exit code should be 0
    And stdout should contain "Mousedown at (100, 200)"

  # AC14: Plain text output for mouseup-at
  Scenario: Mouseup at coordinates with plain text output
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome --plain interact mouseup-at 100 200"
    Then the exit code should be 0
    And stdout should contain "Mouseup at (100, 200)"

  # AC15: Include-snapshot on drag-at
  Scenario: Drag at coordinates with include-snapshot
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact drag-at 100 200 300 400 --include-snapshot"
    Then the exit code should be 0
    And the JSON output should have a "snapshot" field

  # AC16: Include-snapshot on mousedown-at
  Scenario: Mousedown at coordinates with include-snapshot
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mousedown-at 100 200 --include-snapshot"
    Then the exit code should be 0
    And the JSON output should have a "snapshot" field

  # AC17: Include-snapshot on mouseup-at
  Scenario: Mouseup at coordinates with include-snapshot
    Given Chrome is running with CDP enabled
    And a page is loaded with interactive elements
    When I run "agentchrome interact mouseup-at 100 200 --include-snapshot"
    Then the exit code should be 0
    And the JSON output should have a "snapshot" field
