import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite(.serialized)
struct AccessibilityExtractionScalingTests {
  private let rect = CellRect(origin: .zero, size: .init(width: 20, height: 1))

  @Test("Grouping scales with siblings and repeated action titles", arguments: [false, true])
  func groupingScaling(oneContainer: Bool) {
    func sample(_ count: Int) -> Duration {
      var nodes: [AccessibilityNode] = []
      var structures: [Identity: AccessibilityStructure] = [:]
      let root = testIdentity("GroupedRows")
      for row in 0..<(oneContainer ? 1 : count) {
        let parent = root.child(.indexed("Row", index: row))
        nodes.append(.init(identity: parent, rect: rect, role: .group))
        var structure = AccessibilityStructure()
        structure.children = .combine
        structures[parent] = structure
        for column in 0..<(oneContainer ? count : 2) {
          let identity = parent.child(.indexed("Action", index: column))
          var child = AccessibilityNode(
            viewNodeID: .init(rawValue: UInt64(nodes.count + 1)),
            identity: identity, parentIdentity: parent, rect: rect, role: .button, label: "Action")
          child.control = .init(actions: [.activate])
          child.actionIdentity = identity
          nodes.append(child)
        }
      }
      var result: [AccessibilityNode] = []
      let elapsed = (0..<3).map { _ in
        ContinuousClock().measure {
          result = SemanticExtractor().applyingAccessibilityStructure(
            to: nodes, structures: structures)
        }
      }.min()!
      #expect(result.count == (oneContainer ? 1 : count))
      #expect(
        result.allSatisfy {
          Set($0.control?.customActions ?? []).count == (oneContainer ? count : 2)
        })
      #expect(result.first?.control?.customActions.prefix(2) == ["Action", "Action (2)"])
      return elapsed
    }
    let small = sample(500)
    let large = sample(5_000)
    print("accessibility grouping oneContainer=\(oneContainer): 500=\(small), 5000=\(large)")
    // Wide timing allowance accommodates shared CI hosts; quadratic scans and
    // restarting duplicate-name searches still exceed it by a wide margin.
    #expect(large < small * 35 + .milliseconds(20))
  }

  @Test("Inline links scale with indexed routes and preserve individual geometry")
  func inlineLinkScaling() {
    func sample(_ count: Int) -> Duration {
      let parent = testIdentity("RichDocument")
      var runs: [RichTextRun] = []
      var routes: [FocusRegion] = []
      for index in 0..<count {
        runs.append(.init(text: "prose "))
        runs.append(
          .init(text: "link", destination: "https://example.com", linkIdentifier: "link-\(index)"))
        routes.append(
          .init(
            identity: inlineLinkIdentity(parent: parent, identifier: "link-\(index)"),
            rect: .init(origin: .init(x: 0, y: index), size: .init(width: 4, height: 1))))
      }
      let placed = PlacedNode(
        identity: parent, kind: .view("Text"), bounds: rect,
        drawPayload: .richText(.init(runs: runs)))
      var result: [AccessibilityNode] = []
      let elapsed = (0..<3).map { _ in
        ContinuousClock().measure {
          result =
            SemanticExtractor().accessibilityNodesAndVisualLabelRoutes(
              from: placed, focusRegions: routes
            ).nodes
        }
      }.min()!
      let links = result.filter { $0.role == .link }
      #expect(links.count == count)
      #expect(links.map(\.rect) == routes.map(\.rect))
      #expect(result.filter { $0.label == "prose " }.count == count)
      return elapsed
    }
    let small = sample(500)
    let large = sample(5_000)
    print("accessibility inline links: 500=\(small), 5000=\(large)")
    #expect(large < small * 35 + .milliseconds(20))
  }
}
