# File: tests/features/74-fix-emulate-status-inaccurate-state.feature
#
# Generated from: .claude/specs/74-fix-emulate-status-inaccurate-state/requirements.md
# Issue: #74
# Type: Defect regression

@regression
Feature: emulate status reports accurate emulation state
  The `emulate status` command previously hardcoded `mobile: false`,
  `network: None`, and `cpu: None` regardless of actual emulation state.
  This was fixed by persisting emulation state to a file when `emulate set`
  applies CDP overrides, and reading it back in `emulate status`.

  # --- Bug Is Fixed: Mobile ---

  @regression
  Scenario: emulate status reports mobile true after enabling mobile emulation
    Given a Chrome session is connected
    And mobile emulation is enabled via "emulate set --viewport 375x667 --mobile"
    When I run "emulate status --json"
    Then the JSON output field "mobile" is true

  # --- Bug Is Fixed: Network ---

  @regression
  Scenario: emulate status reports network throttling after enabling it
    Given a Chrome session is connected
    And network throttling is enabled via "emulate set --network slow4g"
    When I run "emulate status --json"
    Then the JSON output field "network" is "Slow 4G"

  # --- Bug Is Fixed: CPU ---

  @regression
  Scenario: emulate status reports CPU throttling after enabling it
    Given a Chrome session is connected
    And CPU throttling is enabled via "emulate set --cpu 4"
    When I run "emulate status --json"
    Then the JSON output field "cpu" is 4

  # --- Related Behavior Still Works ---

  @regression
  Scenario: emulate status still reports viewport user agent and color scheme
    Given a Chrome session is connected
    And emulation overrides are applied via "emulate set --viewport 1024x768 --user-agent 'TestAgent' --color-scheme dark"
    When I run "emulate status --json"
    Then the JSON output field "viewport.width" is 1024
    And the JSON output field "viewport.height" is 768
    And the JSON output field "userAgent" contains "TestAgent"
    And the JSON output field "colorScheme" is "dark"

  # --- Defaults After Reset ---

  @regression
  Scenario: emulate status reports defaults after emulate reset
    Given a Chrome session is connected
    And emulation overrides are applied via "emulate set --viewport 375x667 --mobile --network slow4g --cpu 4"
    And emulation is reset via "emulate reset"
    When I run "emulate status --json"
    Then the JSON output field "mobile" is false
    And the JSON output does not contain field "network"
    And the JSON output does not contain field "cpu"
