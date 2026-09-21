import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct OutlineIndentationTests {
  enum Hosting: CaseIterable {
    case standalone
    case listInitializer
    case manualList
  }

  private struct Node: Identifiable {
    let id: String
    var children: [Node] = []
  }

  @Test(
    "Equal-depth outline connectors align for every ancestor continuation combination",
    arguments: Hosting.allCases, [AnyOutlineStyle.rounded, .plain]
  )
  func connectorsAlignAcrossSubtrees(hosting: Hosting, style: AnyOutlineStyle) throws {
    let nodes = [
      Node(
        id: "RootA",
        children: [
          Node(id: "BranchA", children: [Node(id: "LeafA")]),
          Node(id: "BranchB", children: [Node(id: "LeafB")]),
        ]
      ),
      Node(
        id: "RootB",
        children: [
          Node(id: "BranchC", children: [Node(id: "LeafC")]),
          Node(id: "BranchD", children: [Node(id: "LeafD")]),
        ]
      ),
    ]
    let snapshot = DefaultRenderer().render(
      outline(nodes, hosting: hosting)
        .outlineStyle(style),
      context: .init(identity: testIdentity("OutlineIndentation")),
      proposal: .init(width: 40, height: 20)
    )
    let lines = snapshot.rasterSurface.lines
    let branchColumn = try connectorColumn(for: "BranchA", in: lines)
    let leafColumn = try connectorColumn(for: "LeafA", in: lines)

    for name in ["BranchB", "BranchC", "BranchD"] {
      #expect(try connectorColumn(for: name, in: lines) == branchColumn)
    }
    for name in ["LeafB", "LeafC", "LeafD"] {
      #expect(try connectorColumn(for: name, in: lines) == leafColumn)
    }
    #expect(leafColumn == branchColumn + 2)
  }

  @ViewBuilder
  private func outline(_ nodes: [Node], hosting: Hosting) -> some View {
    switch hosting {
    case .standalone:
      OutlineGroup(nodes, children: \.children) { Text($0.id) }
    case .listInitializer:
      List(nodes, selection: .constant("RootA"), children: \.children) { Text($0.id) }
        .listStyle(.insetGrouped)
    case .manualList:
      List(selection: .constant("RootA")) {
        OutlineGroup(nodes, children: \.children) { Text($0.id).tag($0.id) }
      }
      .listStyle(.insetGrouped)
    }
  }

  private func connectorColumn(for name: String, in lines: [String]) throws -> Int {
    let line = try #require(lines.first { $0.contains(name) })
    let connector = try #require(line.firstIndex { "├╰└".contains($0) })
    return line.distance(from: line.startIndex, to: connector)
  }
}
