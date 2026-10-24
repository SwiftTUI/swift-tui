@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCControlGeometryTests {
  @Test func setC153SliderLabelClickInertWheelAdjusts() throws {
    let box = SetCControlGeometryBox()
    box.value = 0.5
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC153"),
      size: .init(width: 40, height: 4)
    ) { Slider("Effort", value: box.double, in: 0...1) }
    defer { h.shutdown() }
    let label = try #require(h.point(forText: "Effort"))
    _ = try h.click(label)
    #expect(box.value == 0.5, "\(box.value)")
    _ = try h.scrollPointer(at: label, deltaY: 1)
    #expect(abs(abs(box.value - 0.5) - 0.1) < 1e-9, "\(box.value)")
  }

  @Test func setC154StepperLabelClickInertAffordanceSteps() throws {
    let box = SetCControlGeometryBox()
    box.count = 3
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC154"),
      size: .init(width: 40, height: 4)
    ) { Stepper("Retries", value: box.int, in: 0...10) }
    defer { h.shutdown() }
    _ = try h.clickText("Retries")
    #expect(box.count == 3)
    let increment = try #require(h.point(forText: "▶"), "\(h.frame)")
    _ = try h.click(increment)
    #expect(box.count == 4, "\(h.frame)")
  }

  @Test func setC155SpentAffordanceDoesNotFallThrough() throws {
    let box = SetCControlGeometryBox()
    box.count = 10
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC155"),
      size: .init(width: 40, height: 4)
    ) { Stepper("Retries", value: box.int, in: 0...10) }
    defer { h.shutdown() }
    let spent = try #require(h.point(forText: "▷"), "hollow increment at the bound: \(h.frame)")
    _ = try h.click(spent)
    #expect(box.count == 10)
    #expect(h.frame.contains("▷"), "\(h.frame)")
  }

  @Test func setC156StepperInDisclosureVetoesToggleUnderContentShape() throws {
    let box = SetCControlGeometryBox()
    box.count = 3
    box.expanded = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC156"),
      size: .init(width: 40, height: 8)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        DisclosureGroup("Details", isExpanded: box.expandedBinding) {
          Stepper("Retries", value: box.int, in: 0...10)
        }
      }
      .contentShape(CellRect(origin: .zero, size: .init(width: 40, height: 8)))
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Retries"), "\(h.frame)")
    _ = try h.clickText("Retries")
    #expect(box.expanded, "the keyboard-only stepper region vetoes the disclosure toggle")
    #expect(box.count == 3)
    _ = try h.clickText("Details")
    #expect(!box.expanded, "the label itself still toggles")
  }

  @Test func setC157SliderInDisclosureVetoesToggleWithoutContentShape() throws {
    let box = SetCControlGeometryBox()
    box.value = 0.5
    box.expanded = true
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC157"),
      size: .init(width: 40, height: 8)
    ) {
      DisclosureGroup("Details", isExpanded: box.expandedBinding) {
        Slider("Effort", value: box.double, in: 0...1)
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Effort"), "\(h.frame)")
    _ = try h.clickText("Effort")
    #expect(box.expanded, "the keyboard-only slider region vetoes the disclosure toggle")
    #expect(box.value == 0.5)
  }

  @Test func setC158OffsetContentThumbReachesTrackEnd() throws {
    let box = SetCControlGeometryBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC158"),
      size: .init(width: 20, height: 6)
    ) {
      ScrollView(.vertical, position: box.offset) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<20) { i in Text("row \(i)") }
        }.offset(y: 3)
      }
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    _ = try h.pressKey(.init(.end))
    try #require(box.offsetValue.y > 0, "End must move: \(h.frame)")
    let thumbRows = SetCControlGeometry.rows(containing: "▐", in: h.frame)
    #expect(
      thumbRows.contains(5), "thumb rows \(thumbRows) must reach the last track row:\n\(h.frame)")
  }

  @Test func setC159HorizontalPaddedContentThumbReachesEnd() throws {
    let box = SetCControlGeometryBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC159"),
      size: .init(width: 20, height: 4)
    ) {
      ScrollView(.horizontal, position: box.offset) {
        HStack(spacing: 0) {
          ForEach(0..<10) { i in Text("col\(i)") }
        }.padding(.trailing, 4)
      }
    }
    defer { h.shutdown() }
    _ = try h.pressKey(.init(.tab))
    _ = try h.pressKey(.init(.end))
    try #require(box.offsetValue.x > 0, "End must move: \(h.frame)")
    let columns = SetCControlGeometry.columns(containing: "▂", in: h.frame)
    #expect(columns.contains(19) || columns.contains(18), "thumb columns \(columns):\n\(h.frame)")
  }

  @Test func setC160TrimmedQuarterFillIsPhysical() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC160"),
      size: .init(width: 10, height: 10)
    ) { Rectangle().trim(from: 0, to: 0.25).fill() }
    defer { h.shutdown() }
    let cells = SetCControlGeometry.paintedCells(in: h.frame)
    #expect(cells.contains(.init(x: 9, y: 1)), "\(h.frame)")
    #expect(!cells.contains(.init(x: 9, y: 6)), "\(h.frame)")
    #expect(!cells.contains(.init(x: 0, y: 1)), "\(h.frame)")
  }

  @Test func setC161TrimmedClipMatchesFill() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC161"),
      size: .init(width: 10, height: 10)
    ) {
      VStack(spacing: 0) {
        ForEach(0..<10) { _ in Text("##########") }
      }.clipShape(Rectangle().trim(from: 0, to: 0.25))
    }
    defer { h.shutdown() }
    let cells = SetCControlGeometry.paintedCells(in: h.frame)
    #expect(cells.contains(.init(x: 9, y: 1)), "\(h.frame)")
    #expect(!cells.contains(.init(x: 9, y: 6)), "\(h.frame)")
    #expect(!cells.contains(.init(x: 0, y: 1)), "\(h.frame)")
  }

  @Test(arguments: [Double.nan, .infinity, -.infinity])
  func setC162NonfinitePathAPIsReject(bad: Double) {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addQuadCurve(to: Point(x: 4, y: 0), control: Point(x: 2, y: bad))
    path.addLine(to: Point(x: 4, y: 4))
    path.closeSubpath()
    #expect(!path.contains(Point(x: 3, y: 1)))
    #expect(path.boundingRect == nil)
    #expect(path.flattened().isEmpty)
    #expect(path.trimmedPath(from: 0, to: 0.5).elements.isEmpty)
  }

  @Test func setC163NaNAnimatableDataBlocksInterpolation() {
    let square = Path(Rect(origin: Point(x: 0, y: 0), size: Size(width: 4, height: 4)))
    var poisoned = square
    var points = square.animatableData.elements
    points[1] = AnimatablePair(.nan, points[1].second)
    poisoned.animatableData = AnimatableArray(points)
    #expect(!square.isInterpolable(to: poisoned))
    #expect(!poisoned.isInterpolable(to: square))
    #expect(square.interpolated(to: poisoned, progress: 0.5) == poisoned)
    let shifted = square.translatedBy(dx: 1, dy: 0)
    #expect(square.isInterpolable(to: shifted))
    #expect(square.interpolated(to: shifted, progress: .infinity) == shifted)
  }

  @Test func setC164OversizedContentShapeInstallsNoRegion() throws {
    let box = SetCControlGeometryBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC164"),
      size: .init(width: 12, height: 3)
    ) {
      Text("tap here")
        .contentShape(
          Path(Rect(origin: Point(x: 6e18, y: 0), size: Size(width: 6e18, height: 1)))
        )
        .onTapGesture { box.taps += 1 }
    }
    defer { h.shutdown() }
    _ = try h.clickText("tap here")
    #expect(box.taps == 0)
  }

  @Test func setC165TrimRejectsPathWithNonfiniteSubpath() {
    var path = Path(Rect(origin: Point(x: 0, y: 0), size: Size(width: 4, height: 4)))
    path.move(to: Point(x: .infinity, y: 0))
    path.addLine(to: Point(x: 5, y: 5))
    #expect(path.trimmedPath(from: 0, to: 0.5).elements.isEmpty)
    #expect(path.boundingRect == nil)
  }
}

