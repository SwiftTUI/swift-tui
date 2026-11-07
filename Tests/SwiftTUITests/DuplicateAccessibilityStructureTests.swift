import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct DuplicateAccessibilityStructureTests {
  private struct Row {
    var id: Int
    var name: String
  }

  private func rows(duplicate: Bool) -> [Row] {
    [.init(id: 1, name: "First"), .init(id: duplicate ? 1 : 2, name: "Second")]
  }

  @Test(arguments: [false, true], ["contain", "list", "table"])
  func eachContainerKeepsItsChildren(duplicate: Bool, kind: String) throws {
    let records = rows(duplicate: duplicate)
    let snapshot = DefaultRenderer().render(
      Group {
        if kind == "list" {
          List(selection: Binding<Int?>.constant(nil)) {
            ForEach(records, id: \.id) { row in Text(row.name).tag(row.id) }
          }
        } else if kind == "table" {
          Table(
            records, id: \.id, selection: Binding<Set<Int>>.constant([]),
            columns: [.init("Name")]
          ) { row in Text(row.name) }
        } else {
          VStack {
            ForEach(records, id: \.id) { row in
              HStack {
                Text(row.name)
                Button("Go") {}
              }
              .accessibilityElement(children: .contain)
            }
          }
        }
      }, context: .init(identity: testIdentity("DuplicateStructure", kind)),
      proposal: .init(width: 50, height: 12))
    let nodes = snapshot.semanticSnapshot.accessibilityNodes
    // Hosts resolve a parent token to its nearest preceding occurrence. Check
    // that each row's content actually follows that row, including selectors.
    var preceding: [Identity: Int] = [:]
    var parents: [Int: Int] = [:]
    for index in nodes.indices {
      if let parent = nodes[index].parentIdentity { parents[index] = preceding[parent] }
      preceding[nodes[index].identity] = index
    }
    let first = try #require(nodes.firstIndex { $0.label == "First" })
    let second = try #require(nodes.firstIndex { $0.label == "Second" })
    func container(_ index: Int) -> Int? {
      var current = parents[index]
      while let candidate = current {
        if kind == "contain" || nodes[candidate].role == .custom("listitem")
          || nodes[candidate].role == .tableRow
        {
          return candidate
        }
        current = parents[candidate]
      }
      return nil
    }
    let firstContainer = try #require(container(first))
    let secondContainer = try #require(container(second))
    #expect(firstContainer != secondContainer)
    if kind != "contain" {
      let selectors = nodes.indices.filter { nodes[$0].label?.hasPrefix("Select row ") == true }
      #expect(selectors.count == 2)
      #expect(selectors.compactMap(container) == [firstContainer, secondContainer])
    }
  }

  @Test(arguments: [false, true])
  func combinedRowsKeepTheirOwnNamesAndActions(duplicate: Bool) throws {
    var activated: [String] = []
    let records = rows(duplicate: duplicate)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DuplicateCombine"), size: .init(width: 50, height: 12)
    ) {
      VStack {
        ForEach(records, id: \.id) { row in
          HStack {
            Text(row.name)
            Button("Go") { activated.append(row.name) }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    defer { harness.shutdown() }
    let groups = harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
      $0.control?.customActions.isEmpty == false
    }
    #expect(groups.map(\.label) == ["First, Go", "Second, Go"])
    #expect(groups.map { $0.control?.customActions } == [["Go"], ["Go"]])
    for group in groups {
      #expect(
        harness.runLoop.handleAccessibilityAction(
          .init(target: try #require(group.actionTarget), action: .custom("Go"))) == .accepted)
    }
    #expect(activated == ["First", "Second"])
  }

  @Test func duplicateSortPrioritiesRemainIndependent() {
    let snapshot = DefaultRenderer().render(
      VStack {
        ForEach(rows(duplicate: true), id: \.id) { row in
          Text(row.name).accessibilitySortPriority(row.name == "First" ? 0 : 1)
        }
      }, context: .init(identity: testIdentity("DuplicateSort")),
      proposal: .init(width: 50, height: 12))
    #expect(
      snapshot.semanticSnapshot.accessibilityNodes.compactMap(\.label)
        == ["Second", "First"])
  }

  @Test func duplicateChildBehaviorsAndRetainedEditorsRemainIndependent() throws {
    let snapshot = DefaultRenderer().render(
      VStack {
        ForEach(rows(duplicate: true), id: \.id) { row in
          HStack {
            TextField(row.name + " editor", text: .constant("Value"))
            Button("Go") {}
          }
          .accessibilityLabel(row.name)
          .accessibilityElement(children: row.name == "First" ? .ignore : .combine)
        }
      }, context: .init(identity: testIdentity("DuplicateBehaviors")),
      proposal: .init(width: 50, height: 12))
    let nodes = snapshot.semanticSnapshot.accessibilityNodes
    #expect(!nodes.contains { $0.label == "First editor" })
    let second = try #require(nodes.firstIndex { $0.label == "Second" })
    let editor = try #require(nodes.firstIndex { $0.label == "Second editor" })
    #expect(editor > second)
    #expect(nodes[editor].parentIdentity == nodes[second].identity)
    #expect(nodes[second].control?.customActions == ["Go"])
    #expect(nodes.first { $0.label == "First" }?.control == nil)
  }
}
