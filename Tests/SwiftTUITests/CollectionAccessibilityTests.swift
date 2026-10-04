import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct CollectionAccessibilityTests {
  private struct OutlineRecord: Identifiable {
    var id: String
    var children: [OutlineRecord] = []
  }

  @Test(
    "outline disclosures share state and preserve independent nested controls",
    arguments: [false, true])
  func outlineDisclosure(hosted: Bool) throws {
    var writes = 0
    let records = [OutlineRecord(id: "Parent", children: [.init(id: "Child")])]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("OutlineDisclosure"),
      size: .init(width: 60, height: 20)
    ) {
      Group {
        if hosted {
          List {
            OutlineGroup(records, children: \.children) { record in
              Button(record.id) { writes += 1 }
            }
          }
        } else {
          OutlineGroup(records, children: \.children) { record in
            Button(record.id) { writes += 1 }
          }
        }
      }
    }
    defer { harness.shutdown() }
    func target(_ name: String) throws -> String {
      try #require(
        harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == name }?
          .actionTarget)
    }
    let child = try target("Child")
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: child, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(writes == 1)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try target("Collapse item 1 at level 1"), action: .activate)) == .accepted)
    _ = try harness.render()
    #expect(
      !harness.runLoop.latestSemanticSnapshot.accessibilityNodes.contains { $0.label == "Child" })
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: child, action: .activate))
        == .staleTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try target("Expand item 1 at level 1"), action: .activate)) == .accepted)
    _ = try harness.render()
    #expect(try target("Child") != child)
    #expect(writes == 1)
  }

  @Test(
    "table header context retains authored sort and row-header roles", arguments: [false, true])
  func sortedHeaders(indexed: Bool) throws {
    let columns: [TableColumn] = [
      .init("Person", sort: .ascending, isRowHeader: true), .init("Score"),
    ]
    let snapshot = DefaultRenderer().render(
      Group {
        if indexed {
          Table(["Ada"], id: \.self, columns: columns) { name in
            Text(name)
            Text("100")
          }
        } else {
          Table(columns: columns) {
            TableRow {
              Text("Ada")
              Text("100")
            }
          }
        }
      }, proposal: .init(width: 40, height: 12)
    ).semanticSnapshot
    #expect(
      snapshot.accessibilityNodes.first { $0.role == .columnHeader && $0.label == "Person" }?
        .properties?.sort == .ascending)
    let header = try #require(snapshot.accessibilityNodes.first { $0.role == .rowHeader })
    #expect(header.properties?.rowIndex == 2 && header.properties?.columnIndex == 1)
  }

  @Test("list sections retain header context and position within the section")
  func sectionContext() throws {
    let nodes = DefaultRenderer().render(
      List {
        Section("First section") {
          Text("One")
          Text("Two")
        }
        Section("Second section") { Text("Three") }
      }, proposal: .init(width: 40, height: 20)
    ).semanticSnapshot.accessibilityNodes
    let items = nodes.filter { $0.role == .custom("listitem") }
    #expect(items.count == 3)
    #expect(
      items.map { $0.properties?.description } == [
        "First section, item 1 of 2", "First section, item 2 of 2", "Second section, item 1 of 1",
      ])
    #expect(nodes.filter { $0.label == "First section" }.count == 1)
    #expect(nodes.filter { $0.label == "Second section" }.count == 1)
  }
  @Test(
    "table selectors use the shared binding once and retire removed row targets",
    arguments: [false, true], [AnyTableStyle.automatic, .inset, .bordered])
  func tableSelection(indexed: Bool, style: AnyTableStyle) throws {
    var ids = [1, 2]
    var selected: Set<Int> = []
    var writes = 0
    var nestedWrites = 0
    var disabled = false
    var readonly = false
    let binding = Binding(
      get: { selected },
      set: {
        selected = $0
        writes += 1
      })
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionSelection"), size: .init(width: 60, height: 20)
    ) {
      Group {
        if indexed {
          Table(ids, id: \.self, selection: binding, columns: [.init("Record", width: 15)]) { id in
            Button("Inspect \(id)") { nestedWrites += 1 }
          }
        } else {
          Table(selection: binding, columns: [.init("Record", width: 15)]) {
            ForEach(ids, id: \.self) { id in
              TableRow { Button("Inspect \(id)") { nestedWrites += 1 } }.tag(id)
            }
          }
        }
      }.tableStyle(style).disabled(disabled).accessibilityProperties(.init(readOnly: readonly))
    }
    defer { harness.shutdown() }
    func target(_ name: String) throws -> String {
      try #require(
        harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first { $0.label == name }?
          .actionTarget)
    }
    let second = try target("Select row 2")
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: second, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(selected == [2] && writes == 1 && nestedWrites == 0)
    let selectedNode = harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
      $0.label == "Select row 2"
    }
    #expect(selectedNode?.control?.value == .boolean(true))
    let nestedTarget = try target("Inspect 2")
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: nestedTarget, action: .focus))
        == .accepted)
    _ = try harness.render()
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: nestedTarget, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(nestedWrites == 1 && writes == 1)
    ids.reverse()
    _ = try harness.renderAfterExternalMutation()
    #expect(try target("Select row 1") == second)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: second, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(selected.isEmpty && writes == 2)
    readonly = true
    _ = try harness.renderAfterExternalMutation()
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try target("Select row 1"), action: .activate)) == .unsupported)
    readonly = false
    disabled = true
    _ = try harness.renderAfterExternalMutation()
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try target("Select row 1"), action: .activate)) == .disabled)
    disabled = false
    ids = [1]
    _ = try harness.renderAfterExternalMutation()
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: second, action: .activate))
        == .staleTarget)
    ids = [1, 2]
    _ = try harness.renderAfterExternalMutation()
    #expect(try target("Select row 2") != second)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: second, action: .activate))
        == .staleTarget)
    #expect(writes == 2)
  }

  @Test("list assistive selectors share single selection with ordinary row input")
  func listSelection() throws {
    var selected: Int? = 1
    var writes = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ListSelection"), size: .init(width: 30, height: 12)
    ) {
      List(
        [1, 2], id: \.self,
        selection: Binding(
          get: { selected },
          set: {
            selected = $0
            writes += 1
          })
      ) {
        Text("Record \($0)")
      }
    }
    defer { harness.shutdown() }
    let target = try #require(
      harness.runLoop.latestSemanticSnapshot.accessibilityNodes.first {
        $0.label == "Select row 2"
      }?.actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(selected == 2 && writes == 1)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
        == .accepted)
    _ = try harness.render()
    #expect(selected == 2 && writes == 1)
  }

  @Test(
    "table headers, rows and cells retain full content across styles",
    arguments: [
      AnyTableStyle.automatic, .inset, .bordered,
    ])
  func staticTableStructure(style: AnyTableStyle) throws {
    let snapshot = DefaultRenderer().render(
      Table(columns: [.init("Person", width: 4), .init("Score", width: 5)]) {
        TableRow {
          Text("Ada Lovelace")
          Text("100")
        }
        TableRow {
          Text("Grace Hopper")
          Button("Inspect") {}
        }
      }.tableStyle(style).accessibilityLabel("Records"), proposal: .init(width: 40, height: 20)
    ).semanticSnapshot
    let nodes = snapshot.accessibilityNodes
    let table = try #require(nodes.first { $0.role == .table })
    #expect(table.properties?.rowCount == 3)
    #expect(table.properties?.columnCount == 2)
    let rows = nodes.filter { $0.role == .tableRow }
    #expect(rows.map { $0.properties?.rowIndex } == [1, 2, 3])
    #expect(rows.allSatisfy { $0.parentIdentity == table.identity })
    #expect(nodes.filter { $0.role == .columnHeader }.compactMap(\.label) == ["Person", "Score"])
    let cells = nodes.filter { $0.role == .cell }
    #expect(cells.map { $0.properties?.columnIndex } == [1, 2, 1, 2])
    #expect(cells.map { $0.properties?.rowIndex } == [2, 2, 3, 3])
    #expect(nodes.filter { $0.label == "Ada Lovelace" }.count == 1)
    #expect(nodes.filter { $0.label == "Grace Hopper" }.count == 1)
    #expect(nodes.filter { $0.role == .button && $0.label == "Inspect" }.count == 1)
  }

  @Test("indexed tables expose logical counts and positions with bounded materialization")
  func indexedTableStructure() throws {
    let snapshot = DefaultRenderer().render(
      Table(0..<200, id: \.self, columns: [.init("Record", width: 10)]) { index in
        Text("Record \(index)")
      }, proposal: .init(width: 30, height: 10)
    ).semanticSnapshot
    let table = try #require(snapshot.accessibilityNodes.first { $0.role == .table })
    #expect(table.properties?.rowCount == 201)
    let rows = snapshot.accessibilityNodes.filter { $0.role == .tableRow }
    #expect(rows.count > 1 && rows.count < 200)
    #expect(rows.allSatisfy { $0.properties?.rowIndex != nil })
    #expect(
      snapshot.accessibilityNodes.filter { $0.role == .columnHeader }.compactMap(\.label) == [
        "Record"
      ])
  }

  @Test("list items preserve complete text, nested controls and logical positions")
  func listStructure() throws {
    let snapshot = DefaultRenderer().render(
      List {
        Text("First record")
        Button("Inspect second") {}
      }, proposal: .init(width: 30, height: 12)
    ).semanticSnapshot
    let list = try #require(snapshot.accessibilityNodes.first { $0.role == .list })
    let items = snapshot.accessibilityNodes.filter { $0.role == .custom("listitem") }
    #expect(items.count == 2)
    #expect(items.map { $0.properties?.positionInSet } == [1, 2])
    #expect(items.allSatisfy { $0.properties?.setSize == 2 && $0.parentIdentity == list.identity })
    #expect(snapshot.accessibilityNodes.filter { $0.label == "First record" }.count == 1)
    #expect(snapshot.accessibilityNodes.filter { $0.label == "Inspect second" }.count == 1)
  }

  @Test("indexed list items carry total counts without realizing every row")
  func indexedListStructure() {
    let snapshot = DefaultRenderer().render(
      List(0..<200, id: \.self) { Text("Record \($0)") },
      proposal: .init(width: 30, height: 10)
    ).semanticSnapshot
    let items = snapshot.accessibilityNodes.filter { $0.role == .custom("listitem") }
    #expect(items.count > 0 && items.count < 200)
    #expect(
      items.allSatisfy { $0.properties?.setSize == 200 && $0.properties?.positionInSet != nil })
  }
}
