import SwiftTUICore

/// One terminal presentation submission and its fate.
///
/// The frame row in `frames.tsv` is emitted at commit, but the `write(2)` that
/// puts those bytes on the wire completes later on the presentation-writer
/// queue. Rather than delay the frame row (which would reorder the sink
/// contract and lose rows on teardown), write completion is a separate record
/// keyed by the same run-loop frame ordinal, so a reducer can join the two by
/// `frame` and derive input→write latency.
@_spi(Runners) public struct PresentationWriteSample: Sendable {
  @_spi(Runners) public enum Outcome: String, Sendable {
    /// The submission reached `write(2)`.
    case written
    /// A newer frame superseded it while it was still pending, or a write
    /// failure discarded it. These bytes never reached the terminal — the
    /// record exists so the join stays total and a dropped frame is visible
    /// as a drop rather than as a missing row.
    case superseded
  }

  /// Run-loop frame ordinal this submission carries — the same value as the
  /// `frame` column in `frames.tsv`.
  @_spi(Runners) public var frame: Int
  /// When the frame was handed to the presentation writer, on the main actor.
  @_spi(Runners) public var submittedAt: MonotonicInstant
  /// When `write(2)` returned, on the writer queue. `nil` when superseded.
  @_spi(Runners) public var writtenAt: MonotonicInstant?
  /// UTF-8 byte count of the submitted emission.
  @_spi(Runners) public var bytes: Int
  @_spi(Runners) public var outcome: Outcome

  @_spi(Runners) public init(
    frame: Int,
    submittedAt: MonotonicInstant,
    writtenAt: MonotonicInstant?,
    bytes: Int,
    outcome: Outcome
  ) {
    self.frame = frame
    self.submittedAt = submittedAt
    self.writtenAt = writtenAt
    self.bytes = bytes
    self.outcome = outcome
  }
}

/// Sink for per-submission presentation write records.
///
/// Conformers must tolerate calls from the presentation-writer queue as well
/// as the main actor: submission and supersession are recorded on the main
/// actor, completion on the writer queue.
@_spi(Runners) public protocol PresentationWriteSink: Sendable {
  func record(_ sample: PresentationWriteSample)
}

/// The run-loop frame ordinal currently being presented.
///
/// Published by the frame driver for the dynamic extent of the present call so
/// the terminal host can stamp the submission it hands to the presentation
/// writer. The writer's own sequence counter cannot serve as the join key: it
/// only advances when a frame actually emits bytes, so a cell-identical frame
/// desynchronises it from the run-loop frame ordinal that `frames.tsv` reports.
package enum PresentingFrameOrdinal {
  @TaskLocal package static var current: Int?
}
