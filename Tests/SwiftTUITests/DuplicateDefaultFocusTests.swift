import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct DuplicateDefaultFocusTests {
  @Test("A value ID forwarded through a modifier chain keeps one entity")
  func forwardedValueID() {
    let renderer = DefaultRenderer()
    for _ in 0..<2 {
      let snapshot = renderer.render(
        Button("One") {}.id("only").frame(width: 8).padding(1),
        proposal: .init(width: 20, height: 5)
      )
      #expect(snapshot.resolvedTree.duplicateEntityIdentityRuntimeIssues().isEmpty)
    }
  }

  @Test(
    "Duplicate IDs mount in a focus scope and reset in document order",
    arguments: DuplicateFocusContent.allCases)
  private func duplicateFocus(content: DuplicateFocusContent) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DuplicateFocus"), size: .init(width: 36, height: 8)
    ) { DuplicateFocusFixture(content: content) }
    defer { harness.shutdown() }
    let root = try #require(harness.runLoop.renderer.viewGraph.committedRootSnapshotIfAvailable())
    #expect(
      root.duplicateEntityIdentityRuntimeIssues().contains {
        $0.typedCode == .Identity.duplicateEntity
      })
    let regions = harness.runLoop.latestSemanticSnapshot.focusRegions
    try #require(regions.count == 2)
    let initial = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    #expect(initial == regions[0].identity)
    _ = try harness.focus(regions[1].identity)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == regions[1].identity)
    _ = try harness.pressKey(.init(.character("r")))
    _ = try harness.renderAfterExternalMutation()
    #expect(
      harness.runLoop.latestSemanticSnapshot.focusRegions.map(\.identity) == regions.map(\.identity)
    )
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == initial)
  }
}

private enum DuplicateFocusContent: CaseIterable, Sendable {
  case repeatedDataID, siblingValueIDs, nestedValueIDs
}

private struct DuplicateFocusFixture: View {
  @Namespace private var namespace
  @Environment(\.resetFocus) private var reset
  let content: DuplicateFocusContent

  var body: some View {
    VStack {
      switch content {
      case .repeatedDataID:
        ForEach(["same", "same"], id: \.self) { _ in Button("Row") {} }
      case .siblingValueIDs:
        Button("First") {}.id("same")
        Button("Second") {}.id("same")
      case .nestedValueIDs:
        VStack { Button("First") {}.id("same") }
        VStack { Button("Second") {}.id("same") }
      }
    }
    .focusScope(namespace)
    .onKeyPress(.character("r")) { _ in
      _ = reset(in: namespace)
      return .handled
    }
  }
}
