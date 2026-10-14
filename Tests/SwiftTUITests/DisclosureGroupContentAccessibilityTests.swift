import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct DisclosureGroupContentAccessibilityTests {
  @Test("style-authored ignore suppresses content descendants", arguments: [1, 2])
  func ignoredStyleContent(childCount: Int) {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Button("Private action") {}
        if childCount > 1 { Text("Private text") }
      }.disclosureGroupStyle(IgnoringContentDisclosureStyle()),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    #expect(!nodes.contains { $0.label == "Private action" || $0.label == "Private text" })
    #expect(!nodes.contains { $0.role == .region })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
  }

  @Test("style-authored combine promotes live content actions", arguments: [1, 2])
  func combinedStyleContent(childCount: Int) throws {
    var activations = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CombinedDisclosure"), size: .init(width: 30, height: 6)
    ) {
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Button("Child action") { activations += 1 }
        if childCount > 1 { Text("Additional detail") }
      }.disclosureGroupStyle(CombiningContentDisclosureStyle())
    }
    defer { harness.shutdown() }
    let nodes = harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    let combined = try #require(
      nodes.first {
        $0.control?.customActions.contains("Child action") == true
      })
    #expect(combined.role == .group)
    #expect(!nodes.contains { $0.role == .button && $0.label == "Child action" })
    #expect(!nodes.contains { $0.role == .region })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try #require(combined.actionTarget), action: .custom("Child action")))
        == .accepted)
    #expect(activations == 1)
    var frames = 0
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    #expect(activations == 1)
  }

  @Test("a style can replace the content's accessibility presentation", arguments: [1, 2])
  func representedStyleContent(childCount: Int) {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Button("Visual action") {}
        if childCount > 1 { Text("Visual text") }
      }.disclosureGroupStyle(RepresentingContentDisclosureStyle()),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    #expect(!nodes.contains { $0.label == "Visual action" || $0.label == "Visual text" })
    #expect(nodes.contains { $0.label == "Replacement details" })
    #expect(!nodes.contains { $0.role == .region })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
  }

  @Test("hidden style content does not publish a region", arguments: [0, 1, 2], [false, true])
  func hiddenStyleContent(childCount: Int, wrapped: Bool) {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        if childCount > 0 { Text("Secret") }
        if childCount > 1 { Button("Secret action") {} }
      }.disclosureGroupStyle(HiddenContentDisclosureStyle(wrapped: wrapped)),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    #expect(!nodes.contains { $0.label == "Secret" || $0.label == "Secret action" })
    #expect(!nodes.contains { $0.role == .region })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
  }

  @Test("style-authored contain remains above the content region", arguments: [1, 2])
  func containedStyleContent(childCount: Int) throws {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Button("Child action") {}
        if childCount > 1 { Text("Additional detail") }
      }.disclosureGroupStyle(ContainingContentDisclosureStyle()),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    let region = try #require(nodes.first { $0.role == .region })
    #expect(region.parentIdentity == testIdentity("StyledContent"))
    #expect(nodes.contains { $0.identity == region.parentIdentity })
    #expect(nodes.first { $0.label == "Child action" }?.parentIdentity == region.identity)
    if childCount > 1 {
      #expect(nodes.first { $0.label == "Additional detail" }?.parentIdentity == region.identity)
    }
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [region.identity])
  }

  @Test("repeated content slots retain independent grouping", arguments: [false, true])
  func repeatedContent(ignoreSecond: Bool) throws {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Button("Child action") {}
      }.disclosureGroupStyle(RepeatedContentDisclosureStyle(ignoreSecond: ignoreSecond)),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    let regions = nodes.filter { $0.role == .region }
    #expect(regions.count == (ignoreSecond ? 1 : 2))
    #expect(regions.first?.parentIdentity == testIdentity("FirstSlot"))
    if !ignoreSecond {
      #expect(regions.last?.parentIdentity == testIdentity("SecondSlot"))
      #expect(regions.first?.identity != regions.last?.identity)
    }
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == regions.map(\.identity))
    let buttons = nodes.filter { $0.label == "Child action" }
    #expect(buttons.count == regions.count)
    #expect(
      buttons.allSatisfy { button in regions.contains { $0.identity == button.parentIdentity } })
  }

  @Test("explicit controls relationships override generated disclosure relationships")
  func authoredControls() {
    let result = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Text("Content")
      }.accessibilityProperties(.init(controls: [])),
      proposal: .init(width: 30, height: 6))
    let nodes = result.semanticSnapshot.accessibilityNodes
    #expect(nodes.contains { $0.role == .region })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
  }
}

private struct IgnoringContentDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      VStack { configuration.content }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Summary only")
    }
  }
}

private struct CombiningContentDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      VStack { configuration.content }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Combined details")
    }
  }
}

private struct RepresentingContentDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      configuration.content.accessibilityRepresentation { Button("Replacement details") {} }
    }
  }
}

private struct HiddenContentDisclosureStyle: DisclosureGroupStyle {
  var wrapped: Bool
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      if wrapped {
        VStack { configuration.content }.accessibilityHidden(true)
      } else {
        configuration.content.accessibilityHidden(true)
      }
    }
  }
}

private struct ContainingContentDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      VStack { configuration.content }
        .accessibilityElement(children: .contain)
        .id(testIdentity("StyledContent"))
    }
  }
}

private struct RepeatedContentDisclosureStyle: DisclosureGroupStyle {
  var ignoreSecond: Bool
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      VStack { configuration.content }
        .accessibilityElement(children: .contain)
        .id(testIdentity("FirstSlot"))
      VStack { configuration.content }
        .accessibilityElement(children: ignoreSecond ? .ignore : .contain)
        .id(testIdentity("SecondSlot"))
    }
  }
}
