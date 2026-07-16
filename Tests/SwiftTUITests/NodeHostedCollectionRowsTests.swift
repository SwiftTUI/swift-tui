import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct NodeHostedCollectionRowsTests {
  @Test("a Button inside List remains a committed focus and action participant")
  func listButtonRemainsCommitted() throws {
    final class Box {
      var taps = 0
    }

    let box = Box()
    let actions = LocalActionRegistry()
    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Button("Tap") {
          box.taps += 1
        }
        .tag(1)
      },
      context: .init(
        identity: testIdentity("ListButtonRoot"),
        localActionRegistry: actions,
        applyEnvironmentValues: false
      )
    )

    let button = try #require(firstResolvedNode(kind: "Button", in: artifacts.resolvedTree))
    #expect(artifacts.semanticSnapshot.focusRegions.contains { $0.identity == button.identity })
    #expect(actions.dispatch(identity: button.identity))
    #expect(box.taps == 1)
  }

  @Test("a Button inside a Table cell remains a committed focus and action participant")
  func tableButtonRemainsCommitted() throws {
    final class Box {
      var taps = 0
    }

    let box = Box()
    let actions = LocalActionRegistry()
    let artifacts = DefaultRenderer().render(
      Table(selection: .constant(1), columns: [.init("Action", width: 12)]) {
        TableRow {
          Button("Run") {
            box.taps += 1
          }
        }
        .tag(1)
      },
      context: .init(
        identity: testIdentity("TableButtonRoot"),
        localActionRegistry: actions,
        applyEnvironmentValues: false
      )
    )

    let button = try #require(firstResolvedNode(kind: "Button", in: artifacts.resolvedTree))
    #expect(artifacts.semanticSnapshot.focusRegions.contains { $0.identity == button.identity })
    #expect(actions.dispatch(identity: button.identity))
    #expect(box.taps == 1)
  }

  @Test("invalid selectable List rows render and report stable runtime issues")
  func invalidSelectableListRowsRenderAndReport() {
    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        Text("Untagged")
        VStack {
          Text("First").tag(1)
          Text("Second").tag(2)
        }
      },
      context: .init(identity: testIdentity("InvalidListRows"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Untagged"))
    #expect(surface.contains("First"))
    #expect(surface.contains("Second"))
    #expect(
      artifacts.diagnostics.runtime.issues.map(\.code).contains(
        "collection.missingSelectionTag"
      )
    )
    #expect(
      artifacts.diagnostics.runtime.issues.map(\.code).contains(
        "collection.ambiguousSelectionTag"
      )
    )
  }

  @Test("plain List rows compile and render without selection tags or issues")
  func plainListRowsNeedNoTags() {
    let artifacts = DefaultRenderer().render(
      List {
        Text("Plain")
      },
      context: .init(identity: testIdentity("PlainList"))
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Plain"))
    #expect(
      !artifacts.diagnostics.runtime.issues.map(\.code).contains(
        "collection.missingSelectionTag"
      )
    )
  }

  @Test("optional List selection starts nil and selects a tagged row")
  func optionalListSelection() {
    final class Box {
      var value: Int?
    }

    let box = Box()
    let actions = LocalActionRegistry()
    _ = DefaultRenderer().render(
      List(
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
      },
      context: .init(
        identity: testIdentity("OptionalList"),
        localActionRegistry: actions,
        applyEnvironmentValues: false
      )
    )

    #expect(box.value == nil)
    #expect(
      actions.dispatch(
        identity: listRowIdentity(for: testIdentity("OptionalList"), rowIndex: 0)
      )
    )
    #expect(box.value == 1)
  }

  @Test("multi-select List row actions toggle membership independently")
  func multipleListSelectionToggles() {
    final class Box {
      var values: Set<Int> = [2]
    }

    let box = Box()
    let actions = LocalActionRegistry()
    _ = DefaultRenderer().render(
      List(
        selection: Binding(
          get: { box.values },
          set: { box.values = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
      },
      context: .init(
        identity: testIdentity("MultipleList"),
        localActionRegistry: actions,
        applyEnvironmentValues: false
      )
    )

    #expect(
      actions.dispatch(
        identity: listRowIdentity(for: testIdentity("MultipleList"), rowIndex: 0)
      )
    )
    #expect(box.values == [1, 2])
    #expect(
      actions.dispatch(
        identity: listRowIdentity(for: testIdentity("MultipleList"), rowIndex: 1)
      )
    )
    #expect(box.values == [1])
  }

  @Test("optional and multi-select Table builder overloads compile and render")
  func tableSelectionOverloadsCompileAndRender() {
    let optional = DefaultRenderer().render(
      Table(selection: .constant(nil as Int?), columns: [.init("Value", width: 6)]) {
        TableRow { Text("One") }.tag(1)
      },
      context: .init(identity: testIdentity("OptionalTable"))
    )
    let multiple = DefaultRenderer().render(
      Table(selection: .constant(Set([1])), columns: [.init("Value", width: 6)]) {
        TableRow { Text("One") }.tag(1)
      },
      context: .init(identity: testIdentity("MultipleTable"))
    )

    #expect(optional.rasterSurface.lines.joined(separator: "\n").contains("One"))
    #expect(multiple.rasterSurface.lines.joined(separator: "\n").contains("One"))
  }

  @Test("direct-data List realizes only a viewport-bounded row band")
  func directDataListIsWindowed() {
    final class Counter {
      var value = 0
    }

    let counter = Counter()
    let rows = Array(0..<1_000)
    let artifacts = DefaultRenderer().render(
      List(rows, id: \.self) { row in
        counter.value += 1
        Text("Row \(row)")
      },
      context: .init(identity: testIdentity("DirectList")),
      proposal: .init(width: .finite(30), height: .finite(12))
    )

    #expect(counter.value <= 14)
    #expect(artifacts.resolvedTree.indexedChildSource?.count == 1_000)
    #expect(artifacts.placedTree.children.count <= 12)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Row 0"))
  }

  @Test("direct-data Table realizes only a viewport-bounded row band")
  func directDataTableIsWindowed() {
    final class Counter {
      var value = 0
    }

    let counter = Counter()
    let rows = Array(0..<1_000)
    let artifacts = DefaultRenderer().render(
      Table(rows, id: \.self, columns: [.init("Value", width: 10)]) { row in
        counter.value += 1
        Text("Row \(row)")
      },
      context: .init(identity: testIdentity("DirectTable")),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    #expect(counter.value <= 10)
    #expect(artifacts.resolvedTree.indexedChildSource?.count == 1_000)
    #expect(artifacts.placedTree.children.count <= 8)
    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("Row 0"))
  }

  @Test("selected direct-data List and Table overloads apply the data ID tag")
  func selectedDirectDataOverloadsApplyIDs() {
    let rows = [IdentifiedRow(id: 1, label: "One")]
    let list = DefaultRenderer().render(
      List(rows, selection: .constant(nil as Int?)) { row in
        Text(row.label)
      },
      context: .init(identity: testIdentity("SelectedDirectList")),
      proposal: .init(width: .finite(20), height: .finite(8))
    )
    let table = DefaultRenderer().render(
      Table(
        rows,
        selection: .constant(Set([1])),
        columns: [.init("Value", width: 8)]
      ) { row in
        Text(row.label)
      },
      context: .init(identity: testIdentity("SelectedDirectTable")),
      proposal: .init(width: .finite(20), height: .finite(8))
    )

    #expect(list.rasterSurface.lines.joined(separator: "\n").contains("One"))
    #expect(table.rasterSurface.lines.joined(separator: "\n").contains("One"))
  }

  @Test("Toggle and TextField inside List retain their action and key routes")
  func listControlRoutesRemainCommitted() throws {
    final class Box {
      var isOn = false
      var text = "a"
    }

    let box = Box()
    let actions = LocalActionRegistry()
    let keys = LocalKeyHandlerRegistry()
    let fieldIdentity = testIdentity("HostedListControls", "Field")
    var environment = EnvironmentValues()
    environment.focusedIdentity = fieldIdentity
    let artifacts = DefaultRenderer().render(
      List(selection: .constant(1)) {
        HStack(spacing: 1) {
          Toggle(
            "Enabled",
            isOn: Binding(get: { box.isOn }, set: { box.isOn = $0 })
          )
          TextField(
            "Name",
            text: Binding(get: { box.text }, set: { box.text = $0 })
          )
          .id(fieldIdentity)
        }
        .tag(1)
      },
      context: .init(
        identity: testIdentity("HostedListControls"),
        environmentValues: environment,
        localActionRegistry: actions,
        localKeyHandlerRegistry: keys,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: .finite(40), height: .finite(5))
    )

    let toggle = try #require(firstResolvedNode(kind: "Toggle", in: artifacts.resolvedTree))
    #expect(actions.dispatch(identity: toggle.identity))
    #expect(box.isOn)
    #expect(keys.dispatch(identity: fieldIdentity, keyPress: KeyPress(.character("b"))))
    #expect(box.text == "ab")
  }

  @Test("List and Table row lifecycle modifiers remain registered")
  func collectionRowLifecycleRemainsCommitted() {
    final class Box {
      var appears = 0
      var disappears = 0
    }

    let box = Box()
    let lifecycle = LocalLifecycleRegistry()
    let root = VStack {
      List(selection: .constant(1)) {
        Text("List life")
          .onAppear { box.appears += 1 }
          .onDisappear { box.disappears += 1 }
          .tag(1)
      }
      Table(selection: .constant(1), columns: [.init("Value", width: 12)]) {
        TableRow {
          Text("Table life")
            .onAppear { box.appears += 1 }
            .onDisappear { box.disappears += 1 }
        }
        .tag(1)
      }
    }
    let artifacts = DefaultRenderer().render(
      root,
      context: .init(
        identity: testIdentity("HostedCollectionLifecycle"),
        localLifecycleRegistry: lifecycle,
        applyEnvironmentValues: true
      )
    )
    let lifecycleNodes = allResolvedNodes(in: artifacts.resolvedTree).filter {
      !$0.lifecycleMetadata.appearHandlerIDs.isEmpty
        || !$0.lifecycleMetadata.disappearHandlerIDs.isEmpty
    }

    #expect(lifecycleNodes.count == 2)
    for node in lifecycleNodes {
      for handlerID in node.lifecycleMetadata.appearHandlerIDs {
        lifecycle.appearHandler(for: handlerID)?()
      }
      for handlerID in node.lifecycleMetadata.disappearHandlerIDs {
        lifecycle.disappearHandler(for: handlerID)?()
      }
    }
    #expect(box.appears == 2)
    #expect(box.disappears == 2)
  }

  @Test("nested row controls win hit testing and keep state through unrelated updates")
  func nestedControlPrecedenceAndStatePersistence() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedCollectionState"),
      size: .init(width: 50, height: 10)
    ) {
      HostedCollectionStateFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Row state 0")
    #expect(frame.contains("Row state 1"))
    #expect(frame.contains("selection 2"))

    let rowPoint = try #require(harness.point(forText: "Row state 1"))
    frame = try harness.click(.init(x: rowPoint.x + 18, y: rowPoint.y))
    #expect(frame.contains("selection 1"))
    #expect(frame.contains("Row state 1"))

    frame = try harness.clickText("Unrelated 0")
    #expect(frame.contains("Unrelated 1"))
    #expect(frame.contains("Row state 1"))

    frame = try harness.clickText("Row state 1")
    #expect(frame.contains("Row state 2"))
    #expect(frame.contains("selection 1"))
  }

  @Test("builder-authored List retains its eager fallback")
  func builderListFallbackRemainsEager() {
    final class Counter {
      var value = 0
    }

    let counter = Counter()
    _ = DefaultRenderer().render(
      List {
        ForEach(0..<64, id: \.self) { index in
          counter.value += 1
          Text("Builder \(index)")
        }
      },
      context: .init(identity: testIdentity("EagerBuilderList")),
      proposal: .init(width: .finite(30), height: .finite(8))
    )

    #expect(counter.value == 64)
  }

  @Test("10k direct-data List realization and placement stay viewport bounded")
  func directDataList10KIsWindowed() {
    final class Counter {
      var value = 0
    }

    let counter = Counter()
    let artifacts = DefaultRenderer().render(
      List(0..<10_000, id: \.self) { row in
        counter.value += 1
        Text("Row \(row)")
      },
      context: .init(identity: testIdentity("DirectList10K")),
      proposal: .init(width: .finite(30), height: .finite(12))
    )

    #expect(counter.value <= 14)
    #expect(artifacts.resolvedTree.indexedChildSource?.count == 10_000)
    #expect(artifacts.placedTree.children.count <= 12)
  }

  @Test("10k direct-data Table realization and placement stay viewport bounded")
  func directDataTable10KIsWindowed() {
    final class Counter {
      var value = 0
    }

    let counter = Counter()
    let artifacts = DefaultRenderer().render(
      Table(0..<10_000, id: \.self, columns: [.init("Value", width: 10)]) { row in
        counter.value += 1
        Text("Row \(row)")
      },
      context: .init(identity: testIdentity("DirectTable10K")),
      proposal: .init(width: .finite(20), height: .finite(12))
    )

    #expect(counter.value <= 10)
    #expect(artifacts.resolvedTree.indexedChildSource?.count == 10_000)
    #expect(artifacts.placedTree.children.count <= 8)
  }

  @Test("direct-data row state follows IDs through reorder")
  func directDataRowStateSurvivesReorder() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedCollectionReorder"),
      size: .init(width: 46, height: 10)
    ) {
      HostedCollectionReorderFixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("B count 0")
    #expect(frame.contains("B count 1"))
    frame = try harness.clickText("Reverse rows")
    #expect(frame.contains("B count 1"))
    frame = try harness.clickText("B count 1")
    #expect(frame.contains("B count 2"))
  }

  @Test("direct-data rows pair viewport lifecycle on exit and re-entry")
  func directDataViewportLifecyclePairs() throws {
    let probe = HostedCollectionLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedCollectionViewportLifecycle"),
      size: .init(width: 44, height: 10)
    ) {
      HostedCollectionViewportLifecycleFixture(probe: probe)
    }
    defer { harness.shutdown() }

    #expect(probe.events.filter { $0 == "appear 0" }.count == 1)
    var frame = try harness.clickText("Toggle viewport")
    #expect(frame.contains("selection 20"))
    #expect(frame.contains("Life row 20"))
    #expect(probe.events.filter { $0 == "disappear 0" }.count == 1)
    frame = try harness.clickText("Toggle viewport")
    #expect(frame.contains("selection 0"))
    #expect(frame.contains("Life row 0"))
    #expect(probe.events.filter { $0 == "appear 0" }.count == 2)
  }

  @Test("removing a visible direct-data row tears its lifecycle down once")
  func directDataSourceShrinkTearsDownOnce() throws {
    let probe = HostedCollectionLifecycleProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedCollectionSourceShrink"),
      size: .init(width: 44, height: 10)
    ) {
      HostedCollectionSourceShrinkFixture(probe: probe)
    }
    defer { harness.shutdown() }

    #expect(probe.events.filter { $0 == "appear 8" }.count == 1)
    var frame = try harness.clickText("Shrink source")
    #expect(!frame.contains("Shrink row 8"))
    #expect(probe.events.filter { $0 == "disappear 8" }.count == 1)
    frame = try harness.clickText("Unrelated 0")
    #expect(frame.contains("Unrelated 1"))
    #expect(probe.events.filter { $0 == "disappear 8" }.count == 1)
  }

  @Test("direct-data Table auto widths retain their visible high-water mark")
  func directDataTableAutoWidthHighWaterIsStable() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HostedTableWidthHighWater"),
      size: .init(width: 70, height: 12)
    ) {
      HostedTableWidthHighWaterFixture()
    }
    defer { harness.shutdown() }

    let initialTail = try #require(harness.point(forText: "tail 0"))
    let frame = try harness.clickText("Jump table")
    #expect(frame.contains("selection 30"))
    let shiftedTail = try #require(harness.point(forText: "tail 30"))
    #expect(shiftedTail.x == initialTail.x)
  }
}

