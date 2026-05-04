import SwiftTUI

struct PhysicsTab: View {
  @State private var toyState = FullScreenToyPhysics.State()
  @State private var didSeedInitialPosition = false
  @GestureState private var dragOffset = Vector.zero
  @GestureState private var gestureIsActive = false

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let metrics = proxy.cellPixelMetrics
      let fieldBounds = FullScreenToyPhysics.fieldBounds(from: bounds)
      let current = FullScreenToyPhysics.displayPosition(
        for: toyState,
        dragOffset: dragOffset,
        in: fieldBounds,
        metrics: metrics
      )
      let currentCell = current.snapped(.toNearestOrAwayFromZero)
      let height = max(
        1,
        Int((Double(FullScreenToyPhysics.diameter) / metrics.aspectRatio).rounded())
      )

      ZStack(alignment: .topLeading) {
        Circle()
          .frame(width: FullScreenToyPhysics.diameter, height: height)
          .offset(x: currentCell.x, y: currentCell.y)
          .foregroundStyle(.cyan)
          .gesture(dragGesture(in: fieldBounds, metrics: metrics))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.black)
      .task(id: FullScreenToyPhysics.BoundsID(size: fieldBounds)) { @MainActor in
        await runToyLoop(in: fieldBounds, metrics: metrics)
      }
    }
    .border(.tint, set: .rounded)
  }

  private func dragGesture(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> some Gesture {
    DragGesture()
      .updating($gestureIsActive) { _, state, _ in
        state = true
      }
      .updating($dragOffset) { value, state, _ in
        state = value.translation
      }
      .onEnded { value in
        FullScreenToyPhysics.applyRelease(
          to: &toyState,
          translation: value.translation,
          velocity: value.velocity,
          in: bounds,
          metrics: metrics
        )
      }
  }

  @MainActor
  private func runToyLoop(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) async {
    if !didSeedInitialPosition {
      toyState = FullScreenToyPhysics.spawnState(in: bounds, metrics: metrics)
      didSeedInitialPosition = true
    } else {
      toyState = FullScreenToyPhysics.clamped(toyState, in: bounds, metrics: metrics)
    }

    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: FullScreenToyPhysics.tickNanoseconds)
      guard !gestureIsActive else {
        continue
      }

      var next = toyState
      FullScreenToyPhysics.step(&next, in: bounds, metrics: metrics)
      guard next != toyState else {
        continue
      }
      toyState = next
    }
  }
}

struct FullScreenToyPhysics {
  /// Cell-width of the circular subject. The height of the cell frame is
  /// derived at the view layer from `cellPixelMetrics.aspectRatio` so the
  /// cell-space frame is visually square; the `Circle` rasterizer then
  /// applies its own sub-pixel aspect correction to emit a pixel-true
  /// circle on any terminal.
  static let diameter = 6
  static let fixedScale = 16
  static let tickMilliseconds = 40
  static let tickNanoseconds: UInt64 = 40_000_000
  static let gravityPerTick = 1
  static let floorFrictionNumerator = 15
  static let floorFrictionDenominator = 16
  static let wallBounceNumerator = 7
  static let wallBounceDenominator = 8
  static let floorBounceNumerator = 3
  static let floorBounceDenominator = 4
  static let settleVelocity = 2
  static let fieldHeightInset = 6
  static let fieldWidthInset = 2
  static let initialLaunchX = 0
  static let initialLaunchY = -10

  struct BoundsID: Hashable {
    let width: Int
    let height: Int

    init(size: CellSize) {
      width = size.width
      height = size.height
    }
  }

  struct State: Equatable {
    var position = FixedPoint.zero
    var velocity = FixedVelocity.zero
  }

  struct FixedPoint: Equatable {
    var x: Int
    var y: Int

    static let zero = Self(x: 0, y: 0)
  }

  struct FixedVelocity: Equatable {
    var x: Int
    var y: Int

    static let zero = Self(x: 0, y: 0)
  }

