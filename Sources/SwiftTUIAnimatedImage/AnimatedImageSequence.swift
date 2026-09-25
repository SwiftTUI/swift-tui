import Synchronization

/// Lazily-populated per-frame PNG byte cache (F153). Reference storage is
/// shared by value copies of the owning sequence; any `frames` mutation swaps
/// the box via `didSet`, so a mutated copy can never be served bytes encoded
/// from the pre-mutation frames.
private final class EncodedFrameStore: Sendable {
  private let slots = Mutex<[[UInt8]?]>([])

  func encodedData(
    at index: Int,
    frameCount: Int,
    encode: () -> [UInt8]
  ) -> [UInt8] {
    let cached = slots.withLock { slots in
      slots.indices.contains(index) ? slots[index] : nil
    }
    if let cached {
      return cached
    }
    let encoded = encode()
    slots.withLock { slots in
      if slots.count != frameCount {
        slots = Array(repeating: nil, count: frameCount)
      }
      if slots.indices.contains(index) {
        slots[index] = encoded
      }
    }
    return encoded
  }
}

/// A finite set of pre-composed frames and display delays.
public struct AnimatedImageSequence: Equatable, Hashable, Sendable {
  /// The sequence's frames. Replacements must keep the frame count and have
  /// matching pixel sizes; construct a new sequence to change frames and delays together.
  public var frames: [AnimatedImageFrame] {
    willSet {
      precondition(
        newValue.count == delayNanoseconds.count,
        "AnimatedImageSequence requires one delay per frame; construct a new sequence to change the count"
      )
      Self.validateFrames(newValue)
    }
    didSet {
      encodedFrameStore = EncodedFrameStore()
    }
  }
  internal var delayNanoseconds: [UInt64]
  /// GIF repeat count: `nil` means play once, `0` repeats forever, and a
  /// positive value repeats that many times after the initial play.
  /// Valid finite repeat counts are 1...65535. Programmatic initializers
  /// without this argument retain their historical infinite-loop default.
  public var loopCount: Int? {
    didSet { Self.validateLoopCount(loopCount) }
  }
  private var encodedFrameStore = EncodedFrameStore()

  /// PNG bytes for the frame at `index`, encoded once per frame (F153):
  /// playback loops and body re-evaluations reuse the cached encoding
  /// instead of re-running the encoder on every tick.
  internal func encodedImageData(at index: Int) -> [UInt8] {
    encodedFrameStore.encodedData(at: index, frameCount: frames.count) {
      frames[index].imageData
    }
  }

  // The encoded-frame store is derived data (invalidated on `frames`
  // mutation) and deliberately excluded: equality and hashing speak for the
  // authored value — frames and delays — exactly as the synthesized
  // conformances did before the cache existed.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.frames == rhs.frames && lhs.delayNanoseconds == rhs.delayNanoseconds
      && lhs.loopCount == rhs.loopCount
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(frames)
    hasher.combine(delayNanoseconds)
    hasher.combine(loopCount)
  }

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
    self.init(frames: frames, framesPerSecond: framesPerSecond, loopCount: 0)
  }

  public init(
    frames: [AnimatedImageFrame], framesPerSecond: Double, loopCount: Int?
  ) {
    precondition(
      framesPerSecond.isFinite && framesPerSecond > 0,
      "AnimatedImageSequence requires a positive finite frame rate"
    )
    let period = (1_000_000_000.0 / framesPerSecond).rounded()
    // A period past `UInt64` nanoseconds saturates like an enormous
    // `frameDelays` duration. `Double(UInt64.max)` rounds up to 2^64, the
    // first value that does not convert.
    let delay = period >= Double(UInt64.max) ? UInt64.max : UInt64(max(1, period))
    self.init(
      frames: frames,
      delayNanoseconds: Array(repeating: delay, count: frames.count), loopCount: loopCount
    )
  }

  public init(
    frames: [AnimatedImageFrame],
    frameDelays: [Duration]
  ) {
    self.init(frames: frames, frameDelays: frameDelays, loopCount: 0)
  }

  public init(
    frames: [AnimatedImageFrame], frameDelays: [Duration], loopCount: Int?
  ) {
    precondition(
      frames.count == frameDelays.count,
      "AnimatedImageSequence requires one delay per frame"
    )
    self.init(
      frames: frames,
      delayNanoseconds: frameDelays.map(Self.nanoseconds), loopCount: loopCount
    )
  }

  internal init(
    frames: [AnimatedImageFrame],
    delayNanoseconds: [UInt64], loopCount: Int? = 0
  ) {
    Self.validateFrames(frames)
    precondition(
      frames.count == delayNanoseconds.count,
      "AnimatedImageSequence requires one delay per frame"
    )
    self.frames = frames
    self.delayNanoseconds = delayNanoseconds.map { max(1, $0) }
    Self.validateLoopCount(loopCount)
    self.loopCount = loopCount
  }

  private static func validateLoopCount(_ value: Int?) {
    precondition(
      value == nil || (0...65535).contains(value!), "GIF loop count must be absent or in 0...65535")
  }

  private static func validateFrames(_ frames: [AnimatedImageFrame]) {
    precondition(!frames.isEmpty, "AnimatedImageSequence requires at least one frame")
    let firstSize = frames[0].pixelSize
    precondition(
      frames.allSatisfy { $0.pixelSize == firstSize },
      "AnimatedImageSequence requires all frames to have the same pixel size")
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
