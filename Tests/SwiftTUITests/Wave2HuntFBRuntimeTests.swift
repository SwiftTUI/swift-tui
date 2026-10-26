// Wave-2 regression hunt, part FB (STUI-1165): composed neighbours of the
// FW-C (6d877a7d), FW-E (ef4ce264) and FW-F (78de6446) repairs — trimmed
// public paths and content shapes, trimmed fill morphing, hyperlinked trailing
// blanks and OSC 8 encoding, custom path strokes at the clip and sampling
// limits, SGR clamps, wheel deltas at value controls, capability detection and
// presentation refusals. The brief and hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-2-hunt/fb/. Wave 3
// FW3-G (STUI-1244, STUI-1245, STUI-1247, STUI-1248) promoted this file's
// guards and added neighbours wave3g01-05, 09, 12 and 13; its evidence is in
// docs/reports/evidence/2026-10-24-campaign-two-wave-3/fw3-g/.
import Foundation
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private let w2fbAspect = RectangleStrokeTrack.snappedAspectRatio(
  CellPixelMetrics.estimated.aspectRatio)

/// A custom shape defined only by normalized unit-rect geometry.
private struct W2FBPathShape: InsettableShape {
  var pathValue: Path
  var geometry: ShapeGeometry { .path(BoxedPath(pathValue), .nonZero) }
}

/// A custom shape whose `path(in:)` is a fixed 4 x 4 square, whatever the rect.
private struct W3GFixedSquareShape: Shape {
  func path(in rect: Rect) -> Path {
    Path(Rect(origin: rect.origin, size: Size(width: 4, height: 4)))
  }
}

/// `W2FBFarPointShape` with the far point at any `y`.
private struct W3GFarPointShape: Shape {
  var farY: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + 10, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + 10, y: farY))
    return path
  }
}

/// A custom shape whose own `path(in:)` holds one far, finite point.
private struct W2FBFarPointShape: Shape {
  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + 10, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + 10, y: 1e308))
    return path
  }
}

private func w2fbLine(_ from: Point, _ to: Point) -> Path {
  var path = Path()
  path.move(to: from)
  path.addLine(to: to)
  return path
}

private func w2fbBrailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value, scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

/// Renders a 4 x 2 cell frame and returns the Braille dot count of each cell.
@MainActor
private func w2fbDotRows(_ view: some View, _ name: String) -> [[Int]] {
  let snapshot = DefaultRenderer().render(
    view.frame(width: 4, height: 2), context: .init(identity: testIdentity("W2FB", name)))
  return snapshot.rasterSurface.cells.map { $0.map(w2fbBrailleDotCount) }
}

/// Renders a 4 x 2 cell frame and returns each cell's Braille dot mask.
@MainActor
private func w2fbDotMasks(_ view: some View, _ name: String) -> [[UInt32]] {
  let snapshot = DefaultRenderer().render(
    view.frame(width: 4, height: 2), context: .init(identity: testIdentity("W2FB", name)))
  return snapshot.rasterSurface.cells.map { row in
    row.map { cell in
      guard let scalar = cell.character.unicodeScalars.first?.value, scalar >= 0x2800,
        scalar <= 0x28FF
      else {
        return 0
      }
      return scalar - 0x2800
    }
  }
}

private func w2fbOpen(_ destination: String) -> String {
  "\u{001B}]8;;\(destination)\u{001B}\\"
}
private let w2fbClose = "\u{001B}]8;;\u{001B}\\"

private final class W2FBMockTerminalController: TerminalControlling {
  private let writesStorage = LockedBox<[String]>([])

  var writes: [String] { writesStorage.value }

  func isATTY(_: Int32) -> Bool { true }

  func enterRawMode(input _: Int32, output _: Int32) throws -> TerminalModeSnapshot {
    TerminalModeSnapshot()
  }

  func restore(_: TerminalModeSnapshot, input _: Int32, output _: Int32) throws {}

  func windowSize(of _: Int32) throws -> CellSize { .init(width: 80, height: 24) }

  func write(_ output: String, to _: Int32) throws {
    writesStorage.withLock { $0.append(output) }
  }

  func read(from _: Int32, maxBytes _: Int, timeoutMilliseconds _: Int) throws -> [UInt8] { [] }
}

// MARK: - Presentation probes

@MainActor
private final class W2FBPresentationLog {
  var alert: PresentationCoordinatorHandle<PromptPresentationItem>?
  var dialog: PresentationCoordinatorHandle<PromptPresentationItem>?
  var items: [String: PromptPresentationItem] = [:]
  /// Operations the probe performs inside its next resolve, then forgets.
  var duringNextResolve: [@MainActor (W2FBPresentationLog) -> Void] = []
}

@MainActor
private func w2fbPromptItem(
  title: String,
  dialog: Bool = false,
  in context: ResolveContext
) -> PromptPresentationItem {
  let spec = dialog ? confirmationDialogPromptPresentationSpec() : alertPromptPresentationSpec()
  return PromptPresentationItem(
    id: presentationAttachmentID(
      for: testIdentity("W2FBItem", title), token: spec.token),
    title: title,
    surface: spec.prepareSurface(context),
    actionPayloads: portalAttachmentDeclaredBuilderChildren(from: Button("Close") {}, edge: nil),
    messagePayloads: portalAttachmentDeclaredBuilderChildren(from: Text("Body."), edge: nil),
    contentPayloads: [],
    dismiss: {}
  )
}

/// Captures the live handles and named items during resolve, and runs the
/// operations queued for this resolve inside the view update.
private struct W2FBPresentationProbe: PrimitiveView, IterativeResolvableView {
  let log: W2FBPresentationLog
  let titles: [(title: String, dialog: Bool)]

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    log.alert = context.environmentValues.alertPresentationCoordinator
    log.dialog = context.environmentValues.confirmationDialogPresentationCoordinator
    for entry in titles where log.items[entry.title] == nil {
      log.items[entry.title] = w2fbPromptItem(title: entry.title, dialog: entry.dialog, in: context)
    }
    let operations = log.duringNextResolve
    log.duringNextResolve = []
    for operation in operations { operation(log) }
    return Text("Workspace").resolveElementsWork(in: context)
  }
}

