import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A third-pass investigation of authored semantics, independent of host JSON.
/// Each probe names its failure hypothesis and exercises the public view surface.
@MainActor
@Suite(.serialized)
struct AdversarialSetASemanticsTests {
  @Test func setA251DescendantPriorityCannotEscapeItsSemanticContainer() {
    // Hypothesis: global sorting lets a high-priority grandchild split another
    // container's subtree, or reverses equal-priority siblings.
    let result = snapshot(
      VStack {
        VStack {
          Text("A first").accessibilitySortPriority(100)
          Text("A second").accessibilitySortPriority(100)
        }.accessibilityElement(children: .contain).accessibilityLabel("Group A")
          .accessibilitySortPriority(-1)
        VStack {
          Text("B first")
          Text("B second")
        }.accessibilityElement(children: .contain).accessibilityLabel("Group B")
          .accessibilitySortPriority(1)
      })
    #expect(labels(result) == ["Group B", "B first", "B second", "Group A", "A first", "A second"])
  }

  @Test func setA252NestedCombinedDuplicateActionsReachTheirOriginalOwners() throws {
    // Hypothesis: a second combine layer drops or misroutes inner generated
    // actions instead of preserving their original child owners.
    let probe = SemanticProbe()
    let h = try harness(252) {
      VStack {
        VStack { Button("Run") { probe.first += 1 } }
          .accessibilityElement(children: .combine)
        Button("Run") { probe.second += 1 }
      }.accessibilityElement(children: .combine).accessibilityLabel("Nested operations")
    }
    defer { h.shutdown() }
    let group = try node("Nested operations", in: h)
    // Inner generated groups lack actionIdentity, so the outer combine skips
    // their preserved child routes before checking combinedActions.
    withKnownIssue("STUI-968: Outer combine drops an inner group's generated operations") {
      #expect(group.control?.customActions == ["Run", "Run (2)"])
    }
    let firstResult = try send(.custom("Run"), to: group, in: h)
    #expect(firstResult == .accepted)
    withKnownIssue("STUI-968: Missing inner route reassigns the first duplicate operation") {
      #expect([probe.first, probe.second] == [1, 0])
    }
    let secondResult = try send(.custom("Run (2)"), to: group, in: h)
    withKnownIssue("STUI-968: Missing inner route removes the second duplicate operation") {
      #expect(secondResult == .accepted)
      #expect([probe.first, probe.second] == [1, 1])
    }
  }

  @Test func setA253CombineDoesNotPromoteUnavailableChildOperations() throws {
    // Hypothesis: flattening an unavailable child into a parent custom action
    // bypasses the child's disabled/read-only guard.
    let probe = SemanticProbe()
    let h = try harness(253) {
      VStack {
        Button("Disabled operation") { probe.first += 1 }.disabled(true)
        Button("Read-only operation") { probe.second += 1 }
          .accessibilityProperties(.init(readOnly: true))
        Button("Available operation") { probe.third += 1 }
      }.accessibilityElement(children: .combine).accessibilityLabel("Operations")
    }
    defer { h.shutdown() }
    let group = try node("Operations", in: h)
    #expect(group.control?.customActions == ["Available operation"])
    #expect(try send(.custom("Disabled operation"), to: group, in: h) == .unsupported)
    #expect(try send(.custom("Read-only operation"), to: group, in: h) == .unsupported)
    #expect(try send(.custom("Available operation"), to: group, in: h) == .accepted)
    #expect(probe.first == 0 && probe.second == 0 && probe.third == 1)
  }

  @Test func setA254CombineReparentsNativeValueAndLinkControlsAfterRemovingWrappers() throws {
    // Hypothesis: retained native controls keep an orphaned parent identity
    // when combine removes an intervening structural container.
    let result = snapshot(
      VStack {
        Text("Summary")
        VStack {
          Toggle("Choice", isOn: .constant(true))
          Link("Reference", destination: "https://example.test/reference")
        }.accessibilityElement(children: .contain)
      }.accessibilityElement(children: .combine).accessibilityLabel("Aggregate"))
    let group = try node("Aggregate", in: result)
    let choice = try node("Choice", in: result)
    let link = try node("Reference", in: result)
    #expect(choice.parentIdentity == group.identity)
    #expect(link.parentIdentity == group.identity)
    #expect(choice.control?.actions.contains(.setValue) == true)
    #expect(link.control?.opensLink == true)
    #expect(!labels(result).contains("Summary"))
  }

