import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 3: scroll-edge, arrow and proxy commands when
/// the content changes. Crosses STUI-1170/1171/1180 (wave 2) and STUI-1243
/// (wave 3). Contracts: `Scrolling.md:9-13, 105-110, 132-171, 206-212`,
/// `Collections.md:176-198`.
@MainActor
@Suite(.serialized)
struct AdversarialSetCDynamicScrollTests {
  // MARK: Far edges issued in the action that grows the content

  @Test func setC225FarEdgeAfterAppendAtBottomRevealsNewRows() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC225"), size: .init(width: 24, height: 8)
    ) { SetCAppendRoot(mode: .eager, model: model) }
    defer { h.shutdown() }
    try setCSettleAtFarEdge(h, model, .bottom)
    try #require(h.frame.contains("row 19"), "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    // STUI-1305 (repaired in wave 4): the edge re-resolves after the layout
    // that adds the rows.
    #expect(
      h.frame.contains("row 24"),
      "scrollTo(edge:) returned \(String(describing: model.lastResult))\n\(h.frame)")
  }

  @Test func setC226FarEdgeAfterAppendFromTopRevealsNewRows() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC226"), size: .init(width: 24, height: 8)
    ) { SetCAppendRoot(mode: .eager, model: model) }
    defer { h.shutdown() }
    try #require(h.frame.contains("row 00"))
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(h.frame.contains("row 24"), "\(h.frame)")
  }

  @Test func setC227LazyFarEdgeAfterAppendAtBottomRevealsNewRows() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC227"), size: .init(width: 24, height: 8)
    ) { SetCAppendRoot(mode: .lazy, model: model) }
    defer { h.shutdown() }
    try setCSettleAtFarEdge(h, model, .bottom)
    try #require(h.frame.contains("row 19"), "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(h.frame.contains("row 24"), "\(h.frame)")
  }

  @Test func setC228TrailingEdgeAfterAppendAtTrailingRevealsNewColumns() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC228"), size: .init(width: 24, height: 4)
    ) { SetCAppendRoot(mode: .horizontal, model: model) }
    defer { h.shutdown() }
    try setCSettleAtFarEdge(h, model, .trailing)
    try #require(h.frame.contains("c19"), "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(h.frame.contains("c24"), "\(h.frame)")
  }

  // MARK: Data-backed lists

  @Test func setC229ListEndFollowsExternalAppend() throws {
    let model = SetCDynModel()
    model.items = Array(0..<20)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC229"), size: .init(width: 24, height: 6)
    ) {
      List(model.items, id: \.self) { i in Text(setCRowLabel(i)) }
    }
    defer { h.shutdown() }
    _ = try h.focusText("row 00")
    _ = try h.pressKey(.init(.end))
    try #require(h.frame.contains("row 19"), "\(h.frame)")
    model.items.append(contentsOf: 20..<25)
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("row 24"), "\(h.frame)")
  }

  @Test func setC230ListFarEdgeAfterAppendAtEndRevealsNewRow() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC230"), size: .init(width: 24, height: 8)
    ) { SetCListAppendRoot(model: model, scrollsToAppended: false) }
    defer { h.shutdown() }
    _ = try h.focusText("row 00")
    _ = try h.pressKey(.init(.end))
    try #require(h.frame.contains("row 19"), "\(h.frame)")
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(h.frame.contains("row 20"), "\(h.frame)")
  }

  @Test func setC231ListScrollToAppendedIDRevealsRow() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC231"), size: .init(width: 24, height: 8)
    ) { SetCListAppendRoot(model: model, scrollsToAppended: true) }
    defer { h.shutdown() }
    try #require(h.frame.contains("row 00"))
    _ = try h.clickText("Append")
    _ = try h.render()
    // STUI-1306 (repaired in wave 4): an unresolved target retries after the
    // next resolve.
    #expect(h.frame.contains("row 20"), "\(h.frame)")
  }

  // Observation O2, repaired with STUI-1306 (wave 4): an eager ScrollView
  // reveals an identified row that the same action inserted, as a data List
  // does (Scrolling.md:134-140, 166-171).
  @Test func setC232EagerScrollToAppendedIDObservation() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC232"), size: .init(width: 24, height: 8)
    ) { SetCAppendRoot(mode: .eagerIdentified, model: model) }
    defer { h.shutdown() }
    _ = try h.clickText("Append")
    _ = try h.render()
    #expect(
      h.frame.contains("row 24"),
      "scrollTo(_:anchor:) returned \(String(describing: model.lastResult))\n\(h.frame)")
  }

  // MARK: Stored offsets outside the content range

  @Test func setC233UpArrowAfterContentShrinkMovesOneLine() throws {
    let model = SetCDynModel()
    model.count = 30
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC233"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    try #require(setCTopRow(h) == "row 24", "\(h.frame)")
    model.count = 20
    _ = try h.renderAfterExternalMutation()
    try #require(setCTopRow(h) == "row 14", "\(h.frame)")
    _ = try h.pressKey(.init(.arrowUp))
    #expect(setCTopRow(h) == "row 13", "offset \(model.offset) frame \(h.frame)")
  }

  @Test func setC234UpArrowAfterOutOfRangeWriteMovesOneLine() throws {
    let model = SetCDynModel()
    model.count = 30
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC234"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    model.offset = .init(x: 0, y: 10_000)
    _ = try h.renderAfterExternalMutation()
    try #require(setCTopRow(h) == "row 24", "\(h.frame)")
    _ = try h.pressKey(.init(.arrowUp))
    #expect(setCTopRow(h) == "row 23", "offset \(model.offset) frame \(h.frame)")
  }

  @Test func setC235ScrollByAtClampedBottomReportsNoMovement() throws {
    let model = SetCDynModel()
    model.count = 30
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC235"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    model.offset = .init(x: 0, y: 10_000)
    _ = try h.renderAfterExternalMutation()
    try #require(setCTopRow(h) == "row 24", "\(h.frame)")
    let moved = try #require(model.proxy).scrollBy(y: 1)
    _ = try h.render()
    #expect(setCTopRow(h) == "row 24")
    #expect(!moved, "scrollBy reported movement at the clamped bottom; offset \(model.offset)")
  }

  @Test func setC236DownArrowAfterNegativeWriteMovesOneLine() throws {
    let model = SetCDynModel()
    model.count = 30
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC236"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    model.offset = .init(x: 0, y: -50)
    _ = try h.renderAfterExternalMutation()
    try #require(setCTopRow(h) == "row 00", "\(h.frame)")
    _ = try h.pressKey(.init(.arrowDown))
    #expect(setCTopRow(h) == "row 01", "offset \(model.offset) frame \(h.frame)")
  }

  // MARK: Pins

  @Test func setC237EndReachesFooterAfterLazyStack() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC237"), size: .init(width: 24, height: 6)
    ) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { Text(setCRowLabel($0)) }
          }
          Text("footer")
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("footer"), "\(h.frame)")
  }

  @Test func setC238FarEdgeOnEmptyLazyStackDoesNotStick() throws {
    let model = SetCDynModel()
    model.count = 0
    model.lazy = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC238"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    #expect(try #require(model.proxy).scrollTo(edge: .bottom) == false)
    _ = try h.render()
    model.count = 30
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(model.offset.y == 0)
    #expect(setCTopRow(h) == "row 00", "\(h.frame)")
  }

  @Test func setC239ReinsertedScrollViewStartsAtTop() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC239"), size: .init(width: 24, height: 6)
    ) { SetCReinsertedRoot(model: model) }
    defer { h.shutdown() }
    #expect(try #require(model.proxy).scrollTo(edge: .bottom))
    model.show = false
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("absent"))
    model.show = true
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    #expect(setCTopRow(h) == "row 00", "\(h.frame)")
  }

  @Test func setC240HomeAfterEndOnVariableLazyStack() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC240"), size: .init(width: 20, height: 8)
    ) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<120, id: \.self) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    try #require(h.frame.contains("vrow 119"), "\(h.frame)")
    _ = try h.pressKey(.init(.home))
    #expect(h.frame.contains("vrow 0"), "\(h.frame)")
  }

  @Test func setC241SecondEndAfterRowGrowthReachesBottom() throws {
    let model = SetCDynModel()
    model.count = 30
    model.lazy = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC241"), size: .init(width: 24, height: 6)
    ) { SetCModelRowsRoot(model: model) }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    try #require(h.frame.contains("row 29"), "\(h.frame)")
    model.rowHeight = 2
    _ = try h.renderAfterExternalMutation()
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("row 29"), "\(h.frame)")
  }

  @Test func setC242EndReachesLazyStackBelowTallHeader() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC242"), size: .init(width: 24, height: 6)
    ) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("header").frame(height: 30, alignment: .top)
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<40, id: \.self) { Text(setCRowLabel($0)) }
          }
        }
      }.scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("row 39"), "\(h.frame)")
  }

  @Test func setC243TextFieldEndInScrollViewKeepsOffset() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC243"), size: .init(width: 24, height: 6)
    ) { SetCTextInScrollRoot(model: model, editor: false) }
    defer { h.shutdown() }
    _ = try h.focusText("abc")
    _ = try h.pressKey(.init(.end))
    _ = try h.pressKey(.init(.end))
    #expect(model.offset == .zero, "\(model.offset)")
    #expect(h.frame.contains("abc"))
  }

  @Test func setC244TextEditorEndInScrollViewKeepsOffset() throws {
    let model = SetCDynModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC244"), size: .init(width: 24, height: 6)
    ) { SetCTextInScrollRoot(model: model, editor: true) }
    defer { h.shutdown() }
    _ = try h.focusText("abc")
    _ = try h.pressKey(.init(.arrowDown))
    _ = try h.pressKey(.init(.end))
    _ = try h.pressKey(.init(.end))
    #expect(model.offset == .zero, "\(model.offset)")
  }
}

