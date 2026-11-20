import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Shapes that conform to `Animatable` (STUI-1546): a fill, a stroke and a
/// clip evaluate `path(in:)` with interpolated `animatableData` on every
/// animation tick, without resolving the view again. A shape that does not
/// conform keeps morphing its path point by point.
///
/// The tests drive the real run loop on an injected frame clock and read
/// the values `path(in:)` was called with. The file uses only API that
/// existed before the change, so it compiles against the earlier engine,
/// where every shape morphed.
@MainActor
@Suite("Animatable shape animation", .serialized)
struct AnimatableShapeAnimationTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  private static let spring = Animation.spring(duration: .milliseconds(600), bounce: 0.5)
  private static let letters = String(repeating: "#", count: 20)
  /// The frame of the change, the quarters of the 800 ms transaction, and a
  /// frame after its end.
  private static let bodyInstants = [0, 200, 400, 600, 800, 900]

  // MARK: - Recorded values

  @Test("path(in:) runs with every sample of a linear animation", arguments: ShapeUse.allCases)
  func shapeReceivesEveryLinearSample(_ use: ShapeUse) throws {
    let probe = try AnimatableValueProbe(named: "shape-linear-\(use)") { fraction, log in
      Self.content(use, EasedWedge(fraction: fraction, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      #expect(frames.count == 26, "\(frames.map(\.milliseconds))")
      // The frame of the write evaluates the path twice: once for the
      // geometry the view now has, and once for the sample it shows, the
      // origin. Every later frame evaluates it once, for its sample.
      #expect(frames.first?.values == [1, 0], "\(use): \(frames.first?.values ?? [])")
      if animatableProbeEvaluatesSelectively {
        #expect(frames.dropFirst().allSatisfy { $0.values.count == 1 }, "\(use)")
      }
      for frame in frames {
        let expected = min(1, Double(frame.milliseconds) / 800)
        let value = try #require(frame.values.last)
        #expect(abs(value - expected) < 1e-9, "\(use) at \(frame.milliseconds) ms: \(value)")
      }
      #expect(frames.last?.values.last == 1, "\(use)")
      // No view was resolved for a tick: the body that holds the shape ran
      // for the mount and for the write.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.evaluations["root"] == 2, "\(use)")
      }
      // The samples are drawn. The wedge covers the square of its fraction
      // of the width, which no morph of two rectangles produces: half way
      // through, a quarter of the columns is painted.
      let extents = frames.map { Self.paintedColumns(in: $0, use) }
      #expect(extents == extents.sorted(), "\(use): \(extents)")
      #expect(extents.last == 20, "\(use): \(extents)")
      #expect(abs(extents[12] - 5) <= 1, "\(use): \(extents)")
      #expect(probe.log.completions == 1, "\(use)")
      #expect(probe.controller.debugStateSnapshot().activeAnimationKeys.isEmpty, "\(use)")
    }
  }

  @Test("a spring evaluates path(in:) beyond the target", arguments: ShapeUse.allCases)
  func springOvershoots(_ use: ShapeUse) throws {
    let probe = try AnimatableValueProbe(named: "shape-spring-\(use)") { fraction, log in
      Self.content(use, EasedWedge(fraction: fraction, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.spring)
      let values = frames.compactMap(\.values.last)
      let peak = try #require(values.max())
      #expect(peak > 1.02, "\(use): \(values)")
      #expect(values.first == 0 && values.last == 1, "\(use): \(values)")
      #expect(probe.log.completions == 1, "\(use)")
    }
  }

  @Test("a trim and an inset of an Animatable shape animate as the shape does")
  func wrappedShapesAnimate() throws {
    for wrapper in ["trim", "inset"] {
      let probe = try AnimatableValueProbe(named: "shape-wrapped-\(wrapper)") { fraction, log in
        if wrapper == "trim" {
          EasedWedge(fraction: fraction, log: log).trim(from: 0, to: 0.75)
            .stroke(Color.white).frame(width: 20, height: 3)
        } else {
          EasedWedge(fraction: fraction, log: log).inset(by: 0)
            .fill(Color.white).frame(width: 20, height: 2)
        }
      }
      defer { probe.shutdown() }
      try probe.run { _ in
        let frames = try probe.animate(to: 1, Self.linear)
        let values = frames.compactMap(\.values.last)
        // The wrapper hides the shape's type from the modifier. The shape
        // still gets each sample.
        #expect(frames.count == 26, "\(wrapper)")
        #expect(values.first == 0 && values.last == 1, "\(wrapper): \(values)")
        #expect(values == values.sorted() && Set(values).count == 26, "\(wrapper): \(values)")
      }
    }
  }

  @Test("what the data does not cover changes when the animation starts")
  func otherFieldsTakeTheNewValueAtOnce() throws {
    let probe = try AnimatableValueProbe(named: "shape-other-fields") { fraction, log in
      // The side the wedge grows from is not animatable data.
      EasedWedge(fraction: 0.5 + fraction / 2, fromTrailing: fraction > 0, log: log)
        .fill(Color.white).frame(width: 20, height: 2)
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(probe.frame.split(separator: "\n").first?.first != " ", "\(probe.frame)")
      let frames = try probe.animate(to: 1, Self.linear)
      // Every sample is evaluated by the shape the view now holds: the wedge
      // is at the trailing edge from the first frame, and its width animates.
      #expect(frames.allSatisfy { $0.secondary.allSatisfy { $0 == 1 } })
      for frame in frames {
        let row = frame.frame.split(separator: "\n", omittingEmptySubsequences: false)[0]
        let cells = Array(row.prefix(20))
        let painted = cells.indices.filter { cells[$0] != " " }
        #expect(painted.last == 19, "\(frame.milliseconds) ms: \(row)")
        #expect(painted.count == 20 - (painted.first ?? 20), "\(frame.milliseconds) ms: \(row)")
      }
      let extents = frames.map { Self.paintedColumns(in: $0, .fill) }
      #expect(extents.first == 5 && extents.last == 20, "\(extents)")
    }
  }

  // MARK: - A shape that does not conform

  @Test("a shape that does not conform still morphs its path")
  func nonConformingShapeMorphs() throws {
    let probe = try AnimatableValueProbe(named: "shape-plain") { fraction, log in
      Text(Self.letters).clipShape(PlainWedge(fraction: fraction, log: log))
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      let frames = try probe.animate(to: 1, Self.linear)
      // The path is evaluated when the view resolves, and not for a tick.
      if animatableProbeEvaluatesSelectively {
        #expect(probe.log.values == [0, 1])
      }
      #expect(Set(probe.log.values) == [0, 1])
      // The two paths morph: one property animation, and a clip that is
      // half way across half way through.
      #expect(frames.first?.propertyAnimations == 1)
      #expect(frames.last?.propertyAnimations == 0)
      let extents = frames.map { Self.paintedColumns(in: $0, .clipShape) }
      #expect(extents == extents.sorted(), "\(extents)")
      #expect(abs(extents[12] - 10) <= 1, "\(extents)")
      #expect(extents.first == 0 && extents.last == 20, "\(extents)")
    }
  }

  // MARK: - Inside a transition body

  @Test("an Animatable clip shape in a transition body is evaluated through the insertion")
  func transitionBodyClipShapeAnimatesOnInsertion() throws {
    let probe = try AnimatableValueProbe(named: "shape-body-insertion") { shown, log in
      if shown > 0.5 {
        Text(Self.letters).transition(WedgeReveal(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      var frames = [try probe.set(1, animation: Self.linear)]
      for offset in Self.bodyInstants.dropFirst() {
        frames.append(try probe.advance(toMilliseconds: offset))
      }
      // The body's clip shape is a value the engine animates between the
      // `willAppear` body and the `identity` body. The shape draws each
      // sample: the path was evaluated with data between the two phases,
      // and the clip covers the square of the fraction, which a morph of the
      // two phases' paths does not.
      let samples = frames.flatMap(\.values)
      #expect(samples.contains { $0 > 0.05 && $0 < 0.95 }, "\(samples)")
      let extents = frames.map { Self.paintedColumns(in: $0, .clipShape) }
      for (extent, expected) in zip(extents, [0, 1, 5, 11, 20, 20]) {
        #expect(abs(extent - expected) <= 1, "\(extents)")
      }
      #expect(extents.first == 0 && extents.last == 20, "\(extents)")
      #expect(probe.log.completions == 1)
    }
  }

  @Test("an Animatable clip shape in a transition body is evaluated through the removal")
  func transitionBodyClipShapeAnimatesOnRemoval() throws {
    let probe = try AnimatableValueProbe(
      named: "shape-body-removal", initial: 1, showsSibling: false
    ) { shown, log in
      if shown > 0.5 {
        Text(Self.letters).transition(WedgeReveal(log: log))
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      #expect(Self.paintedColumns(in: probe.frame, .clipShape) == 20)
      var frames = [try probe.set(0, animation: Self.linear)]
      for offset in Self.bodyInstants.dropFirst() {
        frames.append(try probe.advance(toMilliseconds: offset))
      }
      // The departing view is drawn through the `didDisappear` body, and its
      // clip shape goes from the data on screen to that body's data.
      let samples = frames.flatMap(\.values)
      #expect(samples.contains { $0 > 0.05 && $0 < 0.95 }, "\(samples)")
      let extents = frames.map { Self.paintedColumns(in: $0, .clipShape) }
      for (extent, expected) in zip(extents, [20, 11, 5, 1, 0, 0]) {
        #expect(abs(extent - expected) <= 1, "\(extents)")
      }
      #expect(extents.first == 20 && extents.last == 0, "\(extents)")
      #expect(probe.log.completions == 1)
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private static func content(_ use: ShapeUse, _ shape: EasedWedge) -> some View {
    switch use {
    case .fill:
      shape.fill(Color.white).frame(width: 20, height: 2)
    case .stroke:
      shape.stroke(Color.white).frame(width: 20, height: 3)
    case .clipShape:
      Text(letters).clipShape(shape)
    }
  }

  /// The number of columns of the first row that the shape reaches: the
  /// painted cells of a fill, the letters a clip lets through, and the
  /// trailing edge of a stroke.
  private static func paintedColumns(in frame: AnimatableValueFrame, _ use: ShapeUse) -> Int {
    paintedColumns(in: frame.frame, use)
  }

  private static func paintedColumns(in frame: String, _ use: ShapeUse) -> Int {
    let rows = frame.split(separator: "\n", omittingEmptySubsequences: false)
    guard let row = rows.first else { return 0 }
    let cells = Array(row.prefix(20))
    switch use {
    case .fill:
      return cells.filter { $0 != " " }.count
    case .clipShape:
      // The clipped text is a row of `#`.
      return cells.filter { $0 == "#" }.count
    case .stroke:
      return (cells.lastIndex { $0 != " " } ?? -1) + 1
    }
  }
}

// MARK: - Fixtures

enum ShapeUse: String, CaseIterable, Sendable, CustomStringConvertible {
  case fill, stroke, clipShape

  var description: String { rawValue }
}

/// A rectangle that covers the square of `fraction` of its width, from the
/// leading edge or from the trailing one. The square makes a sample differ
/// from a morph of the two end paths. The shape is `@MainActor`, as every
/// view is, and `Animatable`, which is nonisolated.
private struct EasedWedge: InsettableShape, Animatable {
  var fraction: Double
  var fromTrailing = false
  let log: AnimatableValueLog

  nonisolated var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: Rect) -> Path {
    log.values.append(fraction)
    log.secondary.append(fromTrailing ? 1 : 0)
    let width = rect.size.width * fraction * fraction
    let left = fromTrailing ? rect.origin.x + rect.size.width - width : rect.origin.x
    return wedgePath(left: left, right: left + width, in: rect)
  }
}

/// A rectangle that covers `fraction` of its width and does not conform to
/// `Animatable`.
private struct PlainWedge: Shape {
  var fraction: Double
  let log: AnimatableValueLog

  func path(in rect: Rect) -> Path {
    log.values.append(fraction)
    return wedgePath(
      left: rect.origin.x, right: rect.origin.x + rect.size.width * fraction, in: rect)
  }
}

/// Four lines and a close, so every wedge has the same elements.
private func wedgePath(left: Double, right: Double, in rect: Rect) -> Path {
  var path = Path()
  let bottom = rect.origin.y + rect.size.height
  path.move(to: Point(x: left, y: rect.origin.y))
  path.addLine(to: Point(x: right, y: rect.origin.y))
  path.addLine(to: Point(x: right, y: bottom))
  path.addLine(to: Point(x: left, y: bottom))
  path.closeSubpath()
  return path
}

/// A transition whose body clips its content with an `Animatable` shape.
private struct WedgeReveal: Transition {
  let log: AnimatableValueLog

  func body(content: Content, phase: TransitionPhase) -> some View {
    content.clipShape(EasedWedge(fraction: phase.isIdentity ? 1 : 0, log: log))
  }
}
