# File: tests/features/94-fix-connect-auto-discover-reconnect.feature
#
# Generated from: .claude/specs/94-fix-connect-auto-discover-reconnect/requirements.md
# Issue: #94
# Type: Defect regression

@regression
Feature: Connect auto-discover reconnects to existing session
  The connect command's auto-discover path previously skipped the session file
  and called discover_chrome() directly, which could launch a second Chrome
  instance instead of reconnecting to the one already managed by agentchrome.
  This was fixed by adding a session file check with health verification
  before attempting discovery.

  # --- Bug Is Fixed ---

  @regression
  Scenario: Auto-discover reconnects to existing session instead of launching new Chrome
    Given Chrome was launched with "connect --launch --headless" and session.json exists with a PID and port
    When I run "connect" without any flags
    Then the CLI reconnects to the existing Chrome instance using the session file's ws_url
    And no new Chrome process is spawned
    And the session file's PID is preserved

  # --- Stale Session Fallback ---

  @regression
  Scenario: Auto-discover falls back to discovery when session is stale
    Given a session.json exists but the Chrome process at the recorded port is no longer running
    When I run "connect" without any flags
    Then the CLI attempts to discover a running Chrome instance
    And if none is found the output includes an error message

  # --- No Orphaned Processes ---

  @regression
  Scenario: No orphaned Chrome processes after reconnect and disconnect
    Given Chrome was launched with "connect --launch --headless"
    When I run "connect" without any flags
    And I run "connect --disconnect"
    Then exactly zero agentchrome-managed Chrome processes remain running

  # --- PID Preservation Regression Guard ---

  @regression
  Scenario: Session PID preserved after reconnection
    Given Chrome was launched with "connect --launch" storing a specific PID on a given port
    When I run "connect" auto-discover and it reconnects to the same port
    Then the session file retains the original PID
