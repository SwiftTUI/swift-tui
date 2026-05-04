/// A finite set of pre-composed frames and display delays.
public struct AnimatedImageSequence: Equatable, Hashable, Sendable {
  public var frames: [AnimatedImageFrame]
  internal var delayNanoseconds: [UInt64]

  public var frameDelays: [Duration] {
    delayNanoseconds.map { delay in
      let clamped = delay > UInt64(Int64.max) ? Int64.max : Int64(delay)
      return .nanoseconds(clamped)
    }
  }

  public init(
    frames: [AnimatedImageFrame],
    framesPerSecond: Double
  ) {
    precondition(
      framesPerSecond.isFinite && framesPerSecond > 0,
      "AnimatedImageSequence requires a positive finite frame rate"
    )
    let delay = UInt64(max(1, (1_000_000_000.0 / framesPerSecond).rounded()))
    self.init(
      frames: frames,
      delayNanoseconds: Array(repeating: delay, count: frames.count)
    )
  }

  public init(
    frames: [AnimatedImageFrame],
    frameDelays: [Duration]
  ) {
    precondition(
      frames.count == frameDelays.count,
      "AnimatedImageSequence requires one delay per frame"
    )
    self.init(
      frames: frames,
      delayNanoseconds: frameDelays.map(Self.nanoseconds)
    )
  }

  internal init(
    frames: [AnimatedImageFrame],
    delayNanoseconds: [UInt64]
  ) {
    precondition(!frames.isEmpty, "AnimatedImageSequence requires at least one frame")
    precondition(
      frames.count == delayNanoseconds.count,
      "AnimatedImageSequence requires one delay per frame"
    )
    let firstSize = frames[0].pixelSize
    precondition(
      frames.allSatisfy {
        $0.pixelSize.width == firstSize.width && $0.pixelSize.height == firstSize.height
      },
      "AnimatedImageSequence requires all frames to have the same pixel size"
    )
    self.frames = frames
    self.delayNanoseconds = delayNanoseconds.map { max(1, $0) }
  }

  private static func nanoseconds(
    for duration: Duration
  ) -> UInt64 {
    precondition(duration > .zero, "AnimatedImageSequence frame delays must be positive")
    let components = duration.components

    let seconds = components.seconds > 0 ? UInt64(components.seconds) : 0
    let secondNanoseconds: UInt64
    if seconds > UInt64.max / 1_000_000_000 {
      secondNanoseconds = UInt64.max
    } else {
      secondNanoseconds = seconds * 1_000_000_000
    }

    let attoseconds = components.attoseconds > 0 ? UInt64(components.attoseconds) : 0
    let fractionalNanoseconds = (attoseconds + 999_999_999) / 1_000_000_000

    let (total, overflow) = secondNanoseconds.addingReportingOverflow(fractionalNanoseconds)
    return overflow ? UInt64.max : max(1, total)
  }
}
