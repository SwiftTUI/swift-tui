@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCTrimMorphTests {
  @Test func setC101TrimmedFillExposesNoShapePathSlot() throws {
    let node = try #require(
      SetCTrim.shapeNode(
        SetCMorphShape(fraction: 0.25).trim(from: 0, to: 0.75).fill(), name: "setC101"))
    guard case .shape(let payload) = node.drawPayload, case .trimmed = payload.geometry else {
      Issue.record("expected a trimmed shape payload")
      return
    }
    let snapshot = AnimatableSnapshot.extract(from: node)
    setCKnown(
      "STUI-1129: a trimmed fill exposes no shapePath slot, so compatible path coordinates cannot morph; AnimatableSnapshot.extract captures .shapePath only for a bare .path geometry (AnimatableSnapshot.swift:75-78); contract: Shapes.md:127-132 with :254-258"
    ) {
      #expect(snapshot[.shapePath] != nil)
    }
  }

  @Test func setC102WholeTrimKeepsShapePathSlot() throws {
    let node = try #require(
      SetCTrim.shapeNode(
        SetCMorphShape(fraction: 0.25).trim(from: 0, to: 1).fill(), name: "setC102"))
    guard case .shape(let payload) = node.drawPayload, case .path = payload.geometry else {
      Issue.record("expected a bare path payload for the whole trim")
      return
    }
    #expect(AnimatableSnapshot.extract(from: node)[.shapePath] != nil)
  }

  @Test func setC103TrimmedFillSnapsInFlight() throws {
    let whole = try SetCTrim.midAnimationExtent(trimEnd: 1, name: "setC103-whole")
    #expect(whole > 4 && whole < 19, "control: a bare path morphs (max painted x \(whole))")
    let trimmed = try SetCTrim.midAnimationExtent(trimEnd: 0.75, name: "setC103-trimmed")
    setCKnown(
      "STUI-1129: in flight, a trimmed fill snaps to its destination geometry; the trimmed payload has no shapePath slot to interpolate and AnimationPropertyValueApplication applies .shapePath only to a bare .path (AnimationPropertyValueApplication.swift:294-302); contract: Shapes.md:127-132"
    ) {
      #expect(trimmed > 4 && trimmed < 19, "trimmed fill max painted x at 500 ms: \(trimmed)")
    }
  }

  @Test func setC104TrimmedFillStyleSlotPresent() throws {
    let node = try #require(
      SetCTrim.shapeNode(Rectangle().trim(from: 0, to: 0.5).fill(.red), name: "setC104"))
    #expect(AnimatableSnapshot.extract(from: node)[.shapeFillStyle] != nil)
  }

  @Test func setC105NestedTrimsCompose() {
    let nested = Rectangle().trim(from: 0, to: 0.5).trim(from: 0, to: 0.5)
    #expect(nested.trimStart == 0)
    #expect(nested.trimEnd == 0.25)
    let rect = Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
    #expect(nested.path(in: rect) == Rectangle().trim(from: 0, to: 0.25).path(in: rect))
  }

  @Test func setC106PublicTrimPathMeasuresCellUnits() throws {
    let rect = Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10))
    // The raster route: the quarter of a 10x10 outline at the estimated aspect
    // ratio (2) is the top edge plus 2.5 cells of the trailing edge.
    let aspect = RectangleStrokeTrack.snappedAspectRatio(CellPixelMetrics.estimated.aspectRatio)
    let painted = try #require(
      ShapeGeometry.trimmed(.rectangle, from: 0, to: 0.25)
        .path(in: rect, trimAspectRatio: aspect).boundingRect)
    try #require(painted.size.height > 2 && painted.size.height < 3, "\(painted)")
    let authored = try #require(Rectangle().trim(from: 0, to: 0.25).path(in: rect).boundingRect)
    setCKnown(
      "STUI-1208: TrimmedShape.path(in:) measures the outline in cell units while the raster measures physical units; TrimmedShape.swift:30-35 trims base.path(in:) without the aspect scaling ShapePayload.swift:108-115 applies (STUI-1112); contract: TrimmedShape.swift:9-10 'a share of the outline's physical length'"
    ) {
      #expect(abs(authored.size.height - painted.size.height) < 0.01, "\(authored)")
    }
  }

  @Test func setC107TrimmedContentShapeMissesPaintedCells() throws {
    let box = SetCTrimBox()
    // `contentShape` takes a `Path`; the public trimmed-shape path is the only
    // way to describe the filled outline (Pointer-And-Canvas.md:140-143).
    let outline = Rectangle().trim(from: 0, to: 0.25)
      .path(in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10)))
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC107"),
      size: .init(width: 10, height: 10)
    ) {
      Rectangle().trim(from: 0, to: 0.25).fill()
        .contentShape(outline)
        .onTapGesture { box.taps += 1 }
    }
    defer { h.shutdown() }
    let rows = h.frame.split(separator: "\n", omittingEmptySubsequences: false)
    try #require(rows.count >= 2)
    let row1: [Character] = Array(rows[1])
    let painted = row1.count >= 10 && row1[9] != Character(" ")
    try #require(painted, "cell (9, 1) must be painted: \(h.frame)")
    _ = try h.click(Point(x: 9.5, y: 1.5))
    setCKnown(
      "STUI-1208: a contentShape built from a trimmed shape does not cover the cells the trimmed fill paints; GestureViewModifier.swift:310 takes the cell-unit TrimmedShape.path(in:) while the raster trims in physical units (ShapePayload.swift:108-115); contract: Pointer-And-Canvas.md:140-143, TrimmedShape.swift:9-10"
    ) {
      #expect(box.taps == 1)
    }
  }
}