// MARK: - Fixtures

func setCRowLabel(_ index: Int) -> String {
  index < 10 ? "row 0\(index)" : "row \(index)"
}

@MainActor
private func setCTopRow<Content: View>(_ h: StressRuntimeHarness<Content>) -> String? {
  h.frame.split(separator: "\n", omittingEmptySubsequences: false)
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .first { $0.hasPrefix("row ") }
}

/// Sends the reader's scroll view to `edge` and renders until the far-edge
/// refinement settles (two frames at most for these extents).
@MainActor
private func setCSettleAtFarEdge<Content: View>(
  _ h: StressRuntimeHarness<Content>, _ model: SetCDynModel, _ edge: Edge
) throws {
  #expect(try #require(model.proxy).scrollTo(edge: edge))
  _ = try h.render()
  _ = try h.render()
}

@MainActor
private final class SetCDynModel {
  var offset = ScrollCellOffset.zero
  var proxy: ScrollViewProxy?
  var lastResult: Bool?
  var items: [Int] = []
  var count = 20
  var lazy = false
  var rowHeight = 1
  var show = true

  var binding: Binding<ScrollCellOffset> {
    Binding(get: { self.offset }, set: { self.offset = $0 })
  }

  func capture(_ proxy: ScrollViewProxy) -> Bool {
    self.proxy = proxy
    return true
  }
}

