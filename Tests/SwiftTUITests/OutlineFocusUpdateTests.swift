import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct OutlineFocusUpdateTests {
  @Test(
    "the direct outline List initializer exposes native row focus and selection navigation",
    arguments: [
      (true, false, false), (true, false, true), (true, true, false), (true, true, true),
      (false, false, false), (false, false, true), (false, true, false), (false, true, true),
    ]
  )
  func directOutlineListSupportsNativeRowNavigation(
    overload: (requiresSelection: Bool, hasOptionalChildren: Bool, hasExplicitID: Bool)
  ) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DirectOutlineListFocus"),
      size: CellSize(width: 44, height: 12)
    ) {
      DirectFocusUpdateOutlineList(
        requiresSelection: overload.requiresSelection,
        hasOptionalChildren: overload.hasOptionalChildren,
        hasExplicitID: overload.hasExplicitID)
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("selected=10"))
    _ = try harness.focusText("Parent")
    try requireOutlineRowFocus("Parent", selected: 10, in: harness)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireOutlineRowFocus("Child", selected: 20, in: harness)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireOutlineRowFocus("Sibling", selected: 30, in: harness)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireOutlineRowFocus("Child", selected: 20, in: harness)
  }

  @Test("composed outline multi-selection keeps membership separate from native row focus")
  func composedOutlineMultipleSelection() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MultipleOutlineFocus"),
      size: CellSize(width: 44, height: 12)
    ) {
      MultipleFocusUpdateOutlineList()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Parent")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    let childIdentity = try harness.focusIdentity(forText: "Child")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == childIdentity)
    #expect(harness.frame.contains("members=[10]"))
    _ = try harness.pressKey(KeyPress(.space))
    #expect(harness.frame.contains("members=[10, 20]"))
    _ = try harness.pressKey(KeyPress(.arrowDown))
    let siblingIdentity = try harness.focusIdentity(forText: "Sibling")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == siblingIdentity)
    #expect(harness.frame.contains("members=[10, 20]"))
    _ = try harness.pressKey(KeyPress(.arrowUp))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == childIdentity)
    _ = try harness.pressKey(KeyPress(.space))
    #expect(harness.frame.contains("members=[10]"))
  }

  @Test("equal authored sibling tags still produce an ambiguous List row")
  func equalAuthoredSiblingTagsRemainAmbiguous() {
    let snapshot = DefaultRenderer().render(
      List(selection: Binding<Int>.constant(10)) {
        VStack {
          Text("First").tag(10)
          Text("Second").tag(10)
        }
      },
      context: ResolveContext(identity: testIdentity("AmbiguousOutlineTagCounterexample")))
    let text = snapshot.rasterSurface.lines.joined(separator: "\n")
    #expect(text.contains("First") && text.contains("Second"))
    #expect(
      snapshot.diagnostics.runtime.issues.map(\.code) == ["collection.ambiguousSelectionTag"])
  }

  @Test("a changed hidden outline descendant reveals current content, focus, and action")
  func hiddenDescendantChangesHeightAndValue() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HiddenOutlineFocusUpdate"),
      size: CellSize(width: 44, height: 12)
    ) {
      UpdatingOutlineList()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Root")
    // First measure the original descendant, then retire its viewport window.
    for _ in 0..<13 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireOutlineRowFocus("Original «12»:0", selected: 12, in: harness)
    for _ in 0..<13 {
      _ = try harness.pressKey(KeyPress(.arrowUp))
    }
    try requireOutlineRowFocus("Root", selected: -1, in: harness)
    try #require(!harness.frame.contains("Original «12»:0"))
    let rootFocus = harness.runLoop.focusTracker.currentFocusIdentity

    _ = try harness.pressKey(KeyPress(.character("u"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == rootFocus)
    #expect(!harness.frame.contains("Updated «12»:0"))
    #expect(harness.frame.contains("version=updated"))

    for _ in 0..<13 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireOutlineRowFocus("Updated «12»:0", selected: 12, in: harness)
    #expect(harness.frame.contains("Updated «12»:2"), "\(harness.frame)")
    #expect(!harness.frame.contains("Original «12»:0"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=Updated «12» count=1"), "\(harness.frame)")

    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireOutlineRowFocus("Original «11»:0", selected: 11, in: harness)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=Original «11» count=2"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireOutlineRowFocus("Updated «12»:0", selected: 12, in: harness)
    #expect(harness.frame.contains("Updated «12»:2"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=Updated «12» count=3"), "\(harness.frame)")
  }

  @Test(
    "retiring a focused outline descendant removes its routes and preserves live activation",
    arguments: [false, true], [false, true]
  )
  func retiredDescendantCannotReceiveInput(hosted: Bool, removesDescendant: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RetiredOutlineFocus", "\(hosted)-\(removesDescendant)"),
      size: CellSize(width: 44, height: 12)
    ) {
      RetiringOutline(hosted: hosted)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Retiring child")
    let retiredIdentity = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    let retiredTarget = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Retiring child"
      }?.actionTarget)

    if removesDescendant {
      _ = try harness.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    } else {
      let collapseTarget = try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == "Collapse item 1 at level 1"
        }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(
          AccessibilityActionRequest(target: collapseTarget, action: .activate)) == .accepted)
      _ = try harness.render()
    }

    #expect(!harness.frame.contains("Retiring child"), "\(harness.frame)")
    #expect(
      !harness.runLoop.focusTracker.focusRegions.contains { $0.identity == retiredIdentity })
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.actionTarget == retiredTarget || $0.label == "Retiring child"
      })
    for action in [AccessibilityAction.focus, .activate] {
      #expect(
        harness.runLoop.handleAccessibilityAction(
          AccessibilityActionRequest(target: retiredTarget, action: action)) == .staleTarget)
    }
    _ = try harness.render()
    #expect(harness.frame.contains("activated=none count=0"), "\(harness.frame)")

    // Retirement does not prescribe a fallback target or prune authored selection.
    _ = try harness.focusText("Surviving sibling")
    let survivorIdentity = try harness.focusIdentity(forText: "Surviving sibling")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == survivorIdentity)
    #expect(survivorIdentity != retiredIdentity)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=Surviving sibling count=1"), "\(harness.frame)")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == survivorIdentity)
  }
}

