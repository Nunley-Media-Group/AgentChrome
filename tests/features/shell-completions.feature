# File: tests/features/shell-completions.feature
#
# Generated from: .claude/specs/25-shell-completions-generation/requirements.md
# Issue: #25

Feature: Shell completions generation
  As a developer or automation engineer using agentchrome
  I want tab-completion for all commands, flags, and enum values in my shell
  So that I can discover and use agentchrome features faster without consulting documentation

  # --- Happy Path: Generate completions for each shell ---

  Scenario: Generate bash completion script
    Given agentchrome is built
    When I run "agentchrome completions bash"
    Then the exit code should be 0
    And stdout should contain "agentchrome"

  Scenario: Generate zsh completion script
    Given agentchrome is built
    When I run "agentchrome completions zsh"
    Then the exit code should be 0
    And stdout should contain "agentchrome"

  Scenario: Generate fish completion script
    Given agentchrome is built
    When I run "agentchrome completions fish"
    Then the exit code should be 0
    And stdout should contain "agentchrome"

  Scenario: Generate powershell completion script
    Given agentchrome is built
    When I run "agentchrome completions powershell"
    Then the exit code should be 0
    And stdout should contain "agentchrome"

  Scenario: Generate elvish completion script
    Given agentchrome is built
    When I run "agentchrome completions elvish"
    Then the exit code should be 0
    And stdout should contain "agentchrome"

  # --- Content Validation ---

  Scenario: Completions contain top-level subcommands
    Given agentchrome is built
    When I run "agentchrome completions bash"
    Then the exit code should be 0
    And stdout should contain "navigate"
    And stdout should contain "tabs"
    And stdout should contain "connect"
    And stdout should contain "page"
    And stdout should contain "js"
    And stdout should contain "completions"

  Scenario: Completions contain nested subcommands
    Given agentchrome is built
    When I run "agentchrome completions bash"
    Then the exit code should be 0
    And stdout should contain "list"
    And stdout should contain "create"
    And stdout should contain "close"
    And stdout should contain "activate"

  Scenario: Completions contain global flags
    Given agentchrome is built
    When I run "agentchrome completions bash"
    Then the exit code should be 0
    And stdout should contain "--port"
    And stdout should contain "--host"
    And stdout should contain "--json"

  # --- Error Handling ---

  Scenario: Invalid shell argument produces error
    Given agentchrome is built
    When I run "agentchrome completions invalid-shell"
    Then the exit code should be 1
    And stderr should be valid JSON
    And stderr JSON should have key "error"
    And stderr JSON should have key "code"
    And stderr should contain "invalid value"

  # --- Help Text ---

  Scenario: Completions help shows installation instructions
    Given agentchrome is built
    When I run "agentchrome completions --help"
    Then the exit code should be 0
    And stdout should contain "bash"
    And stdout should contain "zsh"
    And stdout should contain "fish"
    And stdout should contain "powershell"
    And stdout should contain "elvish"

  Scenario: Completions subcommand appears in top-level help
    Given agentchrome is built
    When I run "agentchrome --help"
    Then the exit code should be 0
    And stdout should contain "completions"