private enum SetCAppendMode { case eager, eagerIdentified, lazy, horizontal }

private struct SetCAppendRoot: View {
  let mode: SetCAppendMode
  let model: SetCDynModel
  @State private var count = 20

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      VStack(alignment: .leading, spacing: 0) {
        Button("Append") {
          count += 5
          switch mode {
          case .horizontal: model.lastResult = proxy.scrollTo(edge: .trailing)
          case .eagerIdentified: model.lastResult = proxy.scrollTo(24, anchor: .bottom)
          case .eager, .lazy: model.lastResult = proxy.scrollTo(edge: .bottom)
          }
        }
        switch mode {
        case .eager, .eagerIdentified:
          ScrollView(.vertical, position: model.binding) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<count, id: \.self) { i in Text(setCRowLabel(i)).id(i) }
            }
          }.scrollIndicators(.hidden).frame(width: 20, height: 6)
        case .lazy:
          ScrollView(.vertical, position: model.binding) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<count, id: \.self) { i in Text(setCRowLabel(i)) }
            }
          }.scrollIndicators(.hidden).frame(width: 20, height: 6)
        case .horizontal:
          ScrollView(.horizontal, position: model.binding) {
            HStack(spacing: 1) {
              ForEach(0..<count, id: \.self) { i in Text(i < 10 ? "c0\(i)" : "c\(i)") }
            }
          }.scrollIndicators(.hidden).frame(width: 12, height: 1)
        }
      }
    }
  }
}

private struct SetCListAppendRoot: View {
  let model: SetCDynModel
  let scrollsToAppended: Bool
  @State private var items = Array(0..<20)

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      VStack(alignment: .leading, spacing: 0) {
        Button("Append") {
          let next = items.count
          items.append(next)
          model.lastResult =
            scrollsToAppended ? proxy.scrollTo(next) : proxy.scrollTo(edge: .bottom)
        }
        List(items, id: \.self) { i in Text(setCRowLabel(i)) }.frame(height: 6)
      }
    }
  }
}

private struct SetCModelRowsRoot: View {
  let model: SetCDynModel

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      ScrollView(.vertical, position: model.binding) {
        if model.lazy {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<model.count, id: \.self) { i in
              Text(setCRowLabel(i)).frame(height: model.rowHeight, alignment: .top)
            }
          }
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<model.count, id: \.self) { i in Text(setCRowLabel(i)) }
          }
        }
      }.scrollIndicators(.hidden)
    }
  }
}

private struct SetCReinsertedRoot: View {
  let model: SetCDynModel

  var body: some View {
    ScrollViewReader { proxy in
      let _ = model.capture(proxy)
      if model.show {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<60, id: \.self) { i in Text(setCRowLabel(i)).frame(height: i < 20 ? 1 : 2) }
          }
        }.scrollIndicators(.hidden)
      } else {
        Text("absent")
      }
    }
  }
}

private struct SetCTextInScrollRoot: View {
  let model: SetCDynModel
  let editor: Bool
  @State private var text = "abc"
  @State private var multiline = "abc\ndef"

  var body: some View {
    ScrollView(.vertical, position: model.binding) {
      VStack(alignment: .leading, spacing: 0) {
        if editor {
          TextEditor(text: $multiline).frame(height: 4)
        } else {
          TextField("field", text: $text)
        }
        ForEach(0..<30, id: \.self) { i in Text(setCRowLabel(i)) }
      }
    }.scrollIndicators(.hidden)
  }
}