private struct IdentifiedRow: Identifiable {
  var id: Int
  var label: String
}

@MainActor
private struct HostedCollectionStateFixture: View {
  @State private var selection: Int? = 2
  @State private var unrelated = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("selection \(selection ?? -1)")
      Button("Unrelated \(unrelated)") { unrelated += 1 }
      List(selection: $selection) {
        HStack(spacing: 1) {
          HostedCollectionStateRow()
          Spacer(minLength: 1)
          Text("row bg")
        }
        .tag(1)
        Text("Second row").tag(2)
      }
      .frame(height: 5)
    }
  }
}

@MainActor
private struct HostedCollectionStateRow: View {
  @State private var count = 0

  var body: some View {
    Button("Row state \(count)") { count += 1 }
  }
}

private struct HostedCollectionDataRow: Identifiable {
  var id: String
}

@MainActor
private struct HostedCollectionReorderFixture: View {
  @State private var rows = [
    HostedCollectionDataRow(id: "A"),
    HostedCollectionDataRow(id: "B"),
    HostedCollectionDataRow(id: "C"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse rows") { rows.reverse() }
      List(rows) { row in
        HostedCollectionDataStateRow(label: row.id)
      }
      .frame(height: 6)
    }
  }
}

@MainActor
private struct HostedCollectionDataStateRow: View {
  let label: String
  @State private var count = 0

