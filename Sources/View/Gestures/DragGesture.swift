public import Core

/// A gesture that recognizes pointer drag, producing translation and velocity.
///
/// `Value` matches SwiftUI's `DragGesture.Value` shape (reinterpreted for
/// integer cell coordinates): `time`, `location`, `startLocation`,
/// `translation`, `velocity`, `predictedEndLocation`,
/// `predictedEndTranslation`.
///
/// ## Terminal-faithful defaults
///
/// - `minimumDistance` is in cells (default `0`). SwiftUI's default is
///   10 points in continuous coordinate space.
/// - `velocity` is in cells/second, computed from a trailing ~100ms
///   sample window.
/// - `predictedEndLocation` projects 250ms of current velocity forward,
///   matching SwiftUI's inertial-scroll heuristic.
public struct DragGesture: Gesture {
  public typealias Body = Never

  public struct Value: Equatable, Sendable {
    /// The absolute monotonic time this sample was produced.
    public var time: MonotonicInstant
    /// The current location in the resolved `coordinateSpace`.
    public var location: Point
    /// The location when the drag began.
    public var startLocation: Point
    /// `location - startLocation`.
    public var translation: Size
    /// Instantaneous velocity in cells/second, computed from a
    /// trailing ~100ms sample window. Integer arithmetic — velocities
    /// below 1 cell/sec truncate to zero.
    public var velocity: Size
    /// `startLocation + predictedEndTranslation`. Integer truncation
    /// means velocities below 4 cells/sec produce zero contribution.
    public var predictedEndLocation: Point
    /// `translation + velocity/4` — projects ~250ms of current velocity
    /// forward. Integer truncation as above.
    public var predictedEndTranslation: Size

    public init(
      time: MonotonicInstant,
      location: Point,
      startLocation: Point,
      translation: Size,
      velocity: Size,
      predictedEndLocation: Point,
      predictedEndTranslation: Size
    ) {
      self.time = time
      self.location = location
      self.startLocation = startLocation
      self.translation = translation
      self.velocity = velocity
      self.predictedEndLocation = predictedEndLocation
      self.predictedEndTranslation = predictedEndTranslation
    }
  }

  public let minimumDistance: Int
  public let coordinateSpace: CoordinateSpace

  public init(
    minimumDistance: Int = 0,
    coordinateSpace: CoordinateSpace = .local
  ) {
    self.minimumDistance = minimumDistance
    self.coordinateSpace = coordinateSpace
  }

  public static var _needsPointerCapture: Bool { true }

  public var body: Never { neverBody() }

  public func _makeRecognizer(
    context: GestureRecognizerBuildContext
  ) -> AnyGestureRecognizer {
    AnyGestureRecognizer(
      DragGestureRecognizer(
        minimumDistance: minimumDistance,
        coordinateSpace: coordinateSpace
      )
    )
  }
}

@MainActor
final class DragGestureRecognizer: GestureRecognizer {
  typealias Value = DragGesture.Value

  struct Sample {
    let location: Point
    let time: MonotonicInstant
  }

  let minimumDistance: Int
  let coordinateSpace: CoordinateSpace
  private(set) var phase: GestureRecognizerPhase = .possible
  private var startLocation: Point?
  private var startTime: MonotonicInstant?
  private var targetRect: Rect = Rect(origin: .zero, size: .zero)
  private var samples: [Sample] = []
  private var lastValue: DragGesture.Value?

  init(minimumDistance: Int, coordinateSpace: CoordinateSpace) {
    self.minimumDistance = minimumDistance
    self.coordinateSpace = coordinateSpace
  }

  /// `startLocation` is set on `.down` but `phase` stays `.possible`
  /// until `minimumDistance` is crossed — override `isActive` so the
  /// registry sees the recognizer as in-flight from `.down` onward,
  /// protecting its state from being torn down by a re-resolve that
  /// lands between `.down` and the first `.dragged`.
  var isActive: Bool {
    startLocation != nil && !phase.isTerminal
  }

