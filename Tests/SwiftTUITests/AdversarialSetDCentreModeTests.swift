import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD141–setD150: the centre rule
// (Authoring-Views.md:92-99) under absolute positioning, custom layout,
// scroll anchors, presentation cards, wide glyphs and live resize. Brief 05.

@MainActor
private enum SetDCentre {
  static func raster<V: View>(_ view: V, _ name: String, width: Int, height: Int) -> RasterSurface {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("setD", name)),
      proposal: .init(width: width, height: height)
    ).rasterSurface
  }

  /// The first painted (non-blank) cell's position.
  static func firstInk(in raster: RasterSurface) -> CellPoint? {
    for (y, row) in raster.cells.enumerated() {
      if let x = row.firstIndex(where: { !$0.isContinuation && $0.character != " " }) {
        return CellPoint(x: x, y: y)
      }
    }
    return nil
  }

  /// The bounding box of box-drawing card border glyphs.
  static func cardBounds(in raster: RasterSurface) -> CellRect? {
    let corners: Set<Character> = ["┌", "╭", "┏", "╔"]
    let closing: Set<Character> = ["┘", "╯", "┛", "╝"]
    var origin: CellPoint?
    var end: CellPoint?
    for (y, row) in raster.cells.enumerated() {
      for (x, cell) in row.enumerated() {
        if origin == nil, corners.contains(cell.character) { origin = CellPoint(x: x, y: y) }
        if closing.contains(cell.character) { end = CellPoint(x: x, y: y) }
      }
    }
    guard let origin, let end else { return nil }
    return CellRect(
      origin: origin,
      size: .init(width: end.x - origin.x + 1, height: end.y - origin.y + 1))
  }
}

private struct SetDUnplacedLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ())
    -> LayoutSize
  {
    .init(width: 10, height: 1)
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache: inout ()
  ) {}
}

@MainActor
private final class SetDPresentFlag {
  var presented = false
  var binding: Binding<Bool> { .init(get: { self.presented }, set: { self.presented = $0 }) }
}

@MainActor
@Suite("Campaign F2 pass 2: centre rounding under other features", .serialized)
struct AdversarialSetDCentreModeTests {
  @Test("setD141: .position centres an odd child where a frame centres it")
  func setD141PositionMatchesFrameCentring() throws {
    let positioned = SetDCentre.raster(
      Text("abcde").position(x: 5, y: 0).frame(width: 10, height: 1, alignment: .topLeading),
      "141-position", width: 10, height: 1)
    let framed = SetDCentre.raster(
      Text("abcde").frame(width: 10, height: 1), "141-frame", width: 10, height: 1)
    let framedX = try #require(SetDCentre.firstInk(in: framed)?.x)
    try #require(framedX == 2, "the frame rule: \(framed.lines)")
    setDKnown(
      "NEW-9: .position(x:y:) places an odd child half a cell trailing where frame centring places it leading; the position placement subtracts the floored half extent (LayoutEngine+PlacementRequests.swift:368-380); contract: Authoring-Views.md:92-99, 8236b3f2; adjacent STUI-1212"
    ) {
      #expect(SetDCentre.firstInk(in: positioned)?.x == framedX, "\(positioned.lines)")
    }
  }

  @Test("setD142: vertical .position centres an odd child where a frame centres it")
  func setD142VerticalPositionMatchesFrameCentring() throws {
    let column = VStack(spacing: 0) {
      Text("x")
      Text("y")
      Text("z")
    }
    let positioned = SetDCentre.raster(
      column.position(x: 0, y: 3).frame(width: 1, height: 6, alignment: .topLeading),
      "142-position", width: 1, height: 6)
    let framed = SetDCentre.raster(
      column.frame(width: 1, height: 6), "142-frame", width: 1, height: 6)
    let framedY = try #require(SetDCentre.firstInk(in: framed)?.y)
    try #require(framedY == 1, "the frame rule: \(framed.lines)")
    setDKnown(
      "NEW-9: .position(x:y:) places an odd child half a cell trailing where frame centring places it leading; the position placement subtracts the floored half extent (LayoutEngine+PlacementRequests.swift:368-380); contract: Authoring-Views.md:92-99, 8236b3f2; adjacent STUI-1212"
    ) {
      #expect(SetDCentre.firstInk(in: positioned)?.y == framedY, "\(positioned.lines)")
    }
  }

  @Test("setD143: an unplaced custom-layout subview centres like ZStack (odd child)")
  func setD143UnplacedOddSubviewCentresLikeZStack() throws {
    let custom = SetDCentre.raster(
      SetDUnplacedLayout { Text("abcde") }, "143-layout", width: 10, height: 1)
    let stacked = SetDCentre.raster(
      ZStack { Text("abcde") }.frame(width: 10, height: 1), "143-zstack", width: 10, height: 1)
    let expected = try #require(SetDCentre.firstInk(in: stacked)?.x)
    try #require(expected == 2, "\(stacked.lines)")
    setDKnown(
      "NEW-10: an unplaced custom-layout subview of odd width sits one cell right of ZStack's centre; defaultPlacement puts the floored centre guide at width / 2 (CustomLayoutPlacementGeometry.swift:37-63); contract: Authoring-Views.md:92-99; adjacent STUI-1212, STUI-1267"
    ) {
      #expect(SetDCentre.firstInk(in: custom)?.x == expected, "\(custom.lines)")
    }
  }

  @Test("setD144: an unplaced custom-layout subview centres like ZStack (even child)")
  func setD144UnplacedEvenSubviewCentresLikeZStack() throws {
    let custom = SetDCentre.raster(
      SetDUnplacedLayout { Text("abcd") }, "144-layout", width: 10, height: 1)
    let stacked = SetDCentre.raster(
      ZStack { Text("abcd") }.frame(width: 10, height: 1), "144-zstack", width: 10, height: 1)
    let expected = try #require(SetDCentre.firstInk(in: stacked)?.x)
    #expect(SetDCentre.firstInk(in: custom)?.x == expected, "\(custom.lines)")
  }

