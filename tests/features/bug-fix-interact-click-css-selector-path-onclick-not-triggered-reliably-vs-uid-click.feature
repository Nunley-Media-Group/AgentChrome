# File: tests/features/bug-fix-interact-click-css-selector-path-onclick-not-triggered-reliably-vs-uid-click.feature
#
# Generated from: specs/bug-fix-interact-click-css-selector-path-onclick-not-triggered-reliably-vs-uid-click/requirements.md
# Issue: #252
# Type: Defect regression
#
# All scenarios require a running Chrome instance navigated to the fixture at
# tests/fixtures/interact-click-css-selector-onclick.html, so the BDD harness
# skips them in CI. They document the regression for manual / integration
# verification. See tests/bdd.rs registration for the skip filter.

@regression
Feature: interact click CSS selector fires the onclick handler
  `agentchrome interact click "css:<selector>"` previously resolved the
  target via `DOM.getDocument` + `DOM.querySelector`, yielding a `nodeId`
  scoped to a document handle that could be stale relative to the live
  layout. The mouse event was then dispatched at coordinates that no
  longer landed on the element, so inline `onclick` handlers did not
  fire. This was fixed by resolving the selector through
  `Runtime.evaluate(document.querySelector(...))` + `DOM.describeNode`
  with an `objectId`, keeping the node bound to the live document and
  matching the UID path's stable `backendNodeId` semantics.

  Background:
    Given agentchrome is connected to a headless Chrome instance
    And the page at tests/fixtures/interact-click-css-selector-onclick.html is loaded

  @regression
  Scenario: AC1 — CSS-selector click triggers the onclick handler
    When I run `agentchrome interact click "css:button[onclick='addElement()']"`
    Then the exit code is 0
    And the DOM contains a `.added-manually` element inside `#container`

  @regression
  Scenario: AC2 — UID click behaviour is unchanged
    Given an accessibility snapshot has been taken and the Add Element button has UID "s2"
    When I run `agentchrome interact click s2`
    Then the exit code is 0
    And the DOM contains a `.added-manually` element inside `#container`

  @regression
  Scenario: AC3 — CSS-selector navigation click still reports navigated
    When I run `agentchrome interact click "css:#nav-link"`
    Then the exit code is 0
    And the JSON output's `navigated` field equals true
