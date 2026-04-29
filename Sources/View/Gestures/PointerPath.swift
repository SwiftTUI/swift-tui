public import Core

/// Ordered pointer samples captured during a gesture.
///
/// The sample `location` is expressed in the gesture value's coordinate space.
/// The `pointer` retains the original event-level provenance for callers that
/// need to inspect precision, containing cell, or raw host/protocol pixels.
public struct PointerPath: Equatable, Hashable, Sendable, RandomAccessCollection {
  public struct Sample: Equatable, Hashable, Sendable {
    /// The sample location in the gesture value's coordinate space.
    public var location: Point
    /// The monotonic timestamp attached to the pointer event.
    public var time: MonotonicInstant
    /// The original pointer event location and precision provenance.
    public var pointer: PointerLocation

    public init(
      location: Point,
      time: MonotonicInstant,
      pointer: PointerLocation
    ) {
      self.location = location
      self.time = time
      self.pointer = pointer
    }
  }

  private var samples: [Sample]

  public init(
    _ samples: [Sample] = []
  ) {
    self.samples = samples
  }

  public var startIndex: Int { samples.startIndex }
  public var endIndex: Int { samples.endIndex }

  public subscript(position: Int) -> Sample {
    samples[position]
  }
}