  /// Returns the viewport line on which row 20's first line lands after
  /// `scrollTo(_:anchor: .center)`, for a scroll view or a data list of
  /// two-line rows in a seven-line viewport.
  private func centredRowLine(list: Bool, name: String) throws -> Int? {
    let rows = setDRows(40)
    let h = try SetDLiveHarness(name, size: .init(width: 20, height: 8)) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("go") { _ = proxy.scrollTo(list ? "r020" : "t20", anchor: .center) }
          if list {
            List(rows) { row in
              VStack(alignment: .leading, spacing: 0) {
                Text(row.id)
                Text(row.id + "b")
              }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .frame(height: 7)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                  VStack(alignment: .leading, spacing: 0) {
                    Text(row.id)
                    Text(row.id + "b")
                  }
                  .id("t\(Int(row.id.dropFirst())!)")
                }
              }
            }
            .scrollIndicators(.hidden)
            .frame(height: 7)
          }
        }
      }
    }
    defer { h.shutdown() }
    try h.clickText("go")
    guard let cell = h.cell(of: "r020 ") ?? h.cell(of: "r020") else { return nil }
    return cell.y - 1
  }

  @Test("setD145: a list's centre anchor agrees with a scroll view's for a two-line row")
  func setD145ListCentreAnchorAgreesWithScrollView() throws {
    let scrollLine = try #require(try centredRowLine(list: false, name: "145-scroll"))
    try #require(scrollLine == 2, "scroll view line \(scrollLine)")
    let listLine = try centredRowLine(list: true, name: "145-list")
    setDKnown(
      "NEW-11: a List's scrollTo(_:anchor: .center) puts a two-line row at line 3 of a seven-line window where a ScrollView puts it at line 2; the collection rounds (visible - rowLines) * 0.5 half away from zero (CollectionScrollState.swift:321-345) while the scroll view aligns (length - 1) * u (LocalScrollPositionRegistry.swift:1036-1047); contract: Scrolling.md:134-140, 166-170, Authoring-Views.md:92-99"
    ) {
      #expect(listLine == scrollLine, "list line \(String(describing: listLine))")
    }
  }

  @Test("setD146: a scroll view's centre anchor follows the centre rule for a two-line row")
  func setD146ScrollViewCentreAnchorFollowsRule() throws {
    #expect(try centredRowLine(list: false, name: "146") == 2)
  }

  @Test("setD147: a sheet card is centred by the frame rule at even and odd sizes")
  func setD147SheetCardCentring() throws {
    for size in [CellSize(width: 40, height: 12), CellSize(width: 41, height: 13)] {
      let flag = SetDPresentFlag()
      let h = try SetDLiveHarness("147-\(size.width)", size: size) {
        Text("base").sheet(isPresented: flag.binding) { Text("sheet body text") }
      }
      defer { h.shutdown() }
      flag.presented = true
      try h.renderRoot()
      let raster = try #require(h.raster)
      let card = try #require(SetDCentre.cardBounds(in: raster), "\(h.frame)")
      #expect(card.origin.x == (size.width - card.size.width) / 2, "\(size): \(card)\n\(h.frame)")
      #expect(card.origin.y == (size.height - card.size.height) / 2, "\(size): \(card)\n\(h.frame)")
    }
  }

  @Test("setD148: a centre anchor to an unmeasured variable-height lazy row centres it")
  func setD148LazyCentreAnchorCentresUnmeasuredRow() throws {
    let h = try SetDLiveHarness("148", size: .init(width: 20, height: 10)) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("go") { _ = proxy.scrollTo(100, anchor: .center) }
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<120, id: \.self) { index in
                Text("v\(index)")
                  .frame(height: index < 40 ? 1 : 3, alignment: .topLeading)
                  .id(index)
              }
            }
          }
          .scrollIndicators(.hidden)
          .frame(height: 9)
        }
      }
    }
    defer { h.shutdown() }
    try h.clickText("go")
    let cell = try #require(h.cell(of: "v100"), "\(h.frame)")
    #expect(cell.y - 1 == 3, "row 100 at viewport line \(cell.y - 1)\n\(h.frame)")
  }

  @Test("setD149: a centred VStack places wide-glyph lines by their cell width")
  func setD149WideGlyphCentring() throws {
    let raster = SetDCentre.raster(
      VStack(alignment: .center, spacing: 0) {
        Text("日")
        Text("abc")
        Text("日本")
        Text("日本語")
      }, "149", width: 6, height: 4)
    let columns = ["日", "abc", "日本", "日本語"].enumerated().map { index, text in
      raster.cells[index].firstIndex {
        !$0.isContinuation && String($0.character) == String(text.first!)
      }
    }
    #expect(columns == [2, 1, 1, 0], "\(raster.lines)")
  }

  @Test("setD150: centred text tracks live resizes 10 → 11 → 10 columns")
  func setD150CentreAcrossResizes() throws {
    let h = try SetDLiveHarness("150", size: .init(width: 10, height: 2)) {
      Text("abcde").frame(maxWidth: .infinity)
    }
    defer { h.shutdown() }
    var columns: [Int?] = [h.cell(of: "abcde")?.x]
    try h.resize(.init(width: 11, height: 2))
    columns.append(h.cell(of: "abcde")?.x)
    try h.resize(.init(width: 10, height: 2))
    columns.append(h.cell(of: "abcde")?.x)
    #expect(columns == [2, 3, 2], "\(columns)")
  }
}
