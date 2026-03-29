/// A monotonic point in time used by the frame scheduler.
public struct MonotonicInstant: Equatable, Comparable, Hashable, Sendable {
  public var offset: Duration

  public init(offset: Duration = .zero) {
    self.offset = offset
  }

  public static let zero = Self()

  public static func now() -> Self {
    Self(
      offset: MonotonicClockStorage.origin.duration(
        to: MonotonicClockStorage.clock.now
      )
    )
  }

  public func advanced(by duration: Duration) -> Self {
    Self(offset: offset + duration)
  }

  public func duration(to other: Self) -> Duration {
    other.offset - offset
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.offset < rhs.offset
  }
}

private enum MonotonicClockStorage {
  static let clock = ContinuousClock()
  static let origin = clock.now
}
