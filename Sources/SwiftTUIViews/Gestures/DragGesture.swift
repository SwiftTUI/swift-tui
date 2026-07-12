public import SwiftTUICore

/// A gesture that recognizes pointer drag, producing translation and velocity.
///
/// `Value` matches SwiftUI's `DragGesture.Value` shape in continuous terminal
/// cell coordinates and additionally carries pointer provenance plus the
/// sampled path for the current drag.
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
    /// `location - startLocation`, in cells.
    public var translation: Vector
    /// Instantaneous velocity in cells/second, computed from a
    /// trailing ~100ms sample window.
    public var velocity: Vector
    /// `startLocation + predictedEndTranslation`.
    public var predictedEndLocation: Point
    /// `translation + velocity/4` — projects ~250ms of current velocity
    /// forward.
    public var predictedEndTranslation: Vector
    /// Original pointer location and precision for the current sample.
    public var pointer: PointerLocation
    /// Ordered pointer samples captured since the drag began.
    public var path: PointerPath

    public init(
      time: MonotonicInstant,
      location: Point,
      startLocation: Point,
      translation: Vector,
      velocity: Vector,
      predictedEndLocation: Point,
      predictedEndTranslation: Vector,
      pointer: PointerLocation,
      path: PointerPath
    ) {
      self.time = time
      self.location = location
      self.startLocation = startLocation
      self.translation = translation
      self.velocity = velocity
      self.predictedEndLocation = predictedEndLocation
      self.predictedEndTranslation = predictedEndTranslation
      self.pointer = pointer
      self.path = path
    }
  }

  public let minimumDistance: Double
  public let coordinateSpace: CoordinateSpace

  public init(
    minimumDistance: Double = 0,
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
    let pointer: PointerLocation
  }

  private(set) var minimumDistance: Double
  private(set) var coordinateSpace: CoordinateSpace
  private(set) var phase: GestureRecognizerPhase = .possible
  private var startLocation: Point?
  private var startTime: MonotonicInstant?
  private var targetRect: CellRect = CellRect(origin: .zero, size: .zero)
  private var namedCoordinateSpaces: [String: CellRect] = [:]
  private var samples: [Sample] = []
  private var lastValue: DragGesture.Value?

  init(minimumDistance: Double, coordinateSpace: CoordinateSpace) {
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
    let location = event.location.location
    switch event.kind {
    case .down(.primary):
      startLocation = location
      startTime = event.timestamp
      targetRect = event.targetRect
      namedCoordinateSpaces = event.namedCoordinateSpaces
      samples = [
        Sample(
          location: location,
          time: event.timestamp,
          pointer: event.location
        )
      ]
      if minimumDistance <= 0 {
        phase = .began
        lastValue = makeValue(
          now: event.timestamp,
          location: location,
          start: location,
          startTime: event.timestamp,
          pointer: event.location
        )
      }
      return .handled
    case .dragged(.primary):
      guard let start = startLocation, let t0 = startTime else { return .ignored }
      samples.append(
        Sample(
          location: location,
          time: event.timestamp,
          pointer: event.location
        )
      )
      namedCoordinateSpaces = event.namedCoordinateSpaces
      let dx = location.x - start.x
      let dy = location.y - start.y
      let distance = max(abs(dx), abs(dy))
      guard distance >= minimumDistance else { return .handled }
      if phase == .possible { phase = .began } else { phase = .changed }
      lastValue = makeValue(
        now: event.timestamp,
        location: location,
        start: start,
        startTime: t0,
        pointer: event.location
      )
      return .handled
    case .up(.primary):
      guard let start = startLocation, let t0 = startTime else { return .ignored }
      samples.append(
        Sample(
          location: location,
          time: event.timestamp,
          pointer: event.location
        )
      )
      namedCoordinateSpaces = event.namedCoordinateSpaces
      phase = .ended
      lastValue = makeValue(
        now: event.timestamp,
        location: location,
        start: start,
        startTime: t0,
        pointer: event.location
      )
      return .handled
    default:
      return .ignored
    }
  }

  func handleDeadline(at instant: MonotonicInstant) -> Bool { false }

  /// Adopts re-authored value parameters alongside the interaction state the
  /// registry preserves: a mid-drag re-resolve that authors a new threshold
  /// or coordinate space must apply to the drag in flight.
  func adoptAuthoredCallbacks(from replacement: AnyObject) -> Bool {
    guard let other = replacement as? DragGestureRecognizer else {
      return false
    }
    minimumDistance = other.minimumDistance
    coordinateSpace = other.coordinateSpace
    return true
  }

  func currentValue() -> DragGesture.Value? {
    guard let value = lastValue else { return nil }
    let loc = coordinateSpace.resolve(
      terminalPoint: value.location,
      targetRect: targetRect,
      namedCoordinateSpaces: namedCoordinateSpaces
    )
    let start = coordinateSpace.resolve(
      terminalPoint: value.startLocation,
      targetRect: targetRect,
      namedCoordinateSpaces: namedCoordinateSpaces
    )
    let predEnd = coordinateSpace.resolve(
      terminalPoint: value.predictedEndLocation,
      targetRect: targetRect,
      namedCoordinateSpaces: namedCoordinateSpaces
    )
    let path = PointerPath(
      value.path.map { sample in
        PointerPath.Sample(
          location: coordinateSpace.resolve(
            terminalPoint: sample.location,
            targetRect: targetRect,
            namedCoordinateSpaces: namedCoordinateSpaces
          ),
          time: sample.time,
          pointer: sample.pointer
        )
      }
    )
    return DragGesture.Value(
      time: value.time,
      location: loc,
      startLocation: start,
      translation: value.translation,
      velocity: value.velocity,
      predictedEndLocation: predEnd,
      predictedEndTranslation: value.predictedEndTranslation,
      pointer: value.pointer,
      path: path
    )
  }

  func tearDown() {
    if !phase.isTerminal { phase = .cancelled }
    samples.removeAll()
    namedCoordinateSpaces.removeAll(keepingCapacity: true)
  }

  private func makeValue(
    now: MonotonicInstant,
    location: Point,
    start: Point,
    startTime: MonotonicInstant,
    pointer: PointerLocation
  ) -> DragGesture.Value {
    let translation = Vector(
      dx: location.x - start.x,
      dy: location.y - start.y
    )
    let velocity = computeVelocity(now: now)
    // Predicted end = current + ~250ms of current velocity.
    let predictedEndTranslation = Vector(
      dx: translation.dx + velocity.dx / 4,
      dy: translation.dy + velocity.dy / 4
    )
    let predictedEndLocation = Point(
      x: start.x + predictedEndTranslation.dx,
      y: start.y + predictedEndTranslation.dy
    )
    let path = PointerPath(
      samples.map { sample in
        PointerPath.Sample(
          location: sample.location,
          time: sample.time,
          pointer: sample.pointer
        )
      }
    )
    return DragGesture.Value(
      time: now,
      location: location,
      startLocation: start,
      translation: translation,
      velocity: velocity,
      predictedEndLocation: predictedEndLocation,
      predictedEndTranslation: predictedEndTranslation,
      pointer: pointer,
      path: path
    )
  }

  /// Computes instantaneous velocity (cells/second) from the last two
  /// samples in the buffer, or a small trailing window when available.
  ///
  /// Uses `MonotonicInstant.duration(to:)` which returns a `Swift.Duration`,
  /// then converts via `components.seconds` + `components.attoseconds / 1e18`.
  private func computeVelocity(now: MonotonicInstant) -> Vector {
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
    return Vector(
      dx: (last.location.x - reference.location.x) / dt,
      dy: (last.location.y - reference.location.y) / dt
    )
  }

  /// Seconds between two MonotonicInstant values, using `duration(to:)`.
  private func seconds(from earlier: MonotonicInstant, to later: MonotonicInstant) -> Double {
    let d = earlier.duration(to: later)
    let c = d.components
    return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000.0
  }
}
