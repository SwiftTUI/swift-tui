import SwiftTUICore

/// One terminal presentation submission and its fate.
///
/// The frame row in `frames.tsv` is emitted at commit, but the `write(2)` that
/// puts those bytes on the wire completes later on the presentation-writer
/// queue. The sink does not delay the frame row because a delay can reorder the sink contract.
/// A delay can also lose rows during teardown.
/// Instead, write completion is a separate record with the same run-loop frame ordinal.
/// A reducer can join the two records by `frame` and calculate input→write latency.
@_spi(Runners) public struct PresentationWriteSample: Sendable {
  @_spi(Runners) public enum Outcome: String, Sendable {
    /// The submission reached `write(2)`.
    case written
    /// A newer frame superseded it while it was still pending, or a write
    /// failure discarded it. These bytes never reached the terminal. The
    /// record exists so the join stays total and a dropped frame is visible
    /// as a drop rather than as a missing row.
    case superseded
  }

  /// Run-loop frame ordinal this submission carries, the same value as the
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
/// Conformers must accept calls from the presentation-writer queue and the main actor.
/// The main actor records submission and supersession.
/// The writer queue records completion.
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

/// The scroll-translation candidate for the frame currently being presented
/// (R2.2), published by the frame driver for the dynamic extent of the
/// present call — the same channel as ``PresentingFrameOrdinal``, and for the
/// same reason: the presentation-surface protocols stay untouched while the
/// terminal host reads the frame-scoped value it needs. Consumers MUST
/// resolve it through
/// `TerminalPresentationSession.presentationTranslationCandidate(requested:)`
/// before the trust latch re-arms, exactly like the damage hint.
package enum PresentingScrollTranslation {
  @TaskLocal package static var current: ScrollTranslationCandidate?
}
