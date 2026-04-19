# File: tests/features/101-fix-disconnect-process-not-killed.feature
#
# Generated from: .claude/specs/101-fix-disconnect-process-not-killed/requirements.md
# Issue: #101
# Type: Defect regression

@regression
Feature: Disconnect actually terminates Chrome process
  The `connect --disconnect` command previously reported `killed_pid` in its
  JSON output but did not actually terminate the Chrome process. The kill signal
  was sent without waiting for the process to exit, and child processes were
  not cleaned up. This was fixed by sending SIGTERM to the process group,
  polling for termination, and escalating to SIGKILL if needed.

  # --- Bug Is Fixed ---

  @regression @requires-chrome
  Scenario: Disconnect kills the Chrome process
    Given Chrome was launched with "connect --launch --headless"
    And I note the Chrome process PID
    When I run "connect --disconnect"
    Then the output should contain "killed_pid"
    And the Chrome process should no longer be running

  # --- Child Processes Cleaned Up ---

  @regression @requires-chrome
  Scenario: Disconnect kills Chrome child processes
    Given Chrome was launched with "connect --launch --headless"
    And Chrome has spawned child processes
    When I run "connect --disconnect"
    Then the output should contain "killed_pid"
    And no Chrome child processes from the launched instance should be running

  # --- Already-Exited Process ---

  @regression
  Scenario: Disconnect with already-exited process succeeds cleanly
    Given a session file exists with a PID of an already-exited process
    When I run "connect --disconnect"
    Then the output should contain "disconnected"
    And the session file should not exist
    And the exit code should be 0