@MainActor
private final class SetCTrimBox {
  var taps = 0
}

@MainActor
private final class SetCTrimClock { var now = MonotonicInstant.now() }

@MainActor
private final class SetCTrimLog {
  var fraction: Binding<Double>?
}

/// A rectangle covering `fraction` of the unit width: four lines and a close,
/// so every fraction has the same element topology and can interpolate.
private struct SetCMorphShape: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    let right = rect.origin.x + rect.size.width * fraction
    let bottom = rect.origin.y + rect.size.height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

private struct SetCMorphRoot: View {
  @State private var fraction = 0.25
  let trimEnd: Double
  let log: SetCTrimLog

  var body: some View {
    let _ = capture()
    SetCMorphShape(fraction: fraction).trim(from: 0, to: trimEnd).fill()
  }

  private func capture() {
    log.fraction = $fraction
  }
}

@MainActor
private enum SetCTrim {
  static func shapeNode<V: View>(_ view: V, name: String) -> ResolvedNode? {
    let snapshot = DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetCTrim", name)),
      proposal: .init(width: 20, height: 4))
    return firstShape(in: snapshot.resolvedTree)
  }

  private static func firstShape(in node: ResolvedNode) -> ResolvedNode? {
    if case .shape = node.drawPayload { return node }
    for child in node.children {
      if let found = firstShape(in: child) { return found }
    }
    return nil
  }

  /// Mounts a 20x4 fill, animates the shape fraction 0.25 -> 1.0 over one
  /// second on an injected clock and returns the last painted column of the
  /// top row at 500 ms (4 at the start, 19 at the end, about 9 midway).
  static func midAnimationExtent(trimEnd: Double, name: String) throws -> Int {
    let log = SetCTrimLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity(name),
      size: .init(width: 20, height: 4)
    ) { SetCMorphRoot(trimEnd: trimEnd, log: log) }
    defer { h.shutdown() }
    try #require(maxPaintedX(in: h.frame, row: 0) == 4, "\(h.frame)")
    let controller = h.runLoop.renderer.internalAnimationController
    let clock = SetCTrimClock()
    h.runLoop.frameClock = { clock.now }
    let binding = try #require(log.fraction)
    return try withAnimationSinks(controller) {
      withAnimation(.linear(duration: .seconds(1))) { binding.wrappedValue = 1.0 }
      _ = try h.render()
      let target = clock.now.advanced(by: .milliseconds(500))
      var turns = 0
      while let wake = h.runLoop.scheduler.nextWakeInstant(after: clock.now), wake < target,
        turns < 256
      {
        clock.now = wake
        _ = try h.render()
        turns += 1
      }
      clock.now = target
      h.runLoop.scheduler.requestDeadline(clock.now)
      _ = try h.render()
      return maxPaintedX(in: h.frame, row: 0)
    }
  }

  static func maxPaintedX(in frame: String, row: Int) -> Int {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard row < rows.count else { return -1 }
    var last = -1
    for (index, character) in rows[row].enumerated() where character != " " {
      last = index
    }
    return last
  }
}