@MainActor
private func requireOutlineRowFocus<Content: View>(
  _ label: String, selected: Int, in harness: StressRuntimeHarness<Content>
) throws {
  try #require(harness.frame.contains(label), "the outline row is painted:\n\(harness.frame)")
  let identity = try harness.focusIdentity(forText: label)
  #expect(harness.runLoop.focusTracker.currentFocusIdentity == identity, "\(harness.frame)")
  #expect(harness.frame.contains("selected=\(selected)"), "\(harness.frame)")
}

private struct FocusUpdateOutlineRecord: Identifiable {
  let id: Int
  let title: String
  let lineCount: Int
  let children: [FocusUpdateOutlineRecord]

  var optionalChildren: [FocusUpdateOutlineRecord]? {
    children.isEmpty ? nil : children
  }

  init(id: Int, title: String, lineCount: Int, children: [FocusUpdateOutlineRecord] = []) {
    self.id = id
    self.title = title
    self.lineCount = lineCount
    self.children = children
  }
}

@MainActor
private struct DirectFocusUpdateOutlineList: View {
  let requiresSelection: Bool
  let hasOptionalChildren: Bool
  let hasExplicitID: Bool
  @State private var optionalSelection: Int? = 10
  @State private var requiredSelection = 10

  private var records: [FocusUpdateOutlineRecord] {
    [
      FocusUpdateOutlineRecord(
        id: 10, title: "Parent", lineCount: 1,
        children: [FocusUpdateOutlineRecord(id: 20, title: "Child", lineCount: 1)]),
      FocusUpdateOutlineRecord(id: 30, title: "Sibling", lineCount: 1),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      outline
        .listStyle(FocusUpdateOutlineListStyle())
        .scrollIndicators(.hidden)
        .frame(height: 8)
      Text("selected=\(requiresSelection ? requiredSelection : optionalSelection ?? -1)")
    }
  }