  static func displayPosition(
    for state: State,
    dragOffset: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> Point {
    let dragged = FixedPoint(
      x: state.position.x + Int((dragOffset.dx * Double(fixedScale)).rounded()),
      y: state.position.y + Int((dragOffset.dy * Double(fixedScale)).rounded())
    )
    let clampedPoint = clamped(dragged, in: bounds, metrics: metrics)
    return Point(
      x: Double(clampedPoint.x) / Double(fixedScale),
      y: Double(clampedPoint.y) / Double(fixedScale)
    )
  }

  static func applyRelease(
    to state: inout State,
    translation: Vector,
    velocity: Vector,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) {
    state.position.x += Int((translation.dx * Double(fixedScale)).rounded())
    state.position.y += Int((translation.dy * Double(fixedScale)).rounded())
    state = clamped(state, in: bounds, metrics: metrics)
    state.velocity = releaseVelocity(from: velocity, metrics: metrics)
  }

  static func spawnState(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> State {
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)
    return State(
      position: .init(
        x: maximumOrigin.x / 2,
        y: maximumOrigin.y
      ),
      velocity: .init(
        x: initialLaunchX,
        y: initialLaunchY
      )
    )
  }

  static func fieldBounds(
    from bounds: CellSize
  ) -> CellSize {
    CellSize(
      width: max(0, bounds.width - fieldWidthInset),
      height: max(0, bounds.height - fieldHeightInset)
    )
  }

  private static func releaseVelocity(
    from gestureVelocity: Vector,
    metrics: CellPixelMetrics
  ) -> FixedVelocity {
    FixedVelocity(
      x: fixedVelocityComponent(fromCellsPerSecond: gestureVelocity.dx),
      y: fixedVelocityComponent(
        fromCellsPerSecond: gestureVelocity.dy / metrics.aspectRatio
      )
    )
  }

  static func step(
    _ state: inout State,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) {
    state = clamped(state, in: bounds, metrics: metrics)
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)

    if state.position.y == maximumOrigin.y && state.velocity.y == 0 {
      state.velocity.x = damped(
        state.velocity.x,
        numerator: floorFrictionNumerator,
        denominator: floorFrictionDenominator,
        zeroBelow: 1
      )
    } else {
      let scaledGravity = max(
        1,
        Int((Double(gravityPerTick) / metrics.aspectRatio).rounded())
      )
      state.velocity.y += scaledGravity
    }

    state.position.x += state.velocity.x
    state.position.y += state.velocity.y

    if state.position.x < 0 {
      state.position.x = 0
      state.velocity.x = reflected(
        state.velocity.x,
        direction: 1,
        numerator: wallBounceNumerator,
        denominator: wallBounceDenominator
      )
    } else if state.position.x > maximumOrigin.x {
      state.position.x = maximumOrigin.x
      state.velocity.x = reflected(
        state.velocity.x,
        direction: -1,
        numerator: wallBounceNumerator,
        denominator: wallBounceDenominator
      )
    }

    if state.position.y < 0 {
      state.position.y = 0
      state.velocity.y = reflected(
        state.velocity.y,
        direction: 1,
        numerator: wallBounceNumerator,
        denominator: wallBounceDenominator
      )
    } else if state.position.y > maximumOrigin.y {
      state.position.y = maximumOrigin.y
      let bounced = reflected(
        state.velocity.y,
        direction: -1,
        numerator: floorBounceNumerator,
        denominator: floorBounceDenominator
      )
      state.velocity.y = abs(bounced) <= settleVelocity ? 0 : bounced
      state.velocity.x = damped(
        state.velocity.x,
        numerator: floorFrictionNumerator,
        denominator: floorFrictionDenominator,
        zeroBelow: 1
      )
    }
  }

  static func clamped(
    _ state: State,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> State {
    var state = state
    state.position = clamped(state.position, in: bounds, metrics: metrics)
    return state
  }

  static func maximumOrigin(
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let height = max(1, Int((Double(diameter) / metrics.aspectRatio).rounded()))
    return FixedPoint(
      x: max(0, bounds.width - diameter) * fixedScale,
      y: max(0, bounds.height - height) * fixedScale
    )
  }

  private static func clamped(
    _ point: FixedPoint,
    in bounds: CellSize,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)
    return FixedPoint(
      x: min(max(0, point.x), maximumOrigin.x),
      y: min(max(0, point.y), maximumOrigin.y)
    )
  }

  private static func fixedVelocityComponent(
    fromCellsPerSecond component: Double
  ) -> Int {
    Int(
      (Double(component) * Double(fixedScale) * Double(tickNanoseconds)
        / 1_000_000_000.0).rounded()
    )
  }

  private static func reflected(
    _ component: Int,
    direction: Int,
    numerator: Int,
    denominator: Int
  ) -> Int {
    let magnitude = max(1, abs(component) * numerator / denominator)
    return magnitude * direction
  }

  private static func damped(
    _ component: Int,
    numerator: Int,
    denominator: Int,
    zeroBelow threshold: Int
  ) -> Int {
    guard component != 0 else {
      return 0
    }

    let magnitude = abs(component) * numerator / denominator
    guard magnitude >= threshold else {
      return 0
    }
    return magnitude * (component < 0 ? -1 : 1)
  }
}