  func handle(event: LocalPointerEvent) -> GestureRecognizerEventDisposition {
    guard !phase.isTerminal else { return .ignored }
    switch event.kind {
    case .down(.primary):
      startLocation = event.location
      startTime = event.timestamp
      targetRect = event.targetRect
      samples = [Sample(location: event.location, time: event.timestamp)]
      return .handled
    case .dragged(.primary):
      guard let start = startLocation, let t0 = startTime else { return .ignored }
      samples.append(Sample(location: event.location, time: event.timestamp))
      let dx = event.location.x - start.x
      let dy = event.location.y - start.y
      let distance = max(abs(dx), abs(dy))
      guard distance >= minimumDistance else { return .handled }
      if phase == .possible { phase = .began } else { phase = .changed }
      lastValue = makeValue(
        now: event.timestamp,
        location: event.location,
        start: start,
        startTime: t0
      )
      return .handled
    case .up(.primary):
      guard let start = startLocation, let t0 = startTime else { return .ignored }
      samples.append(Sample(location: event.location, time: event.timestamp))
      phase = .ended
      lastValue = makeValue(
        now: event.timestamp,
        location: event.location,
        start: start,
        startTime: t0
      )
      return .handled
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }

  func currentValue() -> DragGesture.Value? {
    guard let value = lastValue else { return nil }
    let loc = coordinateSpace.resolve(
      terminalPoint: value.location,
      targetRect: targetRect
    )
    let start = coordinateSpace.resolve(
      terminalPoint: value.startLocation,
      targetRect: targetRect
    )
    let predEnd = coordinateSpace.resolve(
      terminalPoint: value.predictedEndLocation,
      targetRect: targetRect
    )
    return DragGesture.Value(
      time: value.time,
      location: loc,
      startLocation: start,
      translation: value.translation,
      velocity: value.velocity,
      predictedEndLocation: predEnd,
      predictedEndTranslation: value.predictedEndTranslation
    )
  }

  func tearDown() {
    if !phase.isTerminal { phase = .cancelled }
    samples.removeAll()
  }

  private func makeValue(
    now: MonotonicInstant,
    location: Point,
    start: Point,
    startTime: MonotonicInstant
  ) -> DragGesture.Value {
    let translation = Size(
      width: location.x - start.x,
      height: location.y - start.y
    )
    let velocity = computeVelocity(now: now)
    // Predicted end = current + ~250ms of current velocity.
    let predictedEndTranslation = Size(
      width: translation.width + velocity.width / 4,
      height: translation.height + velocity.height / 4
    )
    let predictedEndLocation = Point(
      x: start.x + predictedEndTranslation.width,
      y: start.y + predictedEndTranslation.height
    )
    return DragGesture.Value(
      time: now,
      location: location,
      startLocation: start,
      translation: translation,
      velocity: velocity,
      predictedEndLocation: predictedEndLocation,
      predictedEndTranslation: predictedEndTranslation
    )
  }

  /// Computes instantaneous velocity (cells/second) from the last two
  /// samples in the buffer, or a small trailing window when available.
  ///
  /// Uses `MonotonicInstant.duration(to:)` which returns a `Swift.Duration`,
  /// then converts via `components.seconds` + `components.attoseconds / 1e18`.
  private func computeVelocity(now: MonotonicInstant) -> Size {
    guard samples.count >= 2 else { return .zero }
    let last = samples[samples.count - 1]

    // Look back ~100ms or to the earliest sample, whichever is later.
    var reference = samples[0]
    for i in stride(from: samples.count - 1, through: 0, by: -1) {
      let age = seconds(from: samples[i].time, to: now)
      if age >= 0.1 {
        reference = samples[i]
        break
      }
      reference = samples[i]
    }

    let dt = seconds(from: reference.time, to: last.time)
    guard dt > 0 else { return .zero }
    return Size(
      width: Int(Double(last.location.x - reference.location.x) / dt),
      height: Int(Double(last.location.y - reference.location.y) / dt)
    )
  }

  /// Seconds between two MonotonicInstant values, using `duration(to:)`.
  private func seconds(from earlier: MonotonicInstant, to later: MonotonicInstant) -> Double {
    let d = earlier.duration(to: later)
    let c = d.components
    return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000.0
  }
}
