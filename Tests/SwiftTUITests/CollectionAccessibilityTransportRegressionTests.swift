import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct CollectionAccessibilityTransportRegressionTests {
  @Test(
    "published collection targets survive focus and eager-indexed-style churn",
    arguments: [false, true])
  func publishedTargets(asyncDriver: Bool) async throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionTransport"),
      size: .init(width: 171, height: 69)
    ) { CollectionAccessibilityWorkload() }
    defer { harness.shutdown() }
    var frames = 0
    func render() async throws {
      if asyncDriver {
        try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
      } else {
        try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
      }
      let nodes = harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
      #expect(Set(nodes.map(\.identity)).count == nodes.count)
      for node in nodes {
        #expect(node.parentIdentity != node.identity)
      }
    }
    func press(_ label: String) async throws {
      let node = try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        })
      let target = try #require(node.actionTarget)
      if label == "Inspect 1" {
        let live = harness.runLoop.renderer.viewGraph.nodeForIdentity(node.identity)
        #expect(node.viewNodeID == live?.viewNodeID)
      }
      if node.control?.actions.contains(.focus) == true {
        #expect(
          harness.runLoop.handleAccessibilityAction(.init(target: target, action: .focus))
            == .accepted)
        try await render()
        let next = harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        }?.actionTarget
        #expect(next == target)

      }
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
          == .accepted)
      try await render()
    }
    for style in 0..<3 {
      for indexed in [false, true] {
        if indexed { try await press("Indexed records") }
        try await press("Select row 2")
        try await press("Inspect 1")
        try await press("Sort records")
        try await press("Read-only records")
        try await press("Read-only records")
        try await press("Disable records")
        try await press("Disable records")
        try await press("Collapse item 1 at level 1")
        try await press("Expand item 1 at level 1")
      }
      try await press("Indexed records")
      if style < 2 { try await press("Change collection style") }
    }
    #expect(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Collection writes 6; inspections 6; style 2; eager"
      })
  }
}

private struct CollectionOutlineRecord: Identifiable {
  let id: String
  var children: [CollectionOutlineRecord] = []
}

private struct CollectionAccessibilityWorkload: View {
  @State private var selected: Set<Int> = []
  @State private var selectionWrites = 0
  @State private var inspections = 0
  @State private var descending = false
  @State private var style = 0
  @State private var disabled = false
  @State private var readonly = false
  @State private var indexed = false

  private var records: [Int] { descending ? [2, 1] : [1, 2] }
  private var columns: [TableColumn] {
    [
      .init("Person", width: 16, sort: descending ? .descending : .ascending, isRowHeader: true),
      .init("Score", width: 8), .init("Action", width: 12),
    ]
  }
  private var selection: Binding<Set<Int>> {
    Binding(
      get: { selected },
      set: {
        selected = $0
        selectionWrites += 1
      })
  }
  @ViewBuilder private func cells(_ id: Int) -> some View {
    Text(id == 1 ? "Ada Lovelace" : "Grace Hopper")
    Text(id == 1 ? "100" : "95")
    Button("Inspect \(id)") { inspections += 1 }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(
        "Collection writes \(selectionWrites); inspections \(inspections); style \(style); \(indexed ? "indexed" : "eager")"
      )
      HStack {
        Button("Change collection style") { style = (style + 1) % 3 }
        Button("Sort records") { descending.toggle() }
        Toggle("Indexed records", isOn: $indexed)
      }
      HStack {
        Toggle("Disable records", isOn: $disabled)
        Toggle("Read-only records", isOn: $readonly)
      }
      Group {
        if indexed {
          Table(records, id: \.self, selection: selection, columns: columns) { cells($0) }
        } else {
          Table(selection: selection, columns: columns) {
            ForEach(records, id: \.self) { id in TableRow { cells(id) }.tag(id) }
          }
        }
      }
      .tableStyle(style == 0 ? .automatic : (style == 1 ? .inset : .bordered))
      .disabled(disabled)
      .accessibilityProperties(.init(readOnly: readonly))
      .accessibilityLabel("Records")
      .frame(height: 8)
      List {
        Section("Primary records") {
          Text("Ada")
          Text("Grace")
        }
        Section("Archive") { Text("Katherine") }
      }.listStyle(style == 0 ? .automatic : (style == 1 ? .plain : .insetGrouped))
      OutlineGroup(
        [CollectionOutlineRecord(id: "Sources", children: [.init(id: "App.swift")])],
        children: \.children
      ) {
        Text($0.id)
      }.outlineStyle(style == 1 ? .plain : .rounded)
    }
  }
}
