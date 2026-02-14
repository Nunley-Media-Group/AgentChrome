# File: tests/features/scroll.feature
#
# Generated from: .claude/specs/17-scroll-interactions/requirements.md
# Issue: #17

Feature: Scroll Interactions
  As a developer or automation engineer
  I want to scroll pages and scroll to specific elements via the CLI
  So that I can interact with content below the fold and automate full-page workflows

  # --- CLI Argument Validation (no Chrome required) ---

  Scenario: Scroll accepts no mandatory arguments
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --help"
    Then the exit code should be 0
    And stdout should contain "--direction"
    And stdout should contain "--amount"
    And stdout should contain "--to-element"
    And stdout should contain "--to-top"
    And stdout should contain "--to-bottom"
    And stdout should contain "--smooth"
    And stdout should contain "--container"
    And stdout should contain "--include-snapshot"

  Scenario: Interact help lists scroll subcommand
    Given chrome-cli is built
    When I run "chrome-cli interact --help"
    Then the exit code should be 0
    And stdout should contain "scroll"

  Scenario: Conflicting flags --to-top and --to-bottom
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --to-top --to-bottom"
    Then the exit code should be nonzero
    And stderr should contain "cannot be used with"

  Scenario: Conflicting flags --to-top and --direction
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --to-top --direction up"
    Then the exit code should be nonzero
    And stderr should contain "cannot be used with"

  Scenario: Conflicting flags --to-element and --to-top
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --to-element s1 --to-top"
    Then the exit code should be nonzero
    And stderr should contain "cannot be used with"

  Scenario: Conflicting flags --to-element and --amount
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --to-element s1 --amount 300"
    Then the exit code should be nonzero
    And stderr should contain "cannot be used with"

  Scenario: Invalid direction value
    Given chrome-cli is built
    When I run "chrome-cli interact scroll --direction diagonal"
    Then the exit code should be nonzero
    And stderr should contain "invalid value"

  # --- Default Scroll (require Chrome) ---

  Scenario: Scroll down by default
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the output JSON "scrolled.y" should be greater than 0
    And the exit code should be 0

  # --- Directional Scroll ---

  Scenario Outline: Scroll in a specified direction
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --direction <direction>"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

    Examples:
      | direction |
      | down      |
      | up        |
      | left      |
      | right     |

  # --- Pixel Amount ---

  Scenario: Scroll by a specific pixel amount
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --amount 300"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

  Scenario: Scroll horizontally by pixel amount
    Given Chrome is running with CDP enabled
    And a page is loaded with wide scrollable content
    When I run "chrome-cli interact scroll --direction right --amount 200"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

  # --- Absolute Scroll ---

  Scenario: Scroll to top of page
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And the page is scrolled partway down
    When I run "chrome-cli interact scroll --to-top"
    Then the output JSON "position.x" should be 0
    And the output JSON "position.y" should be 0
    And the exit code should be 0

  Scenario: Scroll to bottom of page
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --to-bottom"
    Then the output JSON should contain "position"
    And the output JSON "position.y" should be greater than 0
    And the exit code should be 0

  # --- Element Scroll ---

  Scenario: Scroll to a specific element by UID
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And a snapshot has been taken with UIDs assigned
    And the page has an element with UID "s5" below the fold
    When I run "chrome-cli interact scroll --to-element s5"
    Then the output JSON should contain "position"
    And the exit code should be 0

  Scenario: Scroll to a specific element by CSS selector
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And the page has an element matching "css:#footer"
    When I run "chrome-cli interact scroll --to-element css:#footer"
    Then the output JSON should contain "position"
    And the exit code should be 0

  # --- Smooth Scroll ---

  Scenario: Scroll with smooth behavior
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --smooth --amount 500"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

  # --- Container Scroll ---

  Scenario: Scroll within a container element by UID
    Given Chrome is running with CDP enabled
    And a page is loaded with a scrollable container
    And a snapshot has been taken with UIDs assigned
    And the page has a scrollable container with UID "s3"
    When I run "chrome-cli interact scroll --container s3 --amount 200"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain "position"
    And the exit code should be 0

  # --- Tab Targeting ---

  Scenario: Scroll targeting a specific tab
    Given Chrome is running with CDP enabled
    And multiple tabs are open
    When I run "chrome-cli interact scroll --tab 1"
    Then the output JSON should contain "scrolled"
    And the exit code should be 0

  # --- Snapshot ---

  Scenario: Include snapshot after scroll
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --include-snapshot"
    Then the output JSON should contain "scrolled"
    And the output JSON should contain a "snapshot" field
    And the snapshot should be a valid accessibility tree
    And the exit code should be 0

  # --- Error Handling ---

  Scenario: Scroll to nonexistent UID errors
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And a snapshot has been taken with UIDs assigned
    And no element matches UID "s999" in the snapshot state
    When I run "chrome-cli interact scroll --to-element s999"
    Then stderr should contain "UID 's999' not found"
    And stderr should contain "page snapshot"
    And the exit code should be nonzero

  Scenario: Scroll to element with no snapshot state errors
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And no snapshot has been taken
    When I run "chrome-cli interact scroll --to-element s1"
    Then stderr should contain "No snapshot state found"
    And stderr should contain "page snapshot"
    And the exit code should be nonzero

  Scenario: Scroll to nonexistent CSS selector errors
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --to-element css:#nonexistent-element"
    Then stderr should contain "Element not found"
    And the exit code should be nonzero

  # --- Plain Text Output ---

  Scenario: Plain text output for scroll
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    When I run "chrome-cli interact scroll --plain"
    Then the output should be plain text containing "Scrolled"
    And the exit code should be 0

  Scenario: Plain text output for scroll to top
    Given Chrome is running with CDP enabled
    And a page is loaded with scrollable content
    And the page is scrolled partway down
    When I run "chrome-cli interact scroll --to-top --plain"
    Then the output should be plain text containing "Scrolled to top"
    And the exit code should be 0