@MainActor
private func w2fbRender(
  _ renderer: DefaultRenderer, _ probe: W2FBPresentationProbe
) -> RenderSnapshot {
  renderer.render(
    probe, context: .init(identity: testIdentity("W2FBPresentation")),
    proposal: .init(width: 40, height: 10))
}

private func w2fbSurface(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

@MainActor
private func w2fbMutationWarnings(_ snapshot: RenderSnapshot) -> [RuntimeIssue] {
  snapshot.diagnostics.runtime.issues.filter {
    $0.code == PresentationMutationGuard.mutationDuringViewUpdateCode
  }
}

@MainActor
private final class W2FBTapBox {
  var count = 0
}

@MainActor
private final class W2FBControlBox {
  var slider = 5.0
  var stepper = 5
}

@MainActor
@Suite("Wave-2 hunt FB: drawing, terminal output, capability and presentation neighbours")
struct Wave2HuntFBRuntimeTests {
  // MARK: - FW-C STUI-1208: trimmed public paths and the painted fill

  @Test("w2fb001: a trimmed Circle's public path is the outline its fill paints in a wide frame")
  func w2fb001TrimmedCirclePathMatchesPaintedFillInWideFrame() throws {
    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    // The route the painted fill takes: `ShapeGeometry.resolved(in:)`.
    let painted = ShapeGeometry.trimmed(.circle, from: 0, to: 0.5)
      .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect)
    let paintedBox = try #require(painted.boundingRect)
    try #require(abs(paintedBox.size.width - 20) < 0.01, "\(paintedBox)")
    let authored = try #require(Circle().trim(from: 0, to: 0.5).path(in: rect).boundingRect)
    // STUI-1244 (repaired): the public path traces the painted fill's
    // stretched outline. Contract: ShapePayload.swift:131-134 and 6d877a7d.
    #expect(
      abs(authored.origin.x - paintedBox.origin.x) < 0.01
        && abs(authored.size.width - paintedBox.size.width) < 0.01,
      "authored \(authored) painted \(paintedBox)")
  }

  @Test("w2fb002: a content shape from a trimmed Circle's path covers the cells its fill paints")
  func w2fb002TrimmedCircleContentShapeCoversPaintedCells() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "w2fb002")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 10)
    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = LocalPointerHandlerRegistry()
    ctx.localGestureRegistry = LocalGestureRegistry()
    ctx.localGestureStateRegistry = LocalGestureStateRegistry()

    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    let painted = ShapeGeometry.trimmed(.circle, from: 0, to: 0.5)
      .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect)
    let artifacts = DefaultRenderer().render(
      Circle().trim(from: 0, to: 0.5).fill()
        .contentShape(Circle().trim(from: 0, to: 0.5).path(in: rect))
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 10)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    func hits(_ point: Point) -> Bool {
      region.contains(.subCell(location: point, source: .nativePixels, metrics: metrics))
    }
    let probe = Point(x: 2.5, y: 6.5)
    try #require(painted.contains(probe), "the painted half-ellipse covers \(probe)")
    var disagreements: [CellPoint] = []
    for y in 0..<10 {
      for x in 0..<20 {
        let center = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
        if hits(center) != painted.contains(center) {
          disagreements.append(CellPoint(x: x, y: y))
        }
      }
    }
    let probeHit = hits(probe)

    // The same view in the composed runtime: a click inside both outlines is
    // delivered (precondition), then a click on painted cell (2, 6).
    let taps = W2FBTapBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fb002"), size: .init(width: 20, height: 10)
    ) {
      Circle().trim(from: 0, to: 0.5).fill()
        .contentShape(Circle().trim(from: 0, to: 0.5).path(in: rect))
        .onTapGesture { taps.count += 1 }
        .frame(width: 20, height: 10)
    }
    defer { h.shutdown() }
    let frameRows = try h.render().split(separator: "\n", omittingEmptySubsequences: false)
    try #require(frameRows.count > 6 && Array(frameRows[6]).count > 2, "\(h.frame)")
    try #require(Array(frameRows[6])[2] != " ", "cell (2, 6) must be painted:\n\(h.frame)")
    _ = try h.click(Point(x: 10.5, y: 6.5))
    try #require(taps.count == 1, "a click inside both outlines is delivered")
    _ = try h.click(probe)
    let deliveredOnPaintedCell = taps.count == 2
    // STUI-1244 (repaired): the content shape covers the painted cells.
    // Contract: 6d877a7d, Pointer-And-Canvas.md:140-145.
    #expect(disagreements.isEmpty, "\(disagreements.count) cells disagree: \(disagreements)")
    #expect(probeHit)
    #expect(deliveredOnPaintedCell, "taps \(taps.count)")
  }

  @Test("w2fb003: in a square frame a trimmed Circle's public path equals the painted route")
  func w2fb003TrimmedCircleSquareFrameMatchesPaintedFill() {
    let rect = Rect(origin: .zero, size: .init(width: 10, height: 10))
    for (from, to) in [(0.0, 0.5), (0.125, 0.625)] {
      let painted = ShapeGeometry.trimmed(.circle, from: from, to: to)
        .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect)
      #expect(Circle().trim(from: from, to: to).path(in: rect) == painted, "\(from)...\(to)")
    }
  }

  @Test("w2fb004: other bases trim identically on the public and painted routes in a wide frame")
  func w2fb004TrimmedNonCircleBasesMatchPaintedFillInWideFrame() {
    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    var triangle = Path()
    triangle.move(to: Point(x: 0, y: 1))
    triangle.addLine(to: Point(x: 0.5, y: 0))
    triangle.addLine(to: Point(x: 1, y: 1))
    triangle.closeSubpath()
    let custom = W2FBPathShape(pathValue: triangle)
    let cases: [(String, Path, ShapeGeometry)] = [
      ("ellipse", Ellipse().trim(from: 0.1, to: 0.6).path(in: rect), Ellipse().geometry),
      ("capsule", Capsule().trim(from: 0.1, to: 0.6).path(in: rect), Capsule().geometry),
      (
        "rounded", RoundedRectangle(cornerRadius: 2).trim(from: 0.1, to: 0.6).path(in: rect),
        RoundedRectangle(cornerRadius: 2).geometry
      ),
      ("rectangle", Rectangle().trim(from: 0.1, to: 0.6).path(in: rect), Rectangle().geometry),
      ("custom", custom.trim(from: 0.1, to: 0.6).path(in: rect), custom.geometry),
    ]
    for (name, authored, base) in cases {
      let painted = ShapeGeometry.trimmed(base, from: 0.1, to: 0.6)
        .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect)
      #expect(authored == painted, "\(name)")
    }
  }

  // MARK: - FW-C STUI-1129: trimmed fill morphing

  @Test("w2fb005: a trimmed fill morphs its path while its trim interval snaps")
  func w2fb005TrimmedFillMorphsPathWhileIntervalSnaps() throws {
    func node(_ geometry: ShapeGeometry) -> ResolvedNode {
      ResolvedNode(
        identity: Identity(components: ["w2fb005"]), kind: .view("Path"),
        drawPayload: .shape(.init(geometry: geometry, operation: .fill(style: .color(.white)))))
    }
    let from = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let to = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let start = node(.trimmed(.path(BoxedPath(from), .nonZero), from: 0, to: 0.25))
    let end = node(.trimmed(.path(BoxedPath(to), .nonZero), from: 0, to: 0.75))
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    controller.processResolvedTree(start, transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(end, transaction: transaction, timestamp: time)
    var sample = end
    _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
    guard case .shape(let payload) = sample.drawPayload,
      case .trimmed(let base, let trimFrom, let trimTo) = payload.geometry,
      case .path(let boxed, _) = base
    else {
      Issue.record("unexpected sample geometry \(sample.drawPayload)")
      return
    }
    #expect(trimFrom == 0 && trimTo == 0.75, "the interval takes the destination value")
    let width = try #require(boxed.path.boundingRect?.size.width)
    #expect(abs(width - 0.6) < 1e-9, "sampled width \(width) at 100 of 200 ms")
  }

  // MARK: - FW-C STUI-1150, STUI-1152: hyperlinked trailing blanks and encoding

  @Test("w2fb006: an incremental frame writes trailing blanks that gain a link")
  func w2fb006IncrementalUpdateWritesLinkedTrailingBlanks() throws {
    let link = "https://example.com/a"
    let plain = RasterSurface(size: .init(width: 12, height: 1), lines: ["go"])
    var linked = plain
    linked.cells[0][10].hyperlink = link
    linked.cells[0][11].hyperlink = link
    let planner = TerminalPresentationPlanner(capabilityProfile: .trueColor)

    let gain = planner.plan(previousSurface: plain, currentSurface: linked)
    #expect(gain.strategy == .incremental)
    let gained = try #require(gain.rowBatches.first)
    #expect(gained.renderedBatch == w2fbOpen(link) + "  " + w2fbClose)
    #expect(!gained.canLowerToEraseToEndOfLine(surfaceWidth: 12))

    let loss = planner.plan(previousSurface: linked, currentSurface: plain)
    let lost = try #require(loss.rowBatches.first)
    #expect(lost.renderedBatch == "  ")
    #expect(lost.canLowerToEraseToEndOfLine(surfaceWidth: 12))

    let controller = W2FBMockTerminalController()
    let host = TerminalHost(
      inputFileDescriptor: 0, outputFileDescriptor: 1, fallbackSize: .init(width: 80, height: 24),
      controller: controller, capabilityProfile: .trueColor, usesTerminalEditOperations: true)
    _ = try host.present(plain)
    try host.drainPendingPresentation()
    let before = controller.writes.count
    let metrics = try host.present(linked)
    try host.drainPendingPresentation()
    let written = controller.writes[before...].joined()
    #expect(metrics.strategy == .incremental)
    #expect(written.contains(w2fbOpen(link) + "  " + w2fbClose), "\(written.debugDescription)")
    #expect(!written.contains("\u{001B}[K"))
  }

  @Test("w2fb007: a link destination that sanitizes to empty is trimmed and emits nothing")
  func w2fb007ControlOnlyLinkDestinationTrimsAndEmitsNothing() {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    var trailing = RasterSurface(size: .init(width: 12, height: 1), lines: ["go"])
    trailing.cells[0][10].hyperlink = "\u{001B}\u{0007}"
    trailing.cells[0][11].hyperlink = "\u{001B}\u{0007}"
    #expect(renderer.render(trailing) == "go")
    let text = RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [[RasterCell(character: "X", hyperlink: "\u{001B}\u{0007}")]])
    #expect(renderer.render(text) == "X")
  }

  @Test(
    "w2fb008: destination bytes at the printable-ASCII edges and format scalars encode correctly")
  func w2fb008DestinationEncodingAtRangeEdges() {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [
        [
          RasterCell(
            character: "X", hyperlink: "https://e.x/a b~\u{7F}\u{A0}\u{2028}\u{FEFF}\u{200B}")
        ]
      ])
    #expect(
      renderer.render(surface)
        == w2fbOpen("https://e.x/a b~%C2%A0%E2%80%A8%EF%BB%BF%E2%80%8B") + "X" + w2fbClose)
  }

  @Test("w2fb009: one link run continues from text into linked trailing blanks")
  func w2fb009LinkRunContinuesIntoLinkedTrailingBlanks() {
    let link = "https://example.com/r"
    var surface = RasterSurface(size: .init(width: 6, height: 1), lines: ["ab"])
    for column in 1...3 { surface.cells[0][column].hyperlink = link }
    #expect(
      TerminalSurfaceRenderer(capabilityProfile: .trueColor).render(surface)
        == "a" + w2fbOpen(link) + "b  " + w2fbClose)
  }

  // MARK: - FW-E STUI-741: custom path strokes at the clip and sampling limits

  @Test(
    "w2fb012: a custom path stroke whose finite segment spans the Double range draws its visible part"
  )
  func w2fb012PathStrokeSpanningTheDoubleRangeDrawsVisiblePart() throws {
    let near = W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: 1, y: 0.5)))
    let dash = StrokeStyle(dash: [1.2, 1.2])
    let nearSolid = w2fbDotRows(near.stroke(Color.white), "w2fb012-near")
    let nearDashed = w2fbDotRows(near.stroke(Color.white, style: dash), "w2fb012-near-dash")
    try #require(nearSolid == [[0, 0, 0, 0], [2, 2, 2, 2]], "\(nearSolid)")
    try #require(nearDashed == [[0, 0, 0, 0], [2, 1, 1, 2]], "\(nearDashed)")
    // Unit x -2e307...2e307 is +-1.4e308 subpixels: finite endpoints whose
    // difference is not.
    let far = W2FBPathShape(pathValue: w2fbLine(Point(x: -2e307, y: 0.5), Point(x: 2e307, y: 0.5)))
    let farSolid = w2fbDotRows(far.stroke(Color.white), "w2fb012-far")
    let farDashed = w2fbDotRows(far.stroke(Color.white, style: dash), "w2fb012-far-dash")
    // STUI-1245 (repaired): the segment is clipped in a halved coordinate
    // space instead of being skipped. Contract: Path.swift:72-80.
    #expect(farSolid == nearSolid, "\(farSolid)")
    // Corrected oracle (FW3-G oracle-notes.md): the visible part lies 7e307
    // cell widths into the 2.4-unit dash pattern, far below Double's
    // resolution there, so the contract implies no dash phase. It implies
    // that the visible part is stroked and that the dash only removes dots.
    let farDashedMasks = w2fbDotMasks(far.stroke(Color.white, style: dash), "w2fb012-far-dash-mask")
    let farSolidMasks = w2fbDotMasks(far.stroke(Color.white), "w2fb012-far-mask")
    #expect(farDashed.joined().reduce(0, +) > 0, "\(farDashed)")
    #expect(
      zip(farDashedMasks.joined(), farSolidMasks.joined()).allSatisfy { $0 & ~$1 == 0 },
      "dashed \(farDashedMasks) solid \(farSolidMasks)")
  }

  @Test(
    "w2fb014: custom path strokes at and beyond the Int.max / 8 clip limit match the in-range path")
  func w2fb014PathStrokeAtTheClipLimitMatchesInRangePath() {
    let limit = Double(Int.max / 8) / 7
    let nearRow = w2fbDotRows(
      W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: 1, y: 0.5)))
        .stroke(Color.white), "w2fb014-near-row")
    let nearColumn = w2fbDotRows(
      W2FBPathShape(pathValue: w2fbLine(Point(x: 0.5, y: 0), Point(x: 0.5, y: 1)))
        .stroke(Color.white), "w2fb014-near-column")
    #expect(nearRow == [[0, 0, 0, 0], [2, 2, 2, 2]])
    for end in [limit, 1e18] {
      let row = W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: end, y: 0.5)))
      #expect(w2fbDotRows(row.stroke(Color.white), "w2fb014-row-\(end)") == nearRow, "x \(end)")
      let column = W2FBPathShape(pathValue: w2fbLine(Point(x: 0.5, y: 0), Point(x: 0.5, y: end)))
      #expect(
        w2fbDotRows(column.stroke(Color.white), "w2fb014-column-\(end)") == nearColumn, "y \(end)")
    }
  }

  @Test(
    "w2fb015: a dashed stroke on either side of the 65,536-sample cap dashes like the near path")
  func w2fb015DashedStrokeAtTheSampleCapMatchesNearPath() {
    let dash = StrokeStyle(dash: [1.2, 1.2])
    let near = w2fbDotRows(
      W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: 1, y: 0.5)))
        .stroke(Color.white, style: dash), "w2fb015-near")
    #expect(near == [[0, 0, 0, 0], [2, 1, 1, 2]])
    // 7 subpixels per unit: 4,681 is 32,767 subpixels (full grid) and 4,682 is
    // 32,774 (sampled near the canvas).
    for length in [4_681.0, 4_682.0] {
      let long = W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: length, y: 0.5)))
      #expect(
        w2fbDotRows(long.stroke(Color.white, style: dash), "w2fb015-\(length)") == near,
        "length \(length)")
    }
  }

  @Test("w2fb016: a trimmed stroke of a capped segment keeps the first half of its visible part")
  func w2fb016TrimmedStrokeAtTheSampleCapMatchesNearPath() {
    // Corrected oracle (corrections.md C1): the one-unit path is not a valid
    // reference. Its last subpixel's nearest sample sits at the track length,
    // which `StrokeMask.isOn` wraps to position 0, so that dot survives a trim
    // from 0 (`[[0, 0, 0, 0], [2, 2, 0, 1]]`; StrokeTrack.swift:93-107, not in
    // the wave-2 diff). Both capped segments are compared with the contract
    // value and with each other instead.
    var rows: [[[Int]]] = []
    for length in [4_681.0, 4_682.0] {
      let long = W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: length, y: 0.5)))
      let trimmed = w2fbDotRows(
        long.trim(from: 0, to: 0.5 / length).stroke(Color.white), "w2fb016-\(length)")
      #expect(trimmed == [[0, 0, 0, 0], [2, 2, 0, 0]], "length \(length)")
      rows.append(trimmed)
    }
    #expect(rows[0] == rows[1])
  }

  @Test("w2fb027: a dashed stroke whose far end meets the stroke clip dashes like the near path")
  func w2fb027DashedStrokeAcrossTheStrokeClipLimit() {
    let dash = StrokeStyle(dash: [1.2, 1.2])
    let near = w2fbDotRows(
      W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: 1, y: 0.5)))
        .stroke(Color.white, style: dash), "w2fb027-near")
    for end in [Double(Int.max / 8) / 7, 1e18] {
      let far = W2FBPathShape(pathValue: w2fbLine(Point(x: 0, y: 0.5), Point(x: end, y: 0.5)))
      #expect(
        w2fbDotRows(far.stroke(Color.white, style: dash), "w2fb027-\(end)") == near, "end \(end)")
    }
  }

  // MARK: - FW-E STUI-823, STUI-863: SGR clamps and wheel deltas

  @Test("w2fb024: SGR coordinates 2^24 and 2^24 + 1 decode identically")
  func w2fb024SGRClampIsContinuousAtTheBound() {
    func event(_ bytes: String, _ mode: MouseCoordinateMode) -> InputEvent? {
      var parser = TerminalInputParser(mouseCoordinateMode: mode)
      return parser.feed(Array(bytes.utf8)).first
    }
    let atBound = "\u{001B}[<0;16777216;16777216M"
    let pastBound = "\u{001B}[<0;16777217;16777218M"
    let modes: [MouseCoordinateMode] = [
      .cells,
      .pixels(
        metrics: CellPixelMetrics(width: 1, height: 1, source: .reported), source: .terminalPixels),
      .pixels(
        metrics: CellPixelMetrics(width: 8, height: 16, source: .reported), source: .terminalPixels),
    ]
    for mode in modes {
      let bound = event(atBound, mode)
      #expect(bound != nil)
      #expect(bound == event(pastBound, mode), "\(mode)")
    }
    guard case .mouse(let cells)? = event(pastBound, .cells),
      case .mouse(let pixels)? = event(pastBound, modes[2])
    else {
      Issue.record("no pointer events")
      return
    }
    #expect(cells.location.cell == CellPoint(x: 16_777_215, y: 16_777_215))
    #expect(pixels.location.location == Point(x: 2_097_151.875, y: 1_048_575.9375))
  }

  @Test("w2fb025: a Slider and a Stepper clamp Int.min and Int.max wheel deltas to their bounds")
  func w2fb025ValueControlsClampIntEdgeWheelDeltas() throws {
    let box = W2FBControlBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("w2fb025"), size: .init(width: 40, height: 6)
    ) {
      VStack(alignment: .leading, spacing: 1) {
        Slider(
          "Volume", value: .init(get: { box.slider }, set: { box.slider = $0 }), in: 0...10,
          step: 1)
        Stepper("Count", value: .init(get: { box.stepper }, set: { box.stepper = $0 }), in: 0...10)
      }
    }
    defer { h.shutdown() }
    _ = try h.render()
    func wheel(_ label: String, _ deltaY: Int) throws {
      let point = try #require(h.point(forText: label), "no '\(label)' in\n\(h.frame)")
      _ = h.runLoop.handle(
        RuntimeEvent.input(
          .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: deltaY), location: point))))
      _ = try h.render()
    }
    try wheel("Volume", -1)
    try wheel("Count", -1)
    try #require(box.slider == 6 && box.stepper == 6, "slider \(box.slider) stepper \(box.stepper)")
    try wheel("Volume", .min)
    try wheel("Count", .min)
    #expect(box.slider == 10 && box.stepper == 10, "slider \(box.slider) stepper \(box.stepper)")
    try wheel("Volume", .max)
    try wheel("Count", .max)
    #expect(box.slider == 0 && box.stepper == 0, "slider \(box.slider) stepper \(box.stepper)")
  }

  // MARK: - FW-F STUI-1224, STUI-1225: capability detection

  @Test(
    "w2fb029: xterm-direct2, -direct16 and -direct256 take the hyperlink markers xterm-direct takes"
  )
  func w2fb029DirectXtermVariantsTakeTheHyperlinkMarkers() {
    let markers: [[String: String]] = [
      ["VTE_VERSION": "7600"], ["TERM_PROGRAM": "vscode"], ["WT_SESSION": "abc"],
    ]
    var refused: [String] = []
    for marker in markers {
      let control = TerminalCapabilityProfile.detectPOSIXTerminal(
        environment: marker.merging(["TERM": "xterm-direct"]) { $1 }, isTTY: true)
      #expect(control.supportsHyperlinks, "xterm-direct \(marker)")
      for term in ["xterm-direct2", "xterm-direct16", "xterm-direct256"] {
        let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
          environment: marker.merging(["TERM": term]) { $1 }, isTTY: true)
        #expect(profile.colorLevel == .trueColor, "\(term)")
        if !profile.supportsHyperlinks { refused.append("\(term) \(marker)") }
      }
    }
    // STUI-1247 (repaired): the numbered direct entries are generic xterm
    // entries. Contract: Environment-Variables.md:35-44.
    #expect(refused.isEmpty, "\(refused)")
  }

  @Test("w2fb030: a direct-colour xterm keeps WezTerm's refinement")
  func w2fb030DirectEntryKeepsEmulatorRefinement() {
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct", "TERM_PROGRAM": "WezTerm", "LANG": "C.UTF-8"],
      isTTY: true)
    #expect(profile.colorLevel == .trueColor)
    #expect(profile.supportsHyperlinks)
    #expect(profile.supportsSynchronizedOutput)
    #expect(profile.supportsMouseReporting)
  }

  @Test("w2fb031: probe — an empty WT_SESSION on a generic xterm")
  func w2fb031EmptyWindowsTerminalSessionMarker() {
    let empty = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-256color", "WT_SESSION": ""], isTTY: true)
    let emptyProgram = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-256color", "TERM_PROGRAM": ""], isTTY: true)
    // Observation, recorded in the hypotheses: the marker's presence, not its
    // value, enables hyperlinks; an empty TERM_PROGRAM reads as absent.
    #expect(empty.supportsHyperlinks)
    #expect(!emptyProgram.supportsHyperlinks)
  }

  @Test("w2fb032: the configuration layer keeps direct colour and its documented overrides")
  func w2fb032ConfigurationLayerKeepsDirectColor() {
    func level(_ environment: [String: String], tty: Bool) -> TerminalCapabilityProfile.ColorLevel {
      let configuration = RuntimeConfiguration.detect(environment: environment, isStdoutTTY: tty)
      return TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: tty)
        .applying(configuration).colorLevel
    }
    #expect(level(["TERM": "foot-direct"], tty: true) == .trueColor)
    #expect(level(["TERM": "foot-direct", "NO_COLOR": "1"], tty: true) == .none)
    #expect(level(["TERM": "foot-direct", "FORCE_COLOR": "1"], tty: false) == .ansi16)
  }

  @Test("w2fb033: a detected direct-colour xterm writes 24-bit SGR")
  func w2fb033DetectedDirectEntryEmitsTwentyFourBitColor() {
    let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct", "LANG": "C.UTF-8"], isTTY: true)
    let surface = RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [
        [
          RasterCell(
            character: "X",
            style: .init(foregroundColor: Color(red: 10 / 255, green: 20 / 255, blue: 30 / 255)))
        ]
      ])
    let rendered = TerminalSurfaceRenderer(capabilityProfile: profile).render(surface)
    #expect(rendered.contains("38;2;10;20;30"), "\(rendered.debugDescription)")
  }

  @Test("w2fb038: probe — the Windows arm's WT_SESSION rule against a named emulator")
  func w2fb038WindowsArmSessionMarkerAgainstNamedEmulator() {
    let environment = ["TERM": "xterm-256color", "TERM_PROGRAM": "tmux", "WT_SESSION": "abc"]
    let windows = TerminalCapabilityProfile.detectWindowsConsole(
      environment: environment, isTTY: true)
    let posix = TerminalCapabilityProfile.detectPOSIXTerminal(environment: environment, isTTY: true)
    // The hunt recorded the arms disagreeing here (Windows: both on). STUI-1313
    // applies the documented rule on Windows too: a nonempty TERM_PROGRAM
    // outranks the inherited WT_SESSION, so both arms leave both off.
    #expect(!windows.supportsHyperlinks && !windows.supportsSynchronizedOutput)
    #expect(!posix.supportsHyperlinks && !posix.supportsSynchronizedOutput)
  }

  // MARK: - FW-F STUI-1226: presentation mutation during update

  @Test("w2fb034: a dismiss refused during a view update stays refused")
  func w2fb034RefusedDismissDuringUpdateStaysRefused() throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let log = W2FBPresentationLog()
    let probe = W2FBPresentationProbe(log: log, titles: [("Kept prompt", false)])
    _ = w2fbRender(renderer, probe)
    let alert = try #require(log.alert)
    let item = try #require(log.items["Kept prompt"])
    alert.present(item)
    let shown = w2fbRender(renderer, probe)
    try #require(w2fbSurface(shown).contains("Kept prompt"), "\(w2fbSurface(shown))")
    log.duringNextResolve = [{ $0.alert?.dismiss(id: item.id) }]
    let refused = w2fbRender(renderer, probe)
    let later = w2fbRender(renderer, probe)
    let warnings = w2fbMutationWarnings(refused)
    #expect(warnings.count == 1)
    #expect(
      warnings.first?.message.hasPrefix(
        "AlertPresentationCoordinator.dismiss(id:) must not be called during view update.")
        == true, "\(warnings.map(\.message))")
    #expect(w2fbSurface(refused).contains("Kept prompt"), "\(w2fbSurface(refused))")
    #expect(w2fbSurface(later).contains("Kept prompt"), "\(w2fbSurface(later))")
    #expect(w2fbMutationWarnings(later).isEmpty)
  }

  @Test("w2fb035: two refusals in one view update record two warnings and neither applies")
  func w2fb035TwoRefusalsInOneUpdateWarnTwice() throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let log = W2FBPresentationLog()
    let probe = W2FBPresentationProbe(
      log: log, titles: [("Refused alert", false), ("Refused dialog", true)])
    _ = w2fbRender(renderer, probe)
    let alertItem = try #require(log.items["Refused alert"])
    let dialogItem = try #require(log.items["Refused dialog"])
    log.duringNextResolve = [
      { $0.alert?.present(alertItem) }, { $0.dialog?.present(dialogItem) },
    ]
    let refused = w2fbRender(renderer, probe)
    let later = w2fbRender(renderer, probe)
    let messages = w2fbMutationWarnings(refused).map(\.message)
    #expect(messages.count == 2, "\(messages)")
    #expect(messages.contains { $0.hasPrefix("AlertPresentationCoordinator.present(_:)") })
    #expect(
      messages.contains { $0.hasPrefix("ConfirmationDialogPresentationCoordinator.present(_:)") })
    for snapshot in [refused, later] {
      #expect(!w2fbSurface(snapshot).contains("Refused alert"))
      #expect(!w2fbSurface(snapshot).contains("Refused dialog"))
    }
    #expect(w2fbMutationWarnings(later).isEmpty)
  }

  @Test("w2fb036: an in-flight draft replays the allowed operation and not the refused one")
  func w2fb036InFlightDraftReplaysOnlyTheAllowedOperation() throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    let state = PresentationPortalState()
    var environment = EnvironmentValues()
    state.injectHandles(
      into: &environment, hostIdentity: testIdentity("w2fb036", "Host"), invalidator: nil)
    let handle = environment.alertPresentationCoordinator
    let context = ResolveContext(identity: testIdentity("w2fb036"), environmentValues: environment)
    let refusedItem = w2fbPromptItem(title: "Refused", in: context)
    let allowedItem = w2fbPromptItem(title: "Allowed", in: context)

    let draft = state.makeDraft()
    // Refused first: had it been applied, it would head the alert queue.
    ViewUpdateGuard.withViewUpdate { handle.present(refusedItem) }
    handle.present(allowedItem)
    draft.commit()

    let entries = state.overlayEntries()
    #expect(entries.count == 1)
    #expect(entries.first?.portalEntryID == allowedItem.portalEntryID)
    #expect(
      ImperativeRuntimeIssueQueue.drain().map(\.code) == [
        PresentationMutationGuard.mutationDuringViewUpdateCode
      ])
  }

  @Test("w2fb037: an item refused during an update presents later from outside it")
  func w2fb037ItemRefusedDuringUpdatePresentsLaterOutsideIt() throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    let renderer = DefaultRenderer()
    let log = W2FBPresentationLog()
    let probe = W2FBPresentationProbe(log: log, titles: [("Second try", false)])
    _ = w2fbRender(renderer, probe)
    let item = try #require(log.items["Second try"])
    log.duringNextResolve = [{ $0.alert?.present(item) }]
    let refused = w2fbRender(renderer, probe)
    #expect(w2fbMutationWarnings(refused).count == 1)
    #expect(!w2fbSurface(refused).contains("Second try"))
    let alert = try #require(log.alert)
    alert.present(item)
    let shown = w2fbRender(renderer, probe)
    #expect(w2fbSurface(shown).contains("Second try"), "\(w2fbSurface(shown))")
    #expect(w2fbMutationWarnings(shown).isEmpty)
  }

  // MARK: - Cross-group

  @Test(
    "w2fb039: a VTE-detected profile writes encoded linked trailing blanks; an old VTE trims them")
  func w2fb039DetectedVTEWritesEncodedLinkedTrailingBlanks() {
    var surface = RasterSurface(size: .init(width: 12, height: 1), lines: ["go"])
    surface.cells[0][10].hyperlink = "https://例え.jp/é"
    surface.cells[0][11].hyperlink = "https://例え.jp/é"
    func rendered(_ version: String) -> String {
      let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
        environment: ["TERM": "xterm-256color", "VTE_VERSION": version, "LANG": "C.UTF-8"],
        isTTY: true)
      return TerminalSurfaceRenderer(capabilityProfile: profile).render(surface)
    }
    #expect(
      rendered("7600")
        == "go" + String(repeating: " ", count: 8)
        + w2fbOpen("https://%E4%BE%8B%E3%81%88.jp/%C3%A9") + "  " + w2fbClose)
    #expect(rendered("4999") == "go")
  }

  @Test("w2fb040: the physical trim of a finite path with a far point keeps the trimmed outline")
  func w2fb040PhysicalTrimOfFarFinitePathKeepsOutline() {
    let rect = Rect(origin: .zero, size: .init(width: 10, height: 10))
    let whole = W2FBFarPointShape().path(in: rect)
    #expect(whole.boundingRect != nil, "the base outline is finite")
    // Control: the cell-unit trim that TrimmedShape.path(in:) returned before
    // 6d877a7d keeps the outline's first half.
    let cellUnit = whole.trimmedPath(from: 0, to: 0.5).boundingRect
    #expect(
      cellUnit.map { $0.origin == .zero && $0.size.width == 10 } == true,
      "\(String(describing: cellUnit))")
    let trimmed = W2FBFarPointShape().trim(from: 0, to: 0.5).path(in: rect)
    let box = trimmed.boundingRect
    // STUI-1248 (repaired): the trim shrinks the outline by a power of two
    // when scaling y would overflow. Contract: TrimmedShape.swift:5-10.
    #expect(box != nil, "trimmed bounding rect \(String(describing: box))")
    #expect(box.map { $0.origin == .zero && $0.size.width == 10 } == true)
  }

  // MARK: - Wave 3 FW3-G neighbours (STUI-1244, STUI-1245, STUI-1247, STUI-1248)

  @Test("wave3g01: a trimmed Circle's public path is the painted route in every frame")
  func wave3g01TrimmedCirclePathsMatchThePaintedRouteInEveryFrame() {
    let frames = [
      Rect(origin: .zero, size: .init(width: 20, height: 10)),
      Rect(origin: .zero, size: .init(width: 6, height: 14)),
      Rect(origin: .zero, size: .init(width: 10, height: 10)),
      Rect(origin: Point(x: 3, y: 2), size: .init(width: 20, height: 10)),
    ]
    var differing: [String] = []
    for rect in frames {
      for (from, to) in [(0.0, 0.5), (0.125, 0.625), (0.3, 0.95)] {
        let painted = ShapeGeometry.trimmed(.circle, from: from, to: to)
          .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect)
        if Circle().trim(from: from, to: to).path(in: rect) != painted {
          differing.append("\(rect) \(from)...\(to)")
        }
      }
    }
    #expect(differing.isEmpty, "\(differing.count) of 12 differ: \(differing)")
  }

  @Test("wave3g02: nested and inset trimmed Circles trace the outline their fill paints")
  func wave3g02NestedAndInsetTrimmedCirclesMatchThePaintedRoute() {
    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    // The fill paints the composed fractions of the untrimmed outline
    // (Shape.swift:89-94): 0 + 0.5 * 0.25 and 0 + 0.5 * 1.
    let nested = Circle().trim(from: 0, to: 0.5).trim(from: 0.25, to: 1)
    #expect(nested.trimStart == 0.125 && nested.trimEnd == 0.5)
    #expect(
      nested.path(in: rect)
        == ShapeGeometry.trimmed(.circle, from: 0.125, to: 0.5)
        .path(in: rect, stretchingCircle: true, trimAspectRatio: w2fbAspect))
    // The fill paints in the inset frame (Rasterizer+PaintCommands.swift:20-24).
    let insetFrame = Rect(origin: Point(x: 2, y: 2), size: .init(width: 16, height: 6))
    #expect(
      Circle().inset(by: 2).trim(from: 0, to: 0.5).path(in: rect)
        == ShapeGeometry.trimmed(.circle, from: 0, to: 0.5)
        .path(in: insetFrame, stretchingCircle: true, trimAspectRatio: w2fbAspect))
  }

  @Test("wave3g03: whole trims and custom bases keep their own outline")
  func wave3g03WholeTrimsAndCustomBasesKeepTheirOwnOutline() throws {
    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    // A whole trim fills the untrimmed analytic Circle, so its path stays the
    // trim of the inscribed `Circle().path(in:)`.
    let inscribed = Circle().path(in: rect)
    let inscribedBox = try #require(inscribed.boundingRect)
    #expect(abs(inscribedBox.origin.x - 5) < 0.01 && abs(inscribedBox.size.width - 10) < 0.01)
    let whole = inscribed.physicallyTrimmedPath(from: 0, to: 1, aspectRatio: w2fbAspect)
    #expect(Circle().trim(from: 0, to: 1).path(in: rect) == whole)
    #expect(Circle().trim(from: -1, to: 2).path(in: rect) == whole)
    // A custom shape is its own path; a trim measures it as authored.
    let fixed = W3GFixedSquareShape()
    #expect(
      fixed.trim(from: 0, to: 0.5).path(in: rect)
        == fixed.path(in: rect).physicallyTrimmedPath(from: 0, to: 0.5, aspectRatio: w2fbAspect))
  }

  @Test("wave3g04: the physical trim of a far finite path keeps the outline in either direction")
  func wave3g04PhysicalTrimOfFarFinitePathsKeepsTheirOutline() throws {
    let rect = Rect(origin: .zero, size: .init(width: 10, height: 10))
    for far in [1e308, -1e308] {
      let trimmed = W3GFarPointShape(farY: far).trim(from: 0, to: 0.5).path(in: rect)
      let box = try #require(trimmed.boundingRect, "far y \(far)")
      #expect(box.origin.x == 0 && box.size.width == 10, "far y \(far): \(box)")
      // Half of the physical length 10 + 2 * 1e308 lies 5e307 - 2.5 cells along y.
      #expect(abs(box.size.height - 5e307) / 5e307 < 1e-12, "far y \(far): \(box)")
      #expect(far > 0 ? box.origin.y == 0 : box.origin.y < -1e307, "far y \(far): \(box)")
    }
  }

  @Test("wave3g05: the physical trim is unchanged wherever the scaled outline is finite")
  func wave3g05PhysicalTrimIsUnchangedWhereTheScaledOutlineIsFinite() {
    let rect = Rect(origin: .zero, size: .init(width: 20, height: 10))
    var curve = Path()
    curve.move(to: Point(x: 1, y: 9))
    curve.addCurve(
      to: Point(x: 19, y: 1), control1: Point(x: 4, y: -3), control2: Point(x: 12, y: 14))
    curve.addQuadCurve(to: Point(x: 2, y: 2), control: Point(x: 9, y: 30))
    let paths = [
      ShapeGeometry.circle.path(in: rect, stretchingCircle: true),
      ShapeGeometry.circle.path(in: rect),
      Path(roundedRect: rect, cornerRadius: 2),
      ShapeGeometry.capsule.path(in: rect),
      curve,
      W3GFarPointShape(farY: 4e307).path(in: rect),
    ]
    var differing: [String] = []
    for (index, path) in paths.enumerated() {
      for aspect in [0.5, 2, 2.5] {
        for (from, to) in [(0.0, 0.5), (0.1, 0.6), (0.3, 0.95)] {
          // The 6d877a7d expression.
          let reference = path.scaledBy(sx: 1, sy: aspect).trimmedPath(from: from, to: to)
            .scaledBy(sx: 1, sy: 1 / aspect)
          if path.physicallyTrimmedPath(from: from, to: to, aspectRatio: aspect) != reference {
            differing.append("path \(index) aspect \(aspect) \(from)...\(to)")
          }
        }
      }
    }
    #expect(differing.isEmpty, "\(differing)")
  }

  @Test("wave3g09: a vertical custom path stroke spanning the Double range draws its visible part")
  func wave3g09VerticalPathStrokeSpanningTheDoubleRange() throws {
    let near = W2FBPathShape(pathValue: w2fbLine(Point(x: 0.5, y: 0), Point(x: 0.5, y: 1)))
    let nearColumn = w2fbDotRows(near.stroke(Color.white), "wave3g09-near")
    try #require(nearColumn.joined().reduce(0, +) > 0, "\(nearColumn)")
    // Unit y -2e307...2e307 is +-1.4e308 subpixels: the difference overflows.
    let far = W2FBPathShape(pathValue: w2fbLine(Point(x: 0.5, y: -2e307), Point(x: 0.5, y: 2e307)))
    #expect(w2fbDotRows(far.stroke(Color.white), "wave3g09-far") == nearColumn)
  }

  @Test("wave3g12: numbered direct xterms take every generic xterm refinement")
  func wave3g12NumberedDirectXtermsTakeEveryGenericXtermRefinement() {
    let wezTerm = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct256", "TERM_PROGRAM": "WezTerm"], isTTY: true)
    #expect(wezTerm.colorLevel == .trueColor)
    #expect(wezTerm.supportsHyperlinks && wezTerm.supportsSynchronizedOutput)
    let ghostty = TerminalCapabilityProfile.detectPOSIXTerminal(
      environment: ["TERM": "xterm-direct16", "TERM_PROGRAM": "ghostty"], isTTY: true)
    #expect(ghostty.supportsHyperlinks && ghostty.supportsSynchronizedOutput)
    let windowsTerminal = TerminalCapabilityProfile.detectWindowsConsole(
      environment: ["TERM": "xterm-direct2", "WT_SESSION": "abc"], isTTY: true)
    #expect(windowsTerminal.colorLevel == .trueColor)
    #expect(windowsTerminal.supportsHyperlinks && windowsTerminal.supportsSynchronizedOutput)
  }

  @Test("wave3g13: other direct and malformed names keep their own capabilities")
  func wave3g13OtherDirectNamesStayUnrefined() {
    for term in ["xterm-directx", "xterm-direct-256", "st-direct", "screen-direct256"] {
      for marker in [["VTE_VERSION": "7600"], ["WT_SESSION": "abc"]] {
        let profile = TerminalCapabilityProfile.detectPOSIXTerminal(
          environment: marker.merging(["TERM": term]) { $1 }, isTTY: true)
        #expect(!profile.supportsHyperlinks, "\(term) \(marker)")
      }
    }
    func color(_ term: String) -> TerminalCapabilityProfile.ColorLevel {
      TerminalCapabilityProfile.detectPOSIXTerminal(environment: ["TERM": term], isTTY: true)
        .colorLevel
    }
    #expect(color("xterm-directx") == .ansi16)
    #expect(color("xterm-direct-256") == .ansi16)
    #expect(color("st-direct") == .trueColor)
    #expect(color("xterm-direct256") == .trueColor)
  }
}