@MainActor
private final class SetCControlGeometryBox {
  var value = 0.0
  var count = 0
  var taps = 0
  var expanded = false
  var offsetValue = ScrollCellOffset.zero
  var expandedBinding: Binding<Bool> {
    .init(get: { self.expanded }, set: { self.expanded = $0 })
  }
  var double: Binding<Double> {
    .init(get: { self.value }, set: { self.value = $0 })
  }
  var int: Binding<Int> {
    .init(get: { self.count }, set: { self.count = $0 })
  }
  var offset: Binding<ScrollCellOffset> {
    .init(get: { self.offsetValue }, set: { self.offsetValue = $0 })
  }
}

private enum SetCControlGeometry {
  static func rows(containing glyph: Character, in frame: String) -> [Int] {
    frame.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
      .compactMap { index, row in row.contains(glyph) ? index : nil }
  }

  static func columns(containing glyph: Character, in frame: String) -> [Int] {
    var columns: [Int] = []
    for row in frame.split(separator: "\n", omittingEmptySubsequences: false) {
      for (index, character) in row.enumerated() where character == glyph {
        columns.append(index)
      }
    }
    return columns
  }

  static func paintedCells(in frame: String) -> Set<CellPoint> {
    var cells = Set<CellPoint>()
    for (y, row) in frame.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      for (x, character) in row.enumerated() where character != " " {
        cells.insert(CellPoint(x: x, y: y))
      }
    }
    return cells
  }
}
