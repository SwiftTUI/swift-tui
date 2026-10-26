import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD191–setD200: wide glyphs under
// table columns, scroll offsets and clips; a two-axis End beside automatic
// indicators. Brief 10.

private struct SetDHalfMask: Shape {
  func path(in rect: Rect) -> Path {
    Path(
      Rect(origin: rect.origin, size: .init(width: rect.size.width / 2, height: rect.size.height)))
  }
}

@MainActor
private enum SetDWide {
  static func raster<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> RasterSurface {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("setD", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface
  }

  /// Lead glyphs of row `y` with their cell columns, blanks omitted.
  static func glyphs(_ raster: RasterSurface?, row y: Int = 0) -> [(x: Int, glyph: Character)] {
    guard let raster, raster.cells.indices.contains(y) else { return [] }
    return raster.cells[y].enumerated().compactMap { x, cell in
      cell.isContinuation || cell.character == " " ? nil : (x, cell.character)
    }
  }
}

@MainActor
@Suite("Campaign F2 pass 2: wide glyphs under tables, scrolling and clips", .serialized)
struct AdversarialSetDWideGlyphModeTests {
  @Test("setD191: a three-cell column truncates a wide-glyph body cell as its header")
  func setD191ThreeCellColumnTruncation() throws {
    let raster = SetDWide.raster(
      Table(setDRows(1), columns: [TableColumn("界界", width: 3)]) { _ in Text("界界") },
      "191", width: 20, height: 6)
    let frame = raster.lines.joined(separator: "\n")
    #expect(!frame.contains("界界"), "\(frame)")
    #expect(frame.components(separatedBy: "界…").count - 1 == 2, "header and body: \(frame)")
  }

  @Test("setD192: a one-cell column truncates a wide glyph to the indicator")
  func setD192OneCellColumnTruncation() throws {
    let raster = SetDWide.raster(
      Table(setDRows(1), columns: [TableColumn("界", width: 1)]) { _ in Text("界") },
      "192", width: 20, height: 6)
    let frame = raster.lines.joined(separator: "\n")
    #expect(!frame.contains("界"), "\(frame)")
    #expect(frame.components(separatedBy: "…").count - 1 >= 2, "\(frame)")
  }

  @Test("setD193: hosted and flattened centred cells agree for a wide-glyph value")
  func setD193CentredColumnAgreement() throws {
    let columns = [TableColumn("C", width: 5, alignment: .center)]
    let hosted = SetDWide.raster(
      Table(setDRows(1), columns: columns) { _ in Text("日本") }.tableHeaders(.hidden),
      "193-hosted", width: 20, height: 4)
    let flattened = SetDWide.raster(
      Table(columns: columns) { TableRow { Text("日本") } }.tableHeaders(.hidden),
      "193-static", width: 20, height: 4)
    let hostedRow = try #require(hosted.lines.first { $0.contains("日本") }, "\(hosted.lines)")
    let staticRow = try #require(flattened.lines.first { $0.contains("日本") }, "\(flattened.lines)")
    #expect(hostedRow == staticRow, "hosted \(hostedRow) static \(staticRow)")
  }