  @Test func setA255IgnoredChildrenDoNotLeaveSemanticRelationsOrOperations() throws {
    // Hypothesis: ignore removes reading text but leaves a child's authored
    // relationship anchor or generated operation in the resulting snapshot.
    let anchor = Identity(components: ["ignored-child"])
    let result = snapshot(
      VStack {
        VStack {
          Button("Ignored operation") {}.accessibilityProperties(.init(identifier: anchor))
        }.accessibilityElement(children: .ignore).accessibilityLabel("Summary")
        Text("Reference source").accessibilityProperties(.init(controls: [anchor]))
      })
    #expect(!labels(result).contains("Ignored operation"))
    #expect(try node("Summary", in: result).control == nil)
    #expect(try node("Reference source", in: result).properties?.controls == [])
  }

  @Test func setA256VirtualControlsRemainOperableBeyondTheirPaintedRepresentationsSize() throws {
    // Hypothesis: a tiny primary decoration gives virtual controls empty action
    // scope, or leaks their larger labels into paint/keyboard traversal.
    let probe = SemanticProbe()
    let h = try harness(256) {
      VStack {
        Button("Ordinary") {}
        Text("X").frame(width: 1, height: 1).accessibilityRepresentation {
          Button("A much wider virtual operation") { probe.first += 1 }
        }
      }
    }
    defer { h.shutdown() }
    let virtual = try node("A much wider virtual operation", in: h)
    #expect(!h.frame.contains("virtual operation"))
    #expect(!h.runLoop.focusTracker.focusRegions.contains { $0.identity == virtual.actionIdentity })
    #expect(try send(.activate, to: virtual, in: h) == .accepted)
    #expect(probe.first == 1)
  }

  @Test func setA257SyntheticChildrenKeepTheirNamedParentAndNestedContainment() throws {
    // Hypothesis: preserving a visual parent's own semantics loses the virtual
    // subtree's explicit containment edge when the visual children are ignored.
    let result = snapshot(
      VStack { Text("Painted detail") }
        .accessibilityRole(.region).accessibilityLabel("Chart")
        .accessibilityChildren {
          VStack { Text("Value 42") }
            .accessibilityElement(children: .contain).accessibilityLabel("Data series")
        })
    let chart = try node("Chart", in: result)
    let series = try node("Data series", in: result)
    let value = try node("Value 42", in: result)
    #expect(chart.role == .region)
    #expect(series.parentIdentity == chart.identity)
    #expect(value.parentIdentity == series.identity)
    #expect(!labels(result).contains("Painted detail"))
  }

  @Test func setA258HiddenAncestorPrunesVirtualAndExplicitlyVisibleDescendants() {
    // Hypothesis: a replacement's separate virtual branch escapes an outer
    // hidden ancestor, especially when its child explicitly writes false.
    let result = snapshot(
      VStack {
        Text("Painted").accessibilityRepresentation {
          Button("Virtual") {}.accessibilityHidden(false)
        }
        Text("Explicit child").accessibilityHidden(false)
      }.accessibilityHidden())
    #expect(result.accessibilityNodes.isEmpty)
  }

