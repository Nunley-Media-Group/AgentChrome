# File: tests/features/large-response-detection.feature
#
# Generated from: specs/feature-add-large-response-detection-with-guided-search-and-full-response-override/requirements.md
# Issue: #168

Feature: Large Response Detection with Guided Search and Full-Response Override
  As an AI agent consuming agentchrome output
  I want a machine-readable guidance response when output exceeds a size threshold
  So that I can avoid unnecessary context consumption while still accessing full output when required

  Background:
    Given a connected Chrome session

  # --- Core Detection ---

  Scenario: Large response returns guidance object instead of raw data
    Given a page with an accessibility tree exceeding 16 KB when serialized
    When I run "page snapshot"
    Then stdout contains valid JSON with "large_response" set to true
    And stdout contains "size_bytes" as a positive integer
    And stdout contains "command" set to "page snapshot"
    And stdout contains a "summary" object
    And stdout contains a "guidance" string
    And the exit code is 0

  Scenario: Search flag filters and returns matching content
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot --search login"
    Then stdout contains an accessibility tree with only nodes matching "login"
    And stdout does not contain "large_response"
    And the exit code is 0

  Scenario: Full-response override returns complete data
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot --full-response"
    Then stdout contains the complete accessibility tree JSON
    And stdout does not contain "large_response"
    And the exit code is 0

  Scenario: Guidance object contains actionable instructions
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot"
    Then the "guidance" field contains "--search"
    And the "guidance" field contains "--full-response"
    And the "guidance" field contains "page snapshot --search"
    And the "guidance" field contains "Use --full-response when"

  Scenario: Below-threshold responses are unaffected
    Given a page with an accessibility tree under 16 KB when serialized
    When I run "page snapshot"
    Then stdout contains the full accessibility tree JSON
    And stdout does not contain "large_response"
    And the exit code is 0

  # --- Threshold Configuration ---

  Scenario: Threshold is configurable via CLI flag
    Given a page producing 20 KB of serialized JSON output
    When I run "page snapshot --large-response-threshold 32768"
    Then stdout contains the full accessibility tree JSON
    And stdout does not contain "large_response"

  Scenario: Threshold configured via CLI flag triggers at custom value
    Given a page producing 20 KB of serialized JSON output
    When I run "page snapshot --large-response-threshold 8192"
    Then stdout contains valid JSON with "large_response" set to true

  Scenario: Threshold is configurable via config file
    Given a config file with "large_response_threshold = 8192" under "[output]"
    And a page producing 10 KB of serialized JSON output
    When I run "page snapshot"
    Then stdout contains valid JSON with "large_response" set to true

  Scenario: CLI threshold flag overrides config file
    Given a config file with "large_response_threshold = 8192" under "[output]"
    And a page producing 10 KB of serialized JSON output
    When I run "page snapshot --large-response-threshold 32768"
    Then stdout contains the full response
    And stdout does not contain "large_response"

  # --- Schema Consistency ---

  Scenario: Guidance object schema is consistent across commands
    Given a page with content exceeding 16 KB
    When I run "page snapshot"
    Then the guidance JSON has exactly these top-level keys: "large_response", "size_bytes", "command", "summary", "guidance"
    When I run "page text"
    Then the guidance JSON has exactly these top-level keys: "large_response", "size_bytes", "command", "summary", "guidance"

  # --- Per-Command Search ---

  Scenario: Page snapshot search filters by text and role
    Given a page with a large accessibility tree containing a "login" button and a "signup" link
    When I run "page snapshot --search login"
    Then stdout contains nodes with name or role matching "login"
    And stdout does not contain nodes exclusively in the "signup" branch
    And ancestor nodes are preserved for tree context

  Scenario: Page text search filters by content
    Given a page with text content exceeding 16 KB containing paragraphs about "errors" and "warnings"
    When I run "page text --search error"
    Then stdout JSON "text" field contains only paragraphs with "error"
    And stdout JSON has "url" and "title" fields
    And the exit code is 0

  Scenario: JS exec search filters JSON keys and values
    Given a JavaScript expression returning a large JSON object with an "email" field
    When I run "js exec ... --search email"
    Then stdout contains only key-value pairs matching "email"
    And the exit code is 0

  Scenario: Network list search filters by URL pattern
    Given a page with network requests to "api/v2/users" and "cdn/images"
    When I run "network list --search api/v2"
    Then stdout contains only requests with URLs matching "api/v2"
    And the exit code is 0

  Scenario: Network get search filters response content
    Given a network request with a large response body containing "token"
    When I run "network get 1 --search token"
    Then the response body contains only content matching "token"
    And the exit code is 0

  # --- Search Bypasses Gate ---

  Scenario: Search flag bypasses large-response gate
    Given a page with an accessibility tree exceeding 16 KB
    And a search query that matches most of the tree
    When I run "page snapshot --search a"
    Then stdout contains the filtered accessibility tree
    And stdout does not contain "large_response"
    And the exit code is 0

  # --- Output Format Compatibility ---

  Scenario: Full-response works with pretty-print
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot --full-response --pretty"
    Then stdout contains pretty-printed JSON
    And stdout does not contain "large_response"

  Scenario: Full-response works with compact JSON
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot --full-response --json"
    Then stdout contains compact JSON
    And stdout does not contain "large_response"

  # --- Existing Truncation ---

  Scenario: Existing per-command truncation remains as second layer
    Given a page with 15000 accessibility tree nodes
    When I run "page snapshot --full-response"
    Then stdout contains the accessibility tree with "truncated" set to true
    And the tree contains at most 10000 nodes

  # --- Command-Specific Summary ---

  Scenario: Snapshot summary contains node count and top roles
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot"
    Then the "summary" object contains "total_nodes" as a positive integer
    And the "summary" object contains "top_roles" as an array of strings

  Scenario: Page text summary contains character and line counts
    Given a page with text content exceeding 16 KB
    When I run "page text"
    Then the "summary" object contains "character_count" as a positive integer
    And the "summary" object contains "line_count" as a positive integer

  # --- Plain Mode ---

  Scenario: Plain mode is not affected by large-response detection
    Given a page with an accessibility tree exceeding 16 KB
    When I run "page snapshot --plain"
    Then stdout contains the full plain-text accessibility tree
    And stdout does not contain "large_response"
    And stdout does not contain "guidance"

  Scenario: Search works with plain mode
    Given a page with a large accessibility tree containing a "login" button
    When I run "page snapshot --plain --search login"
    Then stdout contains plain-text tree nodes matching "login"
    And stdout does not contain "large_response"

  # =============================================================================
  # Issue #220 — Extend temp-file gating to remaining large-response commands
  # =============================================================================
  # All scenarios below are Chrome-dependent and are skipped in CI.
  # They are validated during the /verify-code manual smoke test against the
  # tests/fixtures/harden-progressive-disclosure.html fixture.

  # --- AC3: newly gated commands emit TempFileOutput above threshold ---

  Scenario: audit above threshold emits TempFileOutput with audit summary (AC3, AC4)
    Given a page that produces a Lighthouse report exceeding 16 KB
    When I run "audit"
    Then stdout is a TempFileOutput object
    And the "command" field is "audit"
    And the "summary" object contains "categories" as an array
    And the "summary" object contains "total_issues" as an integer
    And the "summary" object contains "failing_audit_ids" as an array
    And the exit code is 0

  Scenario: dom select above threshold emits TempFileOutput with dom-select summary (AC3, AC4)
    Given a page with enough DOM nodes that dom select produces more than 16 KB
    When I run "dom select *"
    Then stdout is a TempFileOutput object
    And the "command" field is "dom select"
    And the "summary" object contains "match_count" as an integer
    And the "summary" object contains "first_match" as an object
    And the exit code is 0

  Scenario: dom get-style above threshold emits TempFileOutput with styles summary (AC3, AC4)
    Given a page with elements whose computed styles produce more than 16 KB
    When I run "dom get-style <uid>"
    Then stdout is a TempFileOutput object
    And the "command" field is "dom get-style"
    And the "summary" object contains "attribute_count" as an integer
    And the "summary" object contains "keys_seen" as an array
    And the exit code is 0

  Scenario: dom events above threshold emits TempFileOutput with dom-events summary (AC3, AC4)
    Given a page with many event listeners producing more than 16 KB
    When I run "dom events --selector *"
    Then stdout is a TempFileOutput object
    And the "command" field is "dom events"
    And the "summary" object contains "listener_count" as an integer
    And the "summary" object contains "event_types" as an array
    And the exit code is 0

  Scenario: page analyze above threshold emits TempFileOutput with page-analyze summary (AC3, AC4)
    Given a page that produces a page analyze result exceeding 16 KB
    When I run "page analyze"
    Then stdout is a TempFileOutput object
    And the "command" field is "page analyze"
    And the "summary" object contains "iframe_count" as an integer
    And the "summary" object contains "overlay_count" as an integer
    And the "summary" object contains "has_shadow_dom" as a boolean
    And the exit code is 0

  Scenario: page find above threshold emits TempFileOutput with page-find summary (AC3, AC4)
    Given a page with enough interactive elements that page find produces more than 16 KB
    When I run "page find --role *"
    Then stdout is a TempFileOutput object
    And the "command" field is "page find"
    And the "summary" object contains "match_count" as an integer
    And the "summary" object contains "roles_seen" as an array
    And the exit code is 0

  Scenario: console read above threshold emits TempFileOutput with console-read summary (AC3, AC4)
    Given a page that emits more than 200 console messages
    When I run "console read"
    Then stdout is a TempFileOutput object
    And the "command" field is "console read"
    And the "summary" object contains "message_count" as an integer
    And the "summary" object contains "error_count" as an integer
    And the "summary" object contains "warning_count" as an integer
    And the "summary" object contains "levels_seen" as an array
    And the exit code is 0

  Scenario: interact click with include-snapshot above threshold emits compound schema (AC3, AC5)
    Given a clickable element on a page whose snapshot exceeds 16 KB
    When I run "interact click <uid> --include-snapshot"
    Then stdout is a compound TempFileOutput object
    And stdout contains "success" at the top level
    And stdout contains "uid" at the top level
    And the "snapshot" key contains "output_file" pointing to a temp file
    And the "snapshot" key contains "size_bytes" as a positive integer
    And the "snapshot" key contains "command" set to "interact click"
    And the "snapshot" key contains a "summary" object with "total_nodes"
    And the exit code is 0

  # --- AC5: compound schema below threshold is fully inline ---

  Scenario: interact click with include-snapshot below threshold is fully inline (AC5)
    Given a clickable element on a small page whose snapshot is under 16 KB
    When I run "interact click <uid> --include-snapshot"
    Then stdout does not contain "output_file"
    And stdout contains "success" at the top level
    And stdout contains "snapshot" as an inline object
    And the exit code is 0

  # --- AC9: below-threshold behavior unchanged ---

  Scenario: page find below threshold returns raw JSON array unchanged (AC9)
    Given a page with only three interactive elements
    When I run "page find --role button"
    Then stdout is a JSON array
    And stdout does not contain "output_file"
    And stdout does not contain "TempFileOutput"
    And the exit code is 0
