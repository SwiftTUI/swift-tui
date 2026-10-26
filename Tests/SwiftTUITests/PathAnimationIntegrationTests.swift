@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct PathAnimationIntegrationTests {
  @Test("STUI-355: compatible authored paths render start, midpoint and final animation samples")
  func renderedSamples() throws {
    let from = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let to = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    func node(_ path: Path) -> ResolvedNode {
      ResolvedNode(
        identity: Identity(components: ["morph"]), kind: .view("Path"),
        drawPayload: .shape(
          .init(geometry: .path(BoxedPath(path), .nonZero), operation: .fill(style: .color(.white)))
        ))
    }
    controller.processResolvedTree(node(from), transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(node(to), transaction: transaction, timestamp: time)
    var surfaces: [RasterSurface] = []
    for milliseconds in [0, 100, 200] {
      var sample = node(to)
      _ = controller.applyInterpolations(
        to: &sample, at: time.advanced(by: .milliseconds(milliseconds)))
      guard case .shape(let payload) = sample.drawPayload,
        case .path(let boxed, _) = payload.geometry
      else {
        Issue.record("missing path sample")
        return
      }
      let expected = Path(
        Rect(origin: .zero, size: .init(width: 0.2 + 0.8 * Double(milliseconds) / 200, height: 1)))
      let actualSurface = render(boxed.path)
      #expect(actualSurface == render(expected))
      surfaces.append(actualSurface)
    }
    #expect(surfaces[0] != surfaces[1])
    #expect(surfaces[1] != surfaces[2])
    #expect(from.interpolated(to: to, progress: 0) == from)
    #expect(from.interpolated(to: to, progress: 1) == to)
  }

  @Test("morph topology mismatch snaps, including equal point counts with different element kinds")
  func topologyAndDegenerates() throws {
    let move = Path([.move(to: .zero)])
    let line = Path([.line(to: .init(x: 1, y: 1))])
    #expect(!move.isInterpolable(to: line))
    for progress in [0, 0.5, 1, .nan] {
      #expect(move.interpolated(to: line, progress: progress) == line)
      let sample = try #require(
        AnyAnimatable(move).interpolated(to: AnyAnimatable(line), progress: progress))
      #expect(sample.unwrap(as: Path.self) == line)
    }
    #expect(Path().isInterpolable(to: Path()))
    #expect(Path().interpolated(to: Path(), progress: 0.5) == Path())
    let collapsed = Path([.move(to: .zero), .line(to: .zero), .close])
    #expect(collapsed.isInterpolable(to: collapsed))
    #expect(collapsed.interpolated(to: collapsed, progress: 0.5) == collapsed)
    let curves = Path([
      .move(to: .zero), .quadCurve(to: .init(x: 1, y: 1), control: .init(x: 0, y: 1)),
      .curve(to: .zero, control1: .init(x: 1, y: 0), control2: .init(x: 0, y: 1)), .close,
    ])
    let translated = curves.translatedBy(dx: 2, dy: 4)
    #expect(curves.interpolated(to: translated, progress: 0.5) == curves.translatedBy(dx: 1, dy: 2))
    var copy = curves
    copy.animatableData = .init([])
    #expect(copy == curves)
  }

  @Test("STUI-1129: custom paths morph inside fixed fill trims, keeping fractions and fill rule")
  func trimmedCustomPathsMorphUnderFixedTrims() throws {
    let from = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let to = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let wrappers: [(name: String, wrap: (ShapeGeometry) -> ShapeGeometry)] = [
      ("single", { .trimmed($0, from: 0, to: 0.75) }),
      ("nested", { .trimmed(.trimmed($0, from: 0.1, to: 0.9), from: 0, to: 0.5) }),
    ]
    for (name, wrap) in wrappers {
      let controller = AnimationController()
      let animation = Animation.linear(duration: .milliseconds(200))
      _ = controller.register(animation)
      let time = MonotonicInstant.now()
      func node(_ path: Path) -> ResolvedNode {
        Self.fillNode(wrap(.path(BoxedPath(path), .evenOdd)))
      }
      controller.processResolvedTree(node(from), transaction: .init(), timestamp: time)
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      controller.processResolvedTree(node(to), transaction: transaction, timestamp: time)
      var sample = node(to)
      _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
      guard case .shape(let payload) = sample.drawPayload else {
        Issue.record("\(name): missing shape payload")
        continue
      }
      let expectedTrims = Self.trims(of: wrap(.path(BoxedPath(to), .evenOdd)))
      #expect(Self.trims(of: payload.geometry) == expectedTrims, "\(name)")
      let inner = try #require(Self.innerPath(of: payload.geometry), "\(name)")
      #expect(inner.rule == .evenOdd, "\(name)")
      let width = try #require(inner.path.boundingRect?.size.width, "\(name)")
      #expect(abs(width - 0.6) < 1e-9, "\(name): sampled width \(width) at 100 of 200 ms")
    }
    // An analytic primitive has no path to morph, trimmed or not.
    let analytic = Self.fillNode(.trimmed(.rectangle, from: 0, to: 0.5))
    #expect(AnimatableSnapshot.extract(from: analytic)[.shapePath] == nil)
  }

  @Test("STUI-1129 carve-out: a fill's trim interval change still snaps")
  func fillTrimIntervalChangeStillSnaps() {
    let path = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    let start = Self.fillNode(.trimmed(.path(BoxedPath(path), .nonZero), from: 0, to: 0.25))
    let end = Self.fillNode(.trimmed(.path(BoxedPath(path), .nonZero), from: 0, to: 0.75))
    controller.processResolvedTree(start, transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(end, transaction: transaction, timestamp: time)
    #expect(controller.activeAnimationCount == 0)
    var sample = end
    _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
    #expect(sample.drawPayload == end.drawPayload)
  }

  /// STUI-1218: a `clipShape` mask morphs like a fill of the same shape
  /// (`Shapes.md`, animate compatible paths), bare or trimmed. Mid-animation,
  /// the mask paints exactly what a static clip at the interpolated fraction
  /// paints (0.25 -> 1 at 500 of 1000 ms is 0.625).
  @Test("STUI-1218: clip masks morph whether trimmed or not")
  func clipMasksMorphWhetherTrimmedOrNot() throws {
    let bare = try Self.midAnimationClipExtent(trimmed: false)
    let trimmed = try Self.midAnimationClipExtent(trimmed: true)
    let midway = Self.staticClipExtent(fraction: 0.625, trimmed: false)
    #expect(midway > 4 && midway < 19, "the midway mask is neither endpoint: \(midway)")
    #expect(bare == midway, "a bare clip mask morphs: \(bare) vs \(midway)")
    #expect(trimmed == Self.staticClipExtent(fraction: 0.625, trimmed: true))
  }

  @Test("STUI-1218: clip mask paths morph inside fixed trims, keeping fractions and fill rule")
  func clipMaskPathsMorphUnderFixedTrims() throws {
    let from = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let to = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let wrappers: [(name: String, wrap: (ShapeGeometry) -> ShapeGeometry)] = [
      ("bare", { $0 }),
      ("single", { .trimmed($0, from: 0, to: 0.75) }),
      ("nested", { .trimmed(.trimmed($0, from: 0.1, to: 0.9), from: 0, to: 0.5) }),
    ]
    for (name, wrap) in wrappers {
      let controller = AnimationController()
      let animation = Animation.linear(duration: .milliseconds(200))
      _ = controller.register(animation)
      let time = MonotonicInstant.now()
      func node(_ path: Path) -> ResolvedNode {
        Self.clipNode([.init(geometry: wrap(.path(BoxedPath(path), .evenOdd)), insetAmount: 1)])
      }
      controller.processResolvedTree(node(from), transaction: .init(), timestamp: time)
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      controller.processResolvedTree(node(to), transaction: transaction, timestamp: time)
      #expect(controller.activeAnimationCount == 1, "\(name)")
      #expect(!controller.hasLayoutAffectingPropertyAnimation, "\(name): a mask is drawing only")
      var sample = node(to)
      _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
      let clips = sample.drawMetadata.shapeClips
      try #require(clips.count == 1, "\(name)")
      #expect(clips[0].insetAmount == 1, "\(name)")
      #expect(
        Self.trims(of: clips[0].geometry) == Self.trims(of: wrap(.path(BoxedPath(to), .evenOdd))),
        "\(name)")
      let inner = try #require(Self.innerPath(of: clips[0].geometry), "\(name)")
      #expect(inner.rule == .evenOdd, "\(name)")
      let width = try #require(inner.path.boundingRect?.size.width, "\(name)")
      #expect(abs(width - 0.6) < 1e-9, "\(name): sampled width \(width) at 100 of 200 ms")
      var end = node(to)
      _ = controller.applyInterpolations(to: &end, at: time.advanced(by: .milliseconds(200)))
      #expect(end.drawMetadata.shapeClips == node(to).drawMetadata.shapeClips, "\(name)")
    }
  }

  @Test("STUI-1218: nested clips morph independently; analytic clips have no path to morph")
  func nestedClipMasksMorphIndependently() throws {
    let narrow = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let wide = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let tall = Path(Rect(origin: .zero, size: .init(width: 1, height: 0.2)))
    func node(_ first: Path, _ second: Path) -> ResolvedNode {
      Self.clipNode([
        .init(geometry: .path(BoxedPath(first), .nonZero), insetAmount: 0),
        .init(geometry: .rectangle, insetAmount: 0),
        .init(geometry: .path(BoxedPath(second), .nonZero), insetAmount: 0),
      ])
    }
    let controller = AnimationController()
    let animation = Animation.linear(duration: .milliseconds(200))
    _ = controller.register(animation)
    let time = MonotonicInstant.now()
    controller.processResolvedTree(node(narrow, wide), transaction: .init(), timestamp: time)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(node(wide, tall), transaction: transaction, timestamp: time)
    var sample = node(wide, tall)
    _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
    let clips = sample.drawMetadata.shapeClips
    try #require(clips.count == 3)
    #expect(clips[1].geometry == .rectangle)
    let first = try #require(Self.innerPath(of: clips[0].geometry)?.path.boundingRect)
    let third = try #require(Self.innerPath(of: clips[2].geometry)?.path.boundingRect)
    #expect(abs(first.size.width - 0.6) < 1e-9 && abs(first.size.height - 1) < 1e-9)
    #expect(abs(third.size.width - 1) < 1e-9 && abs(third.size.height - 0.6) < 1e-9)

    let analytic = Self.clipNode([
      .init(geometry: .trimmed(.rectangle, from: 0, to: 0.5), insetAmount: 0)
    ])
    #expect(AnimatableSnapshot.extract(from: analytic).values.isEmpty)
    #expect(AnimatableSnapshot.extract(from: Self.clipNode([])).values.isEmpty)
  }

  @Test("STUI-1218: mismatched clip topology, clip count and trim interval changes snap")
  func clipMaskStructuralChangesSnap() throws {
    let rect = Path(Rect(origin: .zero, size: .init(width: 0.2, height: 1)))
    let curved = Path([
      .move(to: .zero), .quadCurve(to: .init(x: 1, y: 1), control: .init(x: 0, y: 1)), .close,
    ])
    let clip = { (geometry: ShapeGeometry) in
      DrawMetadata.ShapeClip(geometry: geometry, insetAmount: 0)
    }
    let cases: [(name: String, from: [DrawMetadata.ShapeClip], to: [DrawMetadata.ShapeClip])] = [
      (
        "topology", [clip(.path(BoxedPath(rect), .nonZero))],
        [clip(.path(BoxedPath(curved), .nonZero))]
      ),
      (
        "count", [clip(.path(BoxedPath(rect), .nonZero))],
        [clip(.path(BoxedPath(rect), .nonZero)), clip(.path(BoxedPath(rect), .nonZero))]
      ),
      (
        "kind", [clip(.path(BoxedPath(rect), .nonZero)), clip(.rectangle)],
        [clip(.rectangle), clip(.path(BoxedPath(rect), .nonZero))]
      ),
      (
        "trim interval", [clip(.trimmed(.path(BoxedPath(rect), .nonZero), from: 0, to: 0.25))],
        [clip(.trimmed(.path(BoxedPath(rect), .nonZero), from: 0, to: 0.75))]
      ),
    ]
    for (name, from, to) in cases {
      let controller = AnimationController()
      let animation = Animation.linear(duration: .milliseconds(200))
      _ = controller.register(animation)
      let time = MonotonicInstant.now()
      controller.processResolvedTree(Self.clipNode(from), transaction: .init(), timestamp: time)
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      controller.processResolvedTree(Self.clipNode(to), transaction: transaction, timestamp: time)
      var sample = Self.clipNode(to)
      _ = controller.applyInterpolations(to: &sample, at: time.advanced(by: .milliseconds(100)))
      #expect(sample.drawMetadata.shapeClips == to, "\(name) snaps to the destination")
    }
  }

  /// STUI-1318: an empty mask records no drawn identity, so a mask animating
  /// toward area is an off-screen elision barrier while it runs. A mask whose
  /// destination encloses no area reveals nothing and keeps elision. The slot
  /// stays draw-only: it is never layout-affecting.
  @Test("STUI-1318: a clip mask animating toward area blocks off-screen elision")
  func clipMaskRevealBlocksOffscreenElision() throws {
    let zero = Path(Rect(origin: .zero, size: .init(width: 0, height: 1)))
    let flat = Path(Rect(origin: .zero, size: .init(width: 0, height: 0.4)))
    let wide = Path(Rect(origin: .zero, size: .init(width: 1, height: 1)))
    let cases: [(name: String, from: Path, to: Path, trim: Bool, reveals: Bool)] = [
      ("empty to area", zero, wide, false, true),
      ("trimmed empty to area", zero, wide, true, true),
      ("area to empty", wide, zero, false, false),
      ("empty to empty", zero, flat, false, false),
    ]
    for (name, from, to, trim, reveals) in cases {
      let controller = AnimationController()
      let animation = Animation.linear(duration: .milliseconds(200))
      _ = controller.register(animation)
      let time = MonotonicInstant.now()
      func node(_ path: Path) -> ResolvedNode {
        let geometry = ShapeGeometry.path(BoxedPath(path), .nonZero)
        return Self.clipNode([
          .init(geometry: trim ? .trimmed(geometry, from: 0, to: 0.75) : geometry, insetAmount: 0)
        ])
      }
      controller.processResolvedTree(node(from), transaction: .init(), timestamp: time)
      #expect(!controller.hasRevealingClipMaskAnimation, "\(name): nothing animates yet")
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      controller.processResolvedTree(node(to), transaction: transaction, timestamp: time)
      #expect(controller.activeAnimationCount == 1, "\(name)")
      #expect(controller.hasRevealingClipMaskAnimation == reveals, "\(name)")
      #expect(!controller.hasLayoutAffectingPropertyAnimation, "\(name): a mask is drawing only")
    }
  }

  private func render(_ path: Path) -> RasterSurface {
    DefaultRenderer().render(AuthoredPath(path: path).fill(Color.white).frame(width: 20, height: 8))
      .rasterSurface
  }

  private static func fillNode(_ geometry: ShapeGeometry) -> ResolvedNode {
    ResolvedNode(
      identity: Identity(components: ["morph"]), kind: .view("Path"),
      drawPayload: .shape(.init(geometry: geometry, operation: .fill(style: .color(.white)))))
  }

  private static func clipNode(_ clips: [DrawMetadata.ShapeClip]) -> ResolvedNode {
    var node = ResolvedNode(
      identity: Identity(components: ["clip"]), kind: .view("VStack"),
      children: [
        ResolvedNode(
          identity: Identity(components: ["clip", "text"]), kind: .view("Text"),
          drawPayload: .text("####"))
      ])
    var metadata = node.drawMetadata
    metadata.shapeClips = clips
    node.drawMetadata = metadata
    return node
  }

  /// The last painted column of the top row of the clip fixture at a fixed
  /// fraction, rendered without animation.
  private static func staticClipExtent(fraction: Double, trimmed: Bool) -> Int {
    let rows = VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in Text(String(repeating: "#", count: 20)) }
    }
    let surface =
      trimmed
      ? DefaultRenderer().render(
        rows.clipShape(ClipMorphShape(fraction: fraction).trim(from: 0, to: 0.75)),
        proposal: .init(width: 20, height: 4)
      ).rasterSurface
      : DefaultRenderer().render(
        rows.clipShape(ClipMorphShape(fraction: fraction)), proposal: .init(width: 20, height: 4)
      ).rasterSurface
    return maxPaintedX(in: surface.lines.joined(separator: "\n"))
  }

  private static func trims(of geometry: ShapeGeometry) -> [[Double]] {
    guard case .trimmed(let base, let from, let to) = geometry else { return [] }
    return [[from, to]] + trims(of: base)
  }

  private static func innerPath(of geometry: ShapeGeometry) -> (path: Path, rule: FillRule)? {
    switch geometry {
    case .path(let boxed, let rule): return (boxed.path, rule)
    case .trimmed(let base, _, _): return innerPath(of: base)
    default: return nil
    }
  }

  /// Mounts four 20-column rows of text clipped by a rectangle covering `fraction` of the
  /// width, animates the fraction 0.25 -> 1 over one second on an injected
  /// clock and returns the last painted column of the top row at 500 ms
  /// (4 at the start, 19 at the end).
  private static func midAnimationClipExtent(trimmed: Bool) throws -> Int {
    let log = ClipMorphLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("clip-morph", trimmed ? "trimmed" : "bare"),
      size: .init(width: 20, height: 4)
    ) { ClipMorphRoot(trimmed: trimmed, log: log) }
    defer { h.shutdown() }
    try #require(maxPaintedX(in: h.frame) == 4, "\(h.frame)")
    let controller = h.runLoop.renderer.internalAnimationController
    let clock = ClipMorphClock()
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
      return maxPaintedX(in: h.frame)
    }
  }

  private static func maxPaintedX(in frame: String) -> Int {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard let top = rows.first else { return -1 }
    var last = -1
    for (index, character) in top.enumerated() where character != " " {
      last = index
    }
    return last
  }
}

@MainActor
private final class ClipMorphLog {
  var fraction: Binding<Double>?
}

@MainActor
private final class ClipMorphClock { var now = MonotonicInstant.now() }

/// A rectangle covering `fraction` of the unit width: four lines and a close,
/// so every fraction has the same element topology and can interpolate.
private struct ClipMorphShape: Shape {
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

private struct ClipMorphRoot: View {
  @State private var fraction = 0.25
  let trimmed: Bool
  let log: ClipMorphLog

  var body: some View {
    let _ = capture()
    if trimmed {
      rows.clipShape(ClipMorphShape(fraction: fraction).trim(from: 0, to: 0.75))
    } else {
      rows.clipShape(ClipMorphShape(fraction: fraction))
    }
  }

  private var rows: some View {
    VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in Text(String(repeating: "#", count: 20)) }
    }
  }

  private func capture() {
    log.fraction = $fraction
  }
}

private struct AuthoredPath: Shape {
  var path: Path
  func path(in rect: Rect) -> Path {
    path.scaledBy(sx: rect.size.width, sy: rect.size.height).translatedBy(
      dx: rect.origin.x, dy: rect.origin.y)
  }
}