  @Test("setD194: a click on the wide-glyph text of a low hidden-separator row selects it")
  func setD194WideGlyphLowRowClick() throws {
    let box = SetDSelection<String?>("表100")
    let rows = (0..<200).map { SetDRow(id: setDPadded($0, "表")) }
    let h = try SetDLiveHarness("194", size: .init(width: 30, height: 30)) {
      Table(rows, selection: box.binding, columns: [TableColumn("Name")]) { row in
        Text(row.id).listRowSeparator(.hidden)
      }.tableHeaders(.hidden).scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let visible = h.tokens(prefix: "表")
    try #require(visible.count >= 20, "\(h.frame)")
    let target = visible[visible.count - 2]
    try h.clickText(target)
    #expect(box.value == target)
  }

  @Test("setD195: a half-scrolled wide glyph is dropped, not split")
  func setD195HalfScrolledWideGlyph() throws {
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness("195", size: .init(width: 6, height: 1)) {
      ScrollView(.horizontal, position: offset.binding) { Text("日本語日本語") }
        .scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    offset.value = .init(x: 1, y: 0)
    try h.renderRoot()
    let atOne = SetDWide.glyphs(h.raster)
    #expect(atOne.first?.x == 1 && atOne.first?.glyph == "本", "\(atOne)")
    #expect(h.raster?.cells[0][0].character == " ")
    offset.value = .init(x: 2, y: 0)
    try h.renderRoot()
    let atTwo = SetDWide.glyphs(h.raster)
    #expect(atTwo.first?.x == 0 && atTwo.first?.glyph == "本", "\(atTwo)")
  }

  @Test("setD196: End on a lazy row of wide-glyph items shows the last item whole")
  func setD196LazyWideItemsEnd() throws {
    let h = try SetDLiveHarness("196", size: .init(width: 20, height: 1)) {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 1) {
          ForEach(0..<40, id: \.self) { Text("日\($0)") }
        }
      }
      .scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let scroll = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try h.focus(scroll)
    try h.key(.end)
    #expect(h.frame.contains("日39"), "\(h.frame)")
  }

  @Test("setD197: an overflowing centred wide-glyph line drops its straddling glyph")
  func setD197CentredOverflowClip() throws {
    let raster = SetDWide.raster(
      Text("日本語").fixedSize().frame(width: 3).clipped(), "197", width: 3, height: 1)
    let glyphs = SetDWide.glyphs(raster)
    #expect(
      glyphs.count == 1 && glyphs.first?.x == 1 && glyphs.first?.glyph == "本", "\(raster.lines)")
  }

  @Test("setD198: a half mask keeps only wholly covered wide glyphs at odd and even widths")
  func setD198HalfMaskOddEvenWidths() throws {
    let five = SetDWide.raster(
      Text("日本").frame(width: 5).clipShape(SetDHalfMask()), "198-5", width: 5, height: 1)
    let six = SetDWide.raster(
      Text("日本").frame(width: 6).clipShape(SetDHalfMask()), "198-6", width: 6, height: 1)
    #expect(SetDWide.glyphs(five).map(\.x) == [0], "\(five.lines)")
    #expect(SetDWide.glyphs(five).map(\.glyph) == ["日"])
    #expect(SetDWide.glyphs(six).map(\.x) == [1], "\(six.lines)")
    #expect(SetDWide.glyphs(six).map(\.glyph) == ["日"])
  }

  @Test("setD199: probe — ArrowDown on a focused nested button in a selectable table")
  func setD199NestedButtonArrowDown() throws {
    let box = SetDSelection<String?>("r001")
    let rows = setDRows(10)
    // Correction C7: give the button column room for its label.
    let h = try SetDLiveHarness("199", size: .init(width: 40, height: 14)) {
      Table(
        rows, selection: box.binding,
        columns: [TableColumn("Name", width: 6), TableColumn("Act", width: 12)]
      ) {
        row in
        Text(row.id)
        Button("act\(row.id.dropFirst())") {}
      }.tableHeaders(.hidden)
    }
    defer { h.shutdown() }
    try h.focusText("act002")
    let focused = h.runLoop.focusTracker.currentFocusIdentity
    try h.key(.arrowDown)
    print(
      "setD199 observation: selection \(box.value ?? "nil"), focus moved "
        + "\(h.runLoop.focusTracker.currentFocusIdentity != focused)")
    #expect(box.value != nil)
  }

  @Test("setD200: two-axis End reaches the last row when wide tail rows add an indicator")
  func setD200TwoAxisEndWithLateHorizontalIndicator() throws {
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness("200", size: .init(width: 20, height: 8)) {
      ScrollView([.horizontal, .vertical], position: offset.binding) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<60, id: \.self) { index in
            Text(index >= 55 ? "w\(index)" + String(repeating: "-", count: 40) : "w\(index)")
          }
        }
      }
    }
    defer { h.shutdown() }
    let scroll = try #require(
      h.runLoop.latestSemanticSnapshot.scrollRoutes.max {
        $0.viewportRect.size.height < $1.viewportRect.size.height
      }?.identity)
    try h.focus(scroll)
    try h.key(.end)
    #expect(h.frame.contains("w59"), "\(h.frame)\n\(offset.value)")
  }
}