  @ViewBuilder
  private var outline: some View {
    if requiresSelection {
      if hasOptionalChildren {
        if hasExplicitID {
          List(records, id: \.id, selection: $requiredSelection, children: \.optionalChildren) {
            Text($0.title)
          }
        } else {
          List(records, selection: $requiredSelection, children: \.optionalChildren) {
            Text($0.title)
          }
        }
      } else {
        if hasExplicitID {
          List(records, id: \.id, selection: $requiredSelection, children: \.children) {
            Text($0.title)
          }
        } else {
          List(records, selection: $requiredSelection, children: \.children) { Text($0.title) }
        }
      }
    } else {
      if hasOptionalChildren {
        if hasExplicitID {
          List(records, id: \.id, selection: $optionalSelection, children: \.optionalChildren) {
            Text($0.title)
          }
        } else {
          List(records, selection: $optionalSelection, children: \.optionalChildren) {
            Text($0.title)
          }
        }
      } else {
        if hasExplicitID {
          List(records, id: \.id, selection: $optionalSelection, children: \.children) {
            Text($0.title)
          }
        } else {
          List(records, selection: $optionalSelection, children: \.children) { Text($0.title) }
        }
      }
    }
  }
}

@MainActor
private struct MultipleFocusUpdateOutlineList: View {
  @State private var selection: Set<Int> = [10]

  var body: some View {
    let records = [
      FocusUpdateOutlineRecord(
        id: 10, title: "Parent", lineCount: 1,
        children: [FocusUpdateOutlineRecord(id: 20, title: "Child", lineCount: 1)]),
      FocusUpdateOutlineRecord(id: 30, title: "Sibling", lineCount: 1),
    ]
    VStack(alignment: .leading, spacing: 0) {
      List(selection: $selection) {
        OutlineGroup(records, children: \.children) { Text($0.title) }
      }
      .listStyle(FocusUpdateOutlineListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 8)
      Text("members=\(selection.sorted())")
    }
  }
}

@MainActor
private struct UpdatingOutlineList: View {
  @State private var isUpdated = false
  @State private var selected: Int? = -1
  @State private var activated = "none"
  @State private var activationCount = 0

  private var descendants: [FocusUpdateOutlineRecord] {
    (0..<20).map { id in
      let hasUpdatedContent = id == 12 && isUpdated
      let title = hasUpdatedContent ? "Updated «\(id)»" : "Original «\(id)»"
      return FocusUpdateOutlineRecord(
        id: id, title: title, lineCount: hasUpdatedContent ? 3 : 1)
    }
  }

  var body: some View {
    let children = descendants
    let records = [
      FocusUpdateOutlineRecord(id: -1, title: "Root", lineCount: 1, children: children)
    ]
    VStack(alignment: .leading, spacing: 0) {
      List(
        selection: $selected,
        onActivate: { id in
          activated = children.first { $0.id == id }?.title ?? "Root"
          activationCount += 1
        }
      ) {
        OutlineGroup(records, children: \.children) { record in
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<record.lineCount, id: \.self) { line in
              if record.id == -1 {
                Text("Root")
              } else {
                Text("\(record.title):\(line)")
              }
            }
          }
        }
      }
      .listStyle(FocusUpdateOutlineListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 6)
      Text("selected=\(selected ?? -2)")
      Text("activated=\(activated) count=\(activationCount)")
      Text(isUpdated ? "version=updated" : "version=original")
    }
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      isUpdated = true
      return .handled
    }
  }
}

@MainActor
private struct RetiringOutline: View {
  let hosted: Bool
  @State private var isRemoved = false
  @State private var selected: Int? = nil
  @State private var activated = "none"
  @State private var activationCount = 0

  private var records: [FocusUpdateOutlineRecord] {
    let children =
      isRemoved
      ? [] : [FocusUpdateOutlineRecord(id: 20, title: "Retiring child", lineCount: 1)]
    return [
      FocusUpdateOutlineRecord(id: 10, title: "Parent", lineCount: 1, children: children),
      FocusUpdateOutlineRecord(id: 30, title: "Surviving sibling", lineCount: 1),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if hosted {
          List(records, selection: $selected, children: \.children) { record in
            row(record)
          }
          .listStyle(FocusUpdateOutlineListStyle())
          .scrollIndicators(.hidden)
        } else {
          ScrollView(.vertical) {
            OutlineGroup(records, children: \.children) { record in
              row(record)
            }
          }
        }
      }
      .frame(height: 8)
      Text("activated=\(activated) count=\(activationCount)")
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      isRemoved = true
      return .handled
    }
  }

  private func row(_ record: FocusUpdateOutlineRecord) -> some View {
    Button(record.title) {
      activated = record.title
      activationCount += 1
    }
    .buttonStyle(.plain)
  }
}

private struct FocusUpdateOutlineListStyle {}

extension FocusUpdateOutlineListStyle: ListStyle {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false,
      showsSectionSeparators: false)
  }
}
