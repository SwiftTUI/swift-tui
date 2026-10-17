@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct AccessibilityCompositionContractTests {
  private func node<V: View>(_ view: V) throws -> AccessibilityNode {
    let result = DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["TraitFold"])),
      proposal: .init(width: 40, height: 8))
    return try #require(result.semanticSnapshot.accessibilityNodes.first { $0.label == "Meaning" })
  }

  @Test func removingTheStrongestTraitRevealsTheRemainingContribution() throws {
    let result = try node(
      Text("Meaning").accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(.isHeader).accessibilityRemoveTraits(.isHeader))
    #expect(result.role == .button)
    let reversed = try node(
      Text("Meaning").accessibilityAddTraits(.isHeader)
        .accessibilityAddTraits(.isButton).accessibilityRemoveTraits(.isHeader))
    #expect(reversed.role == .button)
  }

  @Test func explicitRoleStartsANewTraitFoldAndPreservesHeadingLevel() throws {
    let result = try node(
      Text("Meaning").accessibilityAddTraits([.isHeader, .isStaticText])
        .accessibilityRole(.heading(level: 4)).accessibilityAddTraits(.isButton))
    #expect(result.role == .heading(level: 4))
    let removed = try node(
      Text("Meaning").accessibilityAddTraits([.isHeader, .isStaticText])
        .accessibilityRole(.heading(level: 4)).accessibilityRemoveTraits(.isHeader))
    #expect(removed.role == .group)
  }

  @Test func linearValuesResolveSelectionLabelsAndKeepProtectedValuesPrivate() {
    var choice = AccessibilityNode(
      identity: Identity(components: ["choice"]),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)), role: .picker, label: "Mode")
    choice.control = .init(
      actions: [.setValue], value: .text("opaque-choice-token"),
      selection: .init(
        presentation: .menu,
        options: [.init(id: "opaque-choice-token", label: "Quiet", isEnabled: true)]))
    var secret = AccessibilityNode(
      identity: Identity(components: ["secret"]),
      rect: choice.rect, role: .secureField, label: "Password")
    secret.control = .init(actions: [.setValue], value: .text("not-public"))
    let output = LinearAccessibilityRenderer().render([choice, secret])
    #expect(output.contains("Quiet"))
    #expect(!output.contains("opaque-choice-token"))
    #expect(output.contains("Protected value"))
    #expect(!output.contains("not-public"))
    choice.control = .init(
      actions: [.setValue], value: .text("stale-choice-token"),
      selection: .init(presentation: .menu, options: []))
    #expect(!LinearAccessibilityRenderer().render([choice]).contains("stale-choice-token"))
  }

  @Test func nestedAdjustmentReachesItsOriginalControlThroughACustomRole() throws {
    let probe = AccessibilityCompositionProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["NestedAdjustment"]), size: .init(width: 40, height: 10)
    ) {
      VStack {
        VStack {
          Stepper(
            "Level", value: Binding(get: { probe.level }, set: { probe.level = $0 }), in: 0...9
          )
          .accessibilityRole(.custom("level"))
        }.accessibilityElement(children: .combine)
      }.accessibilityElement(children: .combine).accessibilityLabel("Settings")
    }
    defer { h.shutdown() }
    let group = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Settings"
      })
    #expect(group.properties?.valueDescription == "3")
    let target = try #require(group.actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Increase Level")))
        == .accepted)
    #expect(probe.level == 4)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Decrease Level")))
        == .accepted)
    #expect(probe.level == 3)
  }

  @Test func containerNamedActionsDoNotClaimTheirChildrensLabels() {
    let snapshot = DefaultRenderer().render(
      VStack {
        Text("First detail")
        Text("Second detail")
      }
      .accessibilityAction(named: "Archive") {},
      context: .init(identity: Identity(components: ["ContainerOperation"])),
      proposal: .init(width: 40, height: 8)
    ).semanticSnapshot
    #expect(snapshot.accessibilityNodes.compactMap(\.label) == ["First detail", "Second detail"])
    #expect(snapshot.accessibilityNodes.contains { $0.control?.customActions == ["Archive"] })
    #expect(snapshot.focusRegions.isEmpty)
  }

}

@MainActor
private final class AccessibilityCompositionProbe {
  var level = 3
}