  var body: some View {
    Button("\(label) count \(count)") { count += 1 }
  }
}

@MainActor
private final class HostedCollectionLifecycleProbe {
  var events: [String] = []
}

@MainActor
private struct HostedCollectionViewportLifecycleFixture: View {
  let probe: HostedCollectionLifecycleProbe
  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("selection \(selection ?? -1)")
      Button("Toggle viewport") {
        selection = selection == 0 ? 20 : 0
      }
      List(0..<40, id: \.self, selection: $selection) { index in
        Text("Life row \(index)")
          .onAppear { probe.events.append("appear \(index)") }
          .onDisappear { probe.events.append("disappear \(index)") }
      }
      .frame(height: 6)
    }
  }
}

@MainActor
private struct HostedCollectionSourceShrinkFixture: View {
  let probe: HostedCollectionLifecycleProbe
  @State private var rows = Array(0..<12)
  @State private var selection: Int? = 8
  @State private var unrelated = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Shrink source") { rows = [0, 1] }
      Button("Unrelated \(unrelated)") { unrelated += 1 }
      List(rows, id: \.self, selection: $selection) { index in
        Text("Shrink row \(index)")
          .onAppear { probe.events.append("appear \(index)") }
          .onDisappear { probe.events.append("disappear \(index)") }
      }
      .frame(height: 6)
    }
  }
}

@MainActor
private struct HostedTableWidthHighWaterFixture: View {
  @State private var selection: Int? = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("selection \(selection ?? -1)")
      Button("Jump table") { selection = 30 }
      Table(
        0..<40,
        id: \.self,
        selection: $selection,
        columns: [.init("Value"), .init("Tail")]
      ) { index in
        Text(index == 0 ? "wide-value-000000" : "x")
        Text("tail \(index)")
      }
      .frame(height: 8)
    }
  }
}

private func firstResolvedNode(
  kind: String,
  in root: ResolvedNode
) -> ResolvedNode? {
  if root.kind == .view(kind) {
    return root
  }
  for child in root.children {
    if let match = firstResolvedNode(kind: kind, in: child) {
      return match
    }
  }
  return nil
}

private func allResolvedNodes(in root: ResolvedNode) -> [ResolvedNode] {
  [root] + root.children.flatMap(allResolvedNodes)
}
