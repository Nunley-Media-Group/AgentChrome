# File: tests/features/bug-fix-dialog-handling-across-separate-agentchrome-invocations.feature
#
# Generated from: specs/bug-fix-dialog-handling-across-separate-agentchrome-invocations/requirements.md
# Issue: #225
# Type: Defect regression

@regression
Feature: Dialog handling across separate agentchrome invocations
  The `interact click` path previously did not install the dialog interceptor, so
  the `__agentchrome_dialog` cookie was never written when Process 1 triggered a
  dialog and Process 2 then tried to read it. This was fixed by routing
  `interact` sessions through `setup_session_with_interceptors` and adding a
  bounded post-click settle when `--auto-dismiss-dialogs` is active.

  # --- AC1: Cross-process prompt accept ---

  @regression
  Scenario: Process 2 can accept a prompt opened by Process 1
    Given two separate agentchrome invocations share the same CDP port
    And the page contains a JS prompt trigger identified as "s4"
    When Process 1 runs "interact click s4" and exits
    And Process 2 runs "dialog info"
    Then "dialog info" reports open=true with type "prompt" and a non-empty message
    When Process 2 runs "dialog handle accept --text \"Hello agentchrome\""
    Then the command exits with code 0
    And document.getElementById('result').innerText equals "You entered: Hello agentchrome"

  # --- AC2: Cross-process alert auto-dismiss ---

  @regression
  Scenario: --auto-dismiss-dialogs dismisses an alert before the process exits
    Given a page with a JS alert trigger identified as "s2"
    When "agentchrome --auto-dismiss-dialogs interact click s2" runs to completion
    Then no dialog remains blocking the renderer
    And document.getElementById('result').innerText equals "You successfully clicked an alert"

  # --- AC3: No regression in the single-process flow ---

  @regression
  Scenario: Same-process dialog flow behaves exactly as before
    Given a single agentchrome process that opens a dialog via interact
    When that same process runs "dialog info" and "dialog handle accept"
    Then the JSON output shape matches the pre-fix contract field-for-field
    And plain-text output matches the pre-fix messages
    And the exit codes match the pre-fix contract
