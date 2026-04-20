import TerminalUI

struct FullScreenTab: View {
  @State private var toyState = FullScreenToyPhysics.State()
  @State private var didSeedInitialPosition = false
  @GestureState private var dragOffset = Size.zero
  @GestureState private var gestureIsActive = false

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let metrics = proxy.cellPixelMetrics
      let playfieldBounds = FullScreenToyPhysics.playfieldBounds(from: bounds)
      let current = FullScreenToyPhysics.displayPosition(
        for: toyState,
        dragOffset: dragOffset,
        in: playfieldBounds,
        metrics: metrics
      )
      let block = FullScreenToyPhysics.blockSize(metrics: metrics)

      ZStack(alignment: .topLeading) {
        Rectangle()
          .frame(width: block.width, height: block.height)
          .offset(x: current.x, y: current.y)
          .foregroundStyle(.cyan)
          .gesture(dragGesture(in: playfieldBounds, metrics: metrics))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.black)
      .task(id: FullScreenToyPhysics.BoundsID(size: playfieldBounds)) { @MainActor in
        await runToyLoop(in: playfieldBounds, metrics: metrics)
      }
    }
    .border(.tint)
    .background(.tint)
  }

  private func dragGesture(
    in bounds: Size,
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
    in bounds: Size,
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
  static let blockWidth = 6
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
  static let playfieldHeightInset = 6
  static let playfieldWidthtInset = 2
  static let initialLaunchX = 0
  static let initialLaunchY = -10

  /// Height of the rectangular subject in cells, scaled so its *visual*
  /// aspect is square regardless of the terminal's cell aspect.
  static func blockSize(metrics: CellPixelMetrics) -> Size {
    let height = max(1, Int((Double(blockWidth) / metrics.aspectRatio).rounded()))
    return Size(width: blockWidth, height: height)
  }

  struct BoundsID: Hashable {
    let width: Int
    let height: Int

    init(size: Size) {
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
    dragOffset: Size,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> Point {
    let dragged = FixedPoint(
      x: state.position.x + dragOffset.width * fixedScale,
      y: state.position.y + dragOffset.height * fixedScale
    )
    let clampedPoint = clamped(dragged, in: bounds, metrics: metrics)
    return Point(
      x: clampedPoint.x / fixedScale,
      y: clampedPoint.y / fixedScale
    )
  }

  static func applyRelease(
    to state: inout State,
    translation: Size,
    velocity: Size,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) {
    state.position.x += translation.width * fixedScale
    state.position.y += translation.height * fixedScale
    state = clamped(state, in: bounds, metrics: metrics)
    state.velocity = releaseVelocity(from: velocity, metrics: metrics)
  }

  static func spawnState(
    in bounds: Size,
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

  static func playfieldBounds(
    from bounds: Size
  ) -> Size {
    Size(
      width: max(0, bounds.width - playfieldWidthtInset),
      height: max(0, bounds.height - playfieldHeightInset)
    )
  }

  private static func releaseVelocity(
    from gestureVelocity: Size,
    metrics: CellPixelMetrics
  ) -> FixedVelocity {
    FixedVelocity(
      x: fixedVelocityComponent(fromCellsPerSecond: gestureVelocity.width),
      y: fixedVelocityComponent(
        fromCellsPerSecond: Int(
          (Double(gestureVelocity.height) / metrics.aspectRatio).rounded()
        )
      )
    )
  }

  static func step(
    _ state: inout State,
    in bounds: Size,
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
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> State {
    var state = state
    state.position = clamped(state.position, in: bounds, metrics: metrics)
    return state
  }

  static func maximumOrigin(
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let block = blockSize(metrics: metrics)
    return FixedPoint(
      x: max(0, bounds.width - block.width) * fixedScale,
      y: max(0, bounds.height - block.height) * fixedScale
    )
  }

  private static func clamped(
    _ point: FixedPoint,
    in bounds: Size,
    metrics: CellPixelMetrics
  ) -> FixedPoint {
    let maximumOrigin = maximumOrigin(in: bounds, metrics: metrics)
    return FixedPoint(
      x: min(max(0, point.x), maximumOrigin.x),
      y: min(max(0, point.y), maximumOrigin.y)
    )
  }

  private static func fixedVelocityComponent(
    fromCellsPerSecond component: Int
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
