import TerminalUI

struct FullScreenTab: View {
  @State private var toyState = FullScreenToyPhysics.State()
  @State private var didSeedInitialPosition = false
  @GestureState private var dragOffset = Size.zero
  @GestureState private var gestureIsActive = false

  var body: some View {
    GeometryReader { proxy in
      let bounds = proxy.size
      let playfieldBounds = FullScreenToyPhysics.playfieldBounds(from: bounds)
      let current = FullScreenToyPhysics.displayPosition(
        for: toyState,
        dragOffset: dragOffset,
        in: playfieldBounds
      )

      ZStack(alignment: .topLeading) {
        Rectangle()
          .frame(
            width: FullScreenToyPhysics.blockSize.width,
            height: FullScreenToyPhysics.blockSize.height
          )
          .offset(x: current.x, y: current.y)
          .foregroundStyle(.cyan)
          .gesture(dragGesture(in: playfieldBounds))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.black)
      .task(id: FullScreenToyPhysics.BoundsID(size: playfieldBounds)) { @MainActor in
        await runToyLoop(in: playfieldBounds)
      }
    }
    .padding(2)
    .background(.tint)
  }

  private func dragGesture(
    in bounds: Size
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
          in: bounds
        )
      }
  }

  @MainActor
  private func runToyLoop(
    in bounds: Size
  ) async {
    if !didSeedInitialPosition {
      toyState = FullScreenToyPhysics.spawnState(in: bounds)
      didSeedInitialPosition = true
    } else {
      toyState = FullScreenToyPhysics.clamped(toyState, in: bounds)
    }

    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: FullScreenToyPhysics.tickNanoseconds)
      guard !gestureIsActive else {
        continue
      }

      var next = toyState
      FullScreenToyPhysics.step(&next, in: bounds)
      guard next != toyState else {
        continue
      }
      toyState = next
    }
  }
}

struct FullScreenToyPhysics {
  static let blockSize = Size(width: 6, height: 3)
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
  static let initialLaunchX = 0
  static let initialLaunchY = -10

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
    in bounds: Size
  ) -> Point {
    let dragged = FixedPoint(
      x: state.position.x + dragOffset.width * fixedScale,
      y: state.position.y + dragOffset.height * fixedScale
    )
    let clampedPoint = clamped(dragged, in: bounds)
    return Point(
      x: clampedPoint.x / fixedScale,
      y: clampedPoint.y / fixedScale
    )
  }

  static func applyRelease(
    to state: inout State,
    translation: Size,
    velocity: Size,
    in bounds: Size
  ) {
    state.position.x += translation.width * fixedScale
    state.position.y += translation.height * fixedScale
    state = clamped(state, in: bounds)
    state.velocity = releaseVelocity(from: velocity)
  }

  static func spawnState(
    in bounds: Size
  ) -> State {
    let maximumOrigin = maximumOrigin(in: bounds)
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
      width: bounds.width,
      height: max(0, bounds.height - playfieldHeightInset)
    )
  }

  static func releaseVelocity(
    from gestureVelocity: Size
  ) -> FixedVelocity {
    FixedVelocity(
      x: fixedVelocityComponent(fromCellsPerSecond: gestureVelocity.width),
      y: fixedVelocityComponent(fromCellsPerSecond: gestureVelocity.height)
    )
  }

  static func step(
    _ state: inout State,
    in bounds: Size
  ) {
    state = clamped(state, in: bounds)
    let maximumOrigin = maximumOrigin(in: bounds)

    if state.position.y == maximumOrigin.y && state.velocity.y == 0 {
      state.velocity.x = damped(
        state.velocity.x,
        numerator: floorFrictionNumerator,
        denominator: floorFrictionDenominator,
        zeroBelow: 1
      )
    } else {
      state.velocity.y += gravityPerTick
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
    in bounds: Size
  ) -> State {
    var state = state
    state.position = clamped(state.position, in: bounds)
    return state
  }

  static func maximumOrigin(
    in bounds: Size
  ) -> FixedPoint {
    FixedPoint(
      x: max(0, bounds.width - blockSize.width) * fixedScale,
      y: max(0, bounds.height - blockSize.height) * fixedScale
    )
  }

  private static func clamped(
    _ point: FixedPoint,
    in bounds: Size
  ) -> FixedPoint {
    let maximumOrigin = maximumOrigin(in: bounds)
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