  @Test func setA259EmptyCombinedNameBlocksAutomaticChildNameConcatenation() throws {
    // Hypothesis: an intentionally empty aggregate name is treated as absent
    // and repopulated from child labels during semantic combination.
    let result = snapshot(
      VStack {
        Text("Private summary")
        Button("Do work") {}
      }.accessibilityElement(children: .combine).accessibilityLabel(""))
    let group = try #require(
      result.accessibilityNodes.first { $0.control?.customActions == ["Do work"] })
    #expect(group.label == "")
    #expect(!labels(result).contains("Private summary"))
  }

  @Test func setA260RoleTraitsCannotManufactureAnActivationRoute() throws {
    // Hypothesis: role inference accidentally turns descriptive static text
    // into an operable control merely because its role says button or link.
    let result = snapshot(
      HStack {
        Text("Described button").accessibilityAddTraits(.isButton)
        Text("Described link").accessibilityAddTraits(.isLink)
      })
    #expect(try node("Described button", in: result).role == .button)
    #expect(try node("Described link", in: result).role == .link)
    #expect(result.accessibilityNodes.allSatisfy { $0.actionTarget == nil && $0.control == nil })
  }

  @Test func setA261CustomRoleOverrideKeepsThePrimitivesTypedValueOperation() throws {
    // Hypothesis: changing a built-in control's role discards its registered
    // typed action or causes value validation to depend on the default role.
    let probe = SemanticProbe()
    let h = try harness(261) {
      Toggle("Custom switch", isOn: probe.booleanBinding)
        .accessibilityRole(.custom("switch"))
    }
    defer { h.shutdown() }
    let toggle = try node("Custom switch", in: h)
    #expect(toggle.role == .custom("switch"))
    #expect(toggle.control?.value == .boolean(false))
    #expect(toggle.control?.actions.contains(.setValue) == true)
    let result = try send(.setValue(.boolean(true)), to: toggle, in: h)
    // Automatic focus excludes custom roles, leaving no action scope for the
    // primitive's still-advertised setValue operation; dispatch returns outOfScope.
    withKnownIssue("STUI-969: Custom role removes scope for a primitive's typed assistive action") {
      #expect(result == .accepted)
      #expect(probe.flag)
      #expect(probe.writes == 1)
    }
  }

  @Test func setA262RemovingHeadingTraitDoesNotEraseSelectedStateOrDescription() throws {
    // Hypothesis: removing one role trait drops the whole semantic payload,
    // including unrelated selection and descriptive metadata.
    let result = snapshot(
      Text("Former heading").accessibilityRole(.heading(level: 4))
        .accessibilityAddTraits(.isSelected)
        .accessibilityProperties(.init(description: "Keep this explanation"))
        .accessibilityRemoveTraits(.isHeader))
    let item = try node("Former heading", in: result)
    #expect(item.role == .group)
    #expect(item.properties?.selected == true)
    #expect(item.properties?.description == "Keep this explanation")
  }

  @Test func setA263WhitespaceOnlyCustomActionDoesNotPromoteStaticText() throws {
    // Hypothesis: an ignored empty operation still installs focus/action
    // metadata before its whitespace name is rejected.
    let result = snapshot(
      Text("Static description").accessibilityAction(named: " \t\n\u{2003}") {})
    let item = try node("Static description", in: result)
    #expect(item.control == nil)
    #expect(item.actionTarget == nil)
    #expect(item.role == .group)
    #expect(result.focusRegions.isEmpty)
  }

  @Test func setA264AssistiveActivationOverrideLeavesReturnKeyActivationUnchanged() throws {
    // Hypothesis: composing a replacement assistive callback also replaces the
    // primitive's ordinary keyboard activation registration.
    let probe = SemanticProbe()
    let h = try harness(264) {
      Button("Dual activation") { probe.first += 1 }
        .accessibilityAction { probe.second += 1 }
    }
    defer { h.shutdown() }
    let button = try node("Dual activation", in: h)
    #expect(try send(.activate, to: button, in: h) == .accepted)
    #expect(probe.first == 0 && probe.second == 1)
    #expect(try send(.focus, to: button, in: h) == .accepted)
    try h.pressKey(.init(.return))
    #expect(probe.first == 1 && probe.second == 1)
  }

  @Test func setA265DuplicateNamedActionUsesTheLatestOuterClosureAfterReevaluation() throws {
    // Hypothesis: replacing an outer duplicate retains either its previous
    // captured generation or the inner handler in the composed registry.
    let probe = SemanticProbe()
    let h = try harness(265) {
      let generation = probe.generation
      Text("Named operation")
        .accessibilityAction(named: "Inspect") { probe.first += 100 }
        .accessibilityAction(named: "Inspect") { probe.second += generation }
    }
    defer { h.shutdown() }
    #expect(try send(.custom("Inspect"), to: node("Named operation", in: h), in: h) == .accepted)
    probe.generation = 7
    try h.renderAfterExternalMutation()
    let current = try node("Named operation", in: h)
    #expect(current.control?.customActions == ["Inspect"])
    #expect(try send(.custom("Inspect"), to: current, in: h) == .accepted)
    #expect(probe.first == 0 && probe.second == 8)
  }

  @Test func setA266AdjustmentCompositionPreservesActivationAndNamedOperations() throws {
    // Hypothesis: installing both adjustment directions overwrites a previous
    // primitive activation or a later custom operation on the same owner.
    let probe = SemanticProbe()
    let h = try harness(266) {
      Button("Many operations") { probe.first += 1 }
        .accessibilityValue(4, in: 0...10, step: 2)
        .accessibilityAdjustableAction { direction in
          probe.second += direction == .increment ? 2 : -2
        }
        .accessibilityAction(named: "Inspect") { probe.third += 1 }
    }
    defer { h.shutdown() }
    let button = try node("Many operations", in: h)
    for action: AccessibilityAction in [
      .activate, .increment, .increment, .decrement, .custom("Inspect"),
    ] {
      #expect(try send(action, to: button, in: h) == .accepted)
    }
    #expect(probe.first == 1 && probe.second == 2 && probe.third == 1)
    #expect(button.control?.value == .number(4))
    #expect(button.control?.step == 2)
  }

  @Test func setA267ReadOnlyValueControlAcceptsFocusButRejectsBothMutationKinds() throws {
    // Hypothesis: read-only policy guards setValue but permits activation to
    // mutate the same Boolean, or incorrectly blocks harmless focus.
    let probe = SemanticProbe()
    let h = try harness(267) {
      Toggle("Read-only choice", isOn: probe.booleanBinding)
        .accessibilityProperties(.init(readOnly: true))
    }
    defer { h.shutdown() }
    let toggle = try node("Read-only choice", in: h)
    #expect(try send(.focus, to: toggle, in: h) == .accepted)
    #expect(try send(.activate, to: toggle, in: h) == .unsupported)
    #expect(try send(.setValue(.boolean(true)), to: toggle, in: h) == .unsupported)
    #expect(!probe.flag && probe.writes == 0)
  }

  @Test func setA268RangeValidationRejectsWrongTypesAndNonfiniteValuesBeforeMutation() throws {
    // Hypothesis: typed host values bypass a primitive's declared finite range
    // and call its binding setter before reporting invalidValue.
    let probe = SemanticProbe()
    let h = try harness(268) {
      Slider("Bounded number", value: probe.numberBinding, in: -2...4, step: 1)
    }
    defer { h.shutdown() }
    let slider = try node("Bounded number", in: h)
    for value: AccessibilityValue in [
      .text("2"), .boolean(true), .number(.nan), .number(.infinity), .number(-3), .number(5),
    ] {
      #expect(try send(.setValue(value), to: slider, in: h) == .invalidValue)
    }
    #expect(probe.number == 0 && probe.writes == 0)
    #expect(try send(.setValue(.number(-2)), to: slider, in: h) == .accepted)
    #expect(try send(.setValue(.number(4)), to: slider, in: h) == .accepted)
    #expect(probe.number == 4 && probe.writes == 2)
  }

  @Test func setA269NavigationCategoriesDeduplicateWithoutTakingKeyboardFocus() throws {
    // Hypothesis: repeated named review groups append focus registrations or
    // a semantic-focus request steals keyboard focus from a real control.
    let h = try harness(269) {
      VStack {
        Button("Keyboard owner") {}
        Text("Review destination").accessibilityNavigationCategory("Chapters")
          .accessibilityNavigationCategory(" \t")
          .accessibilityNavigationCategory("Chapters")
          .accessibilityNavigationCategory("Bookmarks")
      }
    }
    defer { h.shutdown() }
    let keyboard = h.runLoop.focusTracker.currentFocusIdentity
    let destination = try node("Review destination", in: h)
    #expect(destination.navigationCategories == ["Chapters", "Bookmarks"])
    #expect(destination.control?.actions.contains(.focus) == false)
    #expect(try send(.accessibilityFocus, to: destination, in: h) == .accepted)
    #expect(try node("Review destination", in: h).isAccessibilityFocused)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == keyboard)
  }

  @Test func setA270InvalidNumericOverrideCannotEraseValidAuthoredSemantics() throws {
    // Hypothesis: rejecting a nonfinite outer numeric modifier still replaces
    // valid inner range metadata or its spoken value description.
    let result = snapshot(
      Text("Authored range").accessibilityLabel("Authored range")
        .accessibilityValue(2, in: 0...5, step: 1, description: "Two units")
        .accessibilityAdjustableAction { _ in }
        .accessibilityValue(.nan, in: 0...10, step: 2, description: "Invalid replacement"))
    let control = try node("Authored range", in: result)
    #expect(control.control?.value == .number(2))
    #expect(control.control?.minimum == 0)
    #expect(control.control?.maximum == 5)
    #expect(control.control?.step == 1)
    #expect(control.properties?.valueDescription == "Two units")
    #expect(control.control?.actions.contains(.increment) == true)
    #expect(control.control?.actions.contains(.decrement) == true)
  }

  @Test func setA271RoleChangesRetireQueuedActionsEvenWhenTheGraphOwnerSurvives() throws {
    // Hypothesis: lifetime stamping keys only by graph owner and lets a queued
    // action for a previous semantic role operate the reinterpreted control.
    let probe = SemanticProbe()
    let h = try harness(271) {
      Button("Role-changing control") { probe.first += 1 }
        .accessibilityRole(probe.flag ? .link : .button)
    }
    defer { h.shutdown() }
    let original = try node("Role-changing control", in: h)
    probe.flag = true
    try h.renderAfterExternalMutation()
    let changed = try node("Role-changing control", in: h)
    #expect(changed.role == .link)
    #expect(changed.identity == original.identity)
    #expect(changed.actionTarget != original.actionTarget)
    let queuedResult = try send(.activate, to: original, in: h)
    #expect(queuedResult == .staleTarget)
    let currentResult = try send(.activate, to: changed, in: h)
    #expect(currentResult == .accepted)
    #expect(probe.first == 1)
  }

  @Test func setA272EmptyLanguageOverrideStopsInheritanceWithoutLeakingToSiblings() throws {
    // Hypothesis: an explicitly empty language is confused with nil, or an
    // inner override mutates the inherited language for a following sibling.
    let result = snapshot(
      VStack {
        Text("Inherited")
        VStack {
          Text("Cleared")
          Text("French").accessibilityProperties(.init(language: "fr"))
        }.accessibilityProperties(.init(language: ""))
        Text("Inherited again")
      }.accessibilityProperties(.init(language: "en")))
    #expect(try node("Inherited", in: result).properties?.language == "en")
    #expect(try node("Cleared", in: result).properties?.language == "")
    #expect(try node("French", in: result).properties?.language == "fr")
    #expect(try node("Inherited again", in: result).properties?.language == "en")
  }

  @Test func setA273AmbiguousRelationshipAnchorCannotChooseAnArbitraryPeer() throws {
    // Hypothesis: duplicate authored anchors silently select the first peer,
    // also dropping a separate unambiguous relation from the same source.
    let duplicate = Identity(components: ["duplicate-anchor"])
    let unique = Identity(components: ["unique-anchor"])
    let result = snapshot(
      VStack {
        Text("First duplicate").accessibilityProperties(.init(identifier: duplicate))
        Text("Second duplicate").accessibilityProperties(.init(identifier: duplicate))
        Text("Unique target").accessibilityProperties(.init(identifier: unique))
        Text("Relation source").accessibilityProperties(.init(describedBy: [duplicate, unique]))
      })
    #expect(
      try node("Relation source", in: result).properties?.describedBy == [
        node("Unique target", in: result).identity
      ])
  }

  @Test func setA274SemanticRelationshipsFollowLiveVisibilityAndRecoverAfterUnhiding() throws {
    // Hypothesis: retained relationship resolution preserves an absent target
    // or permanently erases an authored anchor after one hidden generation.
    let probe = SemanticProbe()
    let anchor = Identity(components: ["live-reference"])
    let h = try harness(274) {
      VStack {
        Text("Live target").accessibilityProperties(.init(identifier: anchor))
          .accessibilityHidden(probe.flag)
        Text("Live source").accessibilityProperties(.init(describedBy: [anchor]))
      }
    }
    defer { h.shutdown() }
    let originalIdentity = try node("Live target", in: h).identity
    #expect(try node("Live source", in: h).properties?.describedBy == [originalIdentity])
    probe.flag = true
    try h.renderAfterExternalMutation()
    #expect(try node("Live source", in: h).properties?.describedBy == [])
    probe.flag = false
    try h.renderAfterExternalMutation()
    #expect(
      try node("Live source", in: h).properties?.describedBy == [
        node("Live target", in: h).identity
      ])
  }

  @Test func setA275ExplicitFalseEmptyPropertiesOverrideEarlierValuesFieldByField() throws {
    // Hypothesis: payload merging treats false/empty values as absent, or
    // replacing those fields accidentally clears unrelated inherited metadata.
    let anchor = Identity(components: ["property-target"])
    let result = snapshot(
      VStack {
        Text("Target").accessibilityProperties(.init(identifier: anchor))
        Text("Merged properties")
          .accessibilityProperties(
            .init(
              selected: true, required: true, description: "Original", language: "de",
              describedBy: [anchor])
          )
          .accessibilityProperties(.init(selected: false, description: "", describedBy: []))
      })
    let properties = try #require(node("Merged properties", in: result).properties)
    #expect(properties.selected == false)
    #expect(properties.description == "")
    #expect(properties.describedBy == [])
    #expect(properties.required == true)
    #expect(properties.language == "de")
  }

  private func snapshot<V: View>(_ view: V) -> SemanticSnapshot {
    DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("SetASemanticSnapshot"), applyEnvironmentValues: true),
      proposal: .init(width: 80, height: 30)
    ).semanticSnapshot
  }

  private func labels(_ snapshot: SemanticSnapshot) -> [String] {
    snapshot.accessibilityNodes.compactMap(\.label)
  }

  private func node(_ label: String, in snapshot: SemanticSnapshot) throws -> AccessibilityNode {
    try #require(
      snapshot.accessibilityNodes.first { $0.label == label }, "Missing semantic node: \(label)")
  }

  private func node<V: View>(_ label: String, in h: StressRuntimeHarness<V>) throws
    -> AccessibilityNode
  {
    try node(label, in: h.runLoop.publishedAccessibilitySnapshot)
  }

  private func harness<V: View>(
    _ number: Int, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetASemantic\(number)"), size: .init(width: 80, height: 24),
      content: content)
  }

  private func send<V: View>(
    _ action: AccessibilityAction, to node: AccessibilityNode, in h: StressRuntimeHarness<V>
  ) throws -> AccessibilityActionResult {
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: try #require(node.actionTarget), action: action))
    try h.render()
    return result
  }
}

@MainActor
private final class SemanticProbe {
  var first = 0
  var second = 0
  var third = 0
  var generation = 1
  var flag = false
  var number = 0.0
  var writes = 0

  var booleanBinding: Binding<Bool> {
    Binding(
      get: { self.flag },
      set: {
        self.flag = $0
        self.writes += 1
      })
  }

  var numberBinding: Binding<Double> {
    Binding(
      get: { self.number },
      set: {
        self.number = $0
        self.writes += 1
      })
  }
}
