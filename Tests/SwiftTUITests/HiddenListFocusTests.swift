import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct HiddenListFocusTests {
  @Test(
    "hidden list rows use current content and measurements on first reveal and revisit",
    arguments: HiddenListForm.allCases
  )
  private func hiddenChangesKeepNavigationAndActions(form: HiddenListForm) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HiddenListUpdates", form.rawValue),
      size: CellSize(width: 40, height: 14)
    ) {
      HiddenChangingList(form: form)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("item0-v0:0")
    for (version, targetHeight) in [(1, 3), (2, 2)] {
      let initialFocus = harness.runLoop.focusTracker.currentFocusIdentity
      #expect(!harness.frame.contains("item14-"), "the target changes while offscreen")
      _ = try harness.pressKey(KeyPress(.character("u"), modifiers: .ctrl))
      #expect(harness.frame.contains("version=\(version)"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == initialFocus)
      #expect(!harness.frame.contains("item14-"))

      for row in 1...14 {
        _ = try harness.pressKey(KeyPress(.arrowDown))
        try requireHiddenListRow(row, version: version, form: form, in: harness)
      }
      #expect(harness.frame.contains("item14-v\(version):\(targetHeight - 1)"))
      #expect(!harness.frame.contains("item14-v\(version - 1):"))
      let targetFocus = harness.runLoop.focusTracker.currentFocusIdentity
      _ = try harness.pressKey(KeyPress(.return))
      switch form {
      case .indexedMultiple:
        #expect(harness.frame.contains("checked=2,14"), "\(harness.frame)")
      case .indexedSingle, .builderRequired, .sectionedSingle:
        let count = version == 1 ? 1 : 3
        #expect(harness.frame.contains("activated=14-v\(version) count=\(count)"))
      }

      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireHiddenListRow(15, version: version, form: form, in: harness)
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireHiddenListRow(14, version: version, form: form, in: harness)
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == targetFocus)
      #expect(harness.frame.contains("item14-v\(version):\(targetHeight - 1)"))
      _ = try harness.pressKey(KeyPress(.return))
      switch form {
      case .indexedMultiple:
        #expect(harness.frame.contains("checked=2"), "\(harness.frame)")
        #expect(!harness.frame.contains("checked=2,14"))
      case .indexedSingle, .builderRequired, .sectionedSingle:
        #expect(harness.frame.contains("activated=14-v\(version) count=\(version * 2)"))
      }

      for row in (0..<14).reversed() {
        _ = try harness.pressKey(KeyPress(.arrowUp))
        try requireHiddenListRow(row, version: version, form: form, in: harness)
      }
    }
  }
}

private enum HiddenListForm: String, CaseIterable {
  case indexedSingle
  case indexedMultiple
  case builderRequired
  case sectionedSingle
}

@MainActor
private func requireHiddenListRow<Content: View>(
  _ row: Int, version: Int, form: HiddenListForm,
  in harness: StressRuntimeHarness<Content>
) throws {
  let label = "item\(row)-v\(version):0"
  try #require(harness.frame.contains(label), "the current row is visible:\n\(harness.frame)")
  let identity = try harness.focusIdentity(forText: label)
  #expect(harness.runLoop.focusTracker.currentFocusIdentity == identity, "\(harness.frame)")
  switch form {
  case .indexedMultiple:
    #expect(harness.frame.contains("checked=2"), "navigation preserves existing membership")
  case .indexedSingle, .sectionedSingle:
    #expect(harness.frame.contains("selected=\(row)"), "\(harness.frame)")
  case .builderRequired:
    #expect(harness.frame.contains("required=\(row)"), "\(harness.frame)")
  }
}

@MainActor
private struct HiddenChangingList: View {
  let form: HiddenListForm
  @State private var version = 0
  @State private var selected: Int? = 0
  @State private var required = 0
  @State private var checked: Set<Int> = [2]
  @State private var activated = "none"
  @State private var activationCount = 0

  var body: some View {
    let currentVersion = version
    let activate: @MainActor (Int) -> Void = { row in
      activated = "\(row)-v\(currentVersion)"
      activationCount += 1
    }
    VStack(alignment: .leading, spacing: 0) {
      Group {
        switch form {
        case .indexedSingle:
          List(0..<20, id: \.self, selection: $selected, onActivate: activate) { row in
            rowContent(row)
          }
        case .indexedMultiple:
          List(0..<20, id: \.self, selection: $checked) { row in rowContent(row) }
        case .builderRequired:
          List(selection: $required, onActivate: activate) {
            ForEach(0..<20, id: \.self) { row in rowContent(row).tag(row) }
          }
        case .sectionedSingle:
          List(selection: $selected, onActivate: activate) {
            Section("First") {
              ForEach(0..<10, id: \.self) { row in rowContent(row).tag(row) }
            }
            Section("Second") {
              ForEach(10..<20, id: \.self) { row in rowContent(row).tag(row) }
            }
          }
        }
      }
      .listStyle(HiddenListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 8, alignment: .topLeading)
      Text("version=\(version)")
      Text("selected=\(selected ?? -1) required=\(required)")
      Text("checked=\(checked.sorted().map { String($0) }.joined(separator: ","))")
      Text("activated=\(activated) count=\(activationCount)")
    }
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      version += 1
      return .handled
    }
  }

  private func rowContent(_ row: Int) -> some View {
    let lines: Int
    if version == 1 && row == 13 {
      lines = 6
    } else if row == 14 && version > 0 {
      lines = version == 1 ? 3 : 2
    } else {
      lines = 1
    }
    return Text((0..<lines).map { "item\(row)-v\(version):\($0)" }.joined(separator: "\n"))
  }
}

private struct HiddenListStyle: ListStyle {
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(showsRowSeparators: false, showsSectionSeparators: false)
  }
}
