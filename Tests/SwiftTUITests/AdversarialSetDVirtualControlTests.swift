import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 controls across a lazy viewport", .serialized)
struct AdversarialSetDVirtualControlTests {
  @Test(arguments: Array(81...90))
  func virtualControl(id: Int) throws {
    let kind = id - 80
    let rows = (0..<32).map { _ in SetDControlModel() }
    let position = SetDScrollPosition()
    let scrollID = testIdentity("setDScroll", String(id))
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 40, height: 10)
    ) {
      ScrollView(.vertical, position: position.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<32) { row in
            let _ = position.realizedRows.insert(row)
            VStack(alignment: .leading, spacing: 0) {
              Text("row \(row)")
              SetDControlForm(kind: kind, model: rows[row])
            }.frame(width: 30, height: 5, alignment: .topLeading)
          }
        }
      }.id(scrollID).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let realized = position.realizedRows.count
    try #require(realized > 0 && realized < rows.count)
    func subjectRegion() throws -> FocusRegion {
      let editorIDs = Set(
        h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
          $0.role == .textField || $0.role == .secureField || $0.role == .textEditor
        }.map(\.identity))
      let region = try #require(
        h.runLoop.focusTracker.focusRegions.first {
          kind >= 7 && kind <= 9 ? editorIDs.contains($0.identity) : $0.identity != scrollID
        })
      return region
    }
    func act() throws {
      let region = try subjectRegion()
      _ = try h.focus(region.identity)
      switch kind {
      case 1, 10: _ = try h.pressKey(.init(.return))
      case 2: _ = try h.pressKey(.init(.space))
      case 3, 4, 6: _ = try h.pressKey(.init(.arrowRight))
      case 5: _ = try h.pressKey(.init(.arrowDown))
      default:
        _ = try h.pressKey(.init(.character("z")))
      }
    }
    try #require(h.frame.contains("row 0"))
    if (7...9).contains(kind) {
      let editor = try subjectRegion()
      _ = try h.focus(editor.identity)
      try #require(h.runLoop.focusTracker.currentFocusIdentity == editor.identity)
      let beforeEnd = position.value
      _ = try h.pressKey(.init(.end))
      setDKnown("STUI-1180: no-op End must remain owned by the editor") {
        #expect(position.value == beforeEnd)
      }
      setDKnown("STUI-1180: ancestor scrolling must not evict focused input") {
        #expect(h.runLoop.focusTracker.currentFocusIdentity == editor.identity)
      }
      // Restore this fixture's viewport before the independent remount checks.
      // The assertions above retain the End-routing failure.
      position.value = beforeEnd
      _ = try h.renderAfterExternalMutation()
      _ = try h.focus(editor.identity)
    }
    try act()
    #expect(rows[0].mutations == 1)
    _ = try h.focus(scrollID)
    position.value = .init(x: 0, y: 100)
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("row 20"))
    #expect(!h.frame.contains("row 0"))
    try act()
    #expect(rows[20].mutations == 1)
    #expect(rows[0].mutations == 1)
    _ = try h.focus(scrollID)
    position.value = .zero
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("row 0"))
    try act()
    #expect(rows[0].mutations == 2)
    #expect(rows[20].mutations == 1)
    #expect(
      rows.enumerated().filter { $0.offset != 0 && $0.offset != 20 }.allSatisfy {
        $0.element.mutations == 0
      })
    switch kind {
    case 1, 3...6:
      #expect(rows[0].number == 2)
      #expect(rows[20].number == 1)
    case 2, 10:
      #expect(!rows[0].flag)
      #expect(rows[20].flag)
    default:
      #expect(rows[0].text == "seedzz")
      #expect(rows[20].text == "seedz")
    }
  }
}

@MainActor
private final class SetDScrollPosition {
  var value = ScrollCellOffset.zero
  var realizedRows: Set<Int> = []
  var binding: Binding<ScrollCellOffset> { .init(get: { self.value }, set: { self.value = $0 }) }
}
