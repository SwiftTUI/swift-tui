import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(ucrt)
  import CRT
#endif

#if canImport(Dispatch)
  @unsafe @preconcurrency import Dispatch
#endif

#if !canImport(WASILibc)
  struct TerminalPresentationFrame: Sendable {
    /// Monotonic content-frame ordinal assigned by the host, or `nil` for
    /// supplemental-only output (accessibility cursor focus) that carries no
    /// cell content and therefore never moves the diff baseline.
    var sequence: UInt64?
    var output: String
    /// Run-loop frame ordinal this submission carries, published by the frame
    /// driver through ``PresentingFrameOrdinal``. The join key between
    /// `frames.tsv` and `presents.tsv`; `nil` when nothing published one
    /// (supplemental output, a host driven outside a frame).
    var frameOrdinal: Int?
    /// Instant the frame was handed to the writer.
    var submittedAt: MonotonicInstant
  }

  struct TerminalPresentationEmission {
    var output = ""
    var graphicsReplayScope = TerminalPresentationMetrics.GraphicsReplayScope.none
    var graphicsAttachmentsReplayed = 0
    var editOperationLowering = TerminalPresentationMetrics.EditOperationLowering.none
    var editOperationCount = 0
    var scrollRegionOperationCount = 0

    mutating func append(_ output: String) {
      self.output.append(output)
    }

    mutating func recordGraphicsReplay(
      scope: TerminalPresentationMetrics.GraphicsReplayScope,
      attachmentCount: Int
    ) {
      graphicsReplayScope = scope
      graphicsAttachmentsReplayed = attachmentCount
    }

    mutating func recordEraseToEndOfLine() {
      editOperationLowering = .eraseToEndOfLine
      editOperationCount += 1
    }

    mutating func recordScrollRegionOperation() {
      scrollRegionOperationCount += 1
    }

    func metrics(
      for plan: TerminalPresentationPlan,
      output: String,
      usedSynchronizedOutput: Bool
    ) -> TerminalPresentationMetrics {
      var metrics = TerminalPresentationMetrics(
        bytesWritten: output.utf8.count,
        linesTouched: plan.linesTouched,
        cellsChanged: plan.cellsChanged,
        strategy: plan.strategy == TerminalPresentationPlan.Strategy.fullRepaint
          ? TerminalPresentationMetrics.Strategy.fullRepaint
          : TerminalPresentationMetrics.Strategy.incremental,
        usedSynchronizedOutput: usedSynchronizedOutput,
        graphicsReplayScope: graphicsReplayScope,
        graphicsAttachmentsReplayed: graphicsAttachmentsReplayed,
        editOperationLowering: editOperationLowering,
        editOperationCount: editOperationCount
      )
      metrics.scrollRegionOperationCount = scrollRegionOperationCount
      return metrics
    }
  }

  /// Serializes terminal writes without making the render loop wait for
  /// blocking file-descriptor output.
  ///
  /// The writer keeps only the newest pending frame. A frame's sequence is
  /// recorded as committed at *dequeue* time, under the same lock that clears
  /// `pending`: a dequeued frame is guaranteed to reach the terminal before
  /// anything submitted later, while a still-pending frame can be discarded
  /// with certainty it never will. `reconcileBeforePlanning()` gives
  /// `TerminalHost` that dichotomy so recovery after a dropped frame can diff
  /// against the last surface actually written instead of full repainting.
  final class TerminalPresentationWriter: Sendable {
    private struct State: Sendable {
      var pending: TerminalPresentationFrame?
      // Cursor/control bytes are independent of replaceable cell content.
      var supplementalOutput = ""
      var isWriting = false
      var lastCommittedSequence: UInt64 = 0
      var pendingError: TerminalHostError?
    }

    private let writeBudget = TerminalWriteBudget()
    private let controller: any TerminalControlling
    private let outputFileDescriptor: Int32
    private let queue = DispatchQueue(label: "swift-tui.presentation-writer")
    private let state = Mutex(State())
    /// Per-submission write records, when profiling installed a sink. Resolved
    /// once at construction: the registry read takes a lock, and the write
    /// path must not pay for it per frame. `nil` — the default — makes every
    /// recording site a single branch.
    private let writeSink: (any PresentationWriteSink)?

    init(
      controller: any TerminalControlling,
      outputFileDescriptor: Int32,
      writeSink: (any PresentationWriteSink)? = nil
    ) {
      self.controller = controller
      self.outputFileDescriptor = outputFileDescriptor
      self.writeSink = writeSink
    }

    func submit(
      _ frame: TerminalPresentationFrame
    ) {
      // A pending content frame replaced here never reaches the terminal.
      // Record the supersession rather than staying silent: a missing row
      // would make the join partial, and the dropped frame's write latency
      // would silently read as the latency of the frame that displaced it.
      //
      // Captured under the lock, recorded after it — a sink write is a
      // syscall, and this is the main actor's present path. Instrumentation
      // that stalls the thing it measures is not a measurement.
      var superseded: TerminalPresentationFrame?
      let admitted = startWriterIfNeeded { state in
        superseded = state.pending
        state.pending = frame
      }
      recordSupersessionIfNeeded(of: admitted ? superseded : frame)
    }

    func submitSupplementalOutput(_ output: String) {
      guard !output.isEmpty else {
        return
      }

      startWriterIfNeeded { state in
        state.supplementalOutput.append(output)
      }
    }

    /// Discards any still-pending content frame — the caller is about to
    /// supersede it, and once removed under the lock it can never be written —
    /// and returns the sequence of the last content frame handed to the
    /// terminal write. Supplemental-only pending output is left in place: it
    /// carries no cell content, so it cannot invalidate a diff baseline.
    func reconcileBeforePlanning() -> UInt64 {
      var superseded: TerminalPresentationFrame?
      let lastCommittedSequence = state.withLock { state -> UInt64 in
        if state.pending?.sequence != nil {
          superseded = state.pending
          state.pending = nil
        }
        return state.lastCommittedSequence
      }
      recordSupersessionIfNeeded(of: superseded)
      return lastCommittedSequence
    }

    func lastCommittedSequence() -> UInt64 {
      state.withLock { state in
        state.lastCommittedSequence
      }
    }

    func consumePendingError() throws {
      let pendingError = state.withLock { state in
        let pendingError = state.pendingError
        state.pendingError = nil
        return pendingError
      }

      if let pendingError {
        throw pendingError
      }
    }

    func drain() {
      queue.sync {}
    }

    func finishWithin(_ duration: Duration) {
      writeBudget.finishWithin(duration)
      drain()
    }

    @discardableResult
    private func startWriterIfNeeded(
      updatePendingFrame: (inout State) -> Void
    ) -> Bool {
      let (admitted, shouldStart) = state.withLock { state in
        guard state.pendingError == nil else {
          return (false, false)
        }

        updatePendingFrame(&state)

        guard !state.isWriting else {
          return (true, false)
        }

        state.isWriting = true
        return (true, true)
      }

      if shouldStart {
        queue.async { [self] in
          writePendingFrames()
        }
      }
      return admitted
    }

    private func writePendingFrames() {
      while true {
        let batch: (frame: TerminalPresentationFrame, output: String)? = state.withLock { state in
          guard state.pending != nil || !state.supplementalOutput.isEmpty else {
            state.isWriting = false
            return nil
          }
          let frame =
            state.pending
            ?? TerminalPresentationFrame(
              sequence: nil, output: "", frameOrdinal: nil, submittedAt: .now())
          let output = frame.output + state.supplementalOutput
          state.supplementalOutput = ""
          state.pending = nil
          if let sequence = frame.sequence {
            state.lastCommittedSequence = sequence
          }
          return (frame, output)
        }

        guard let batch else { return }
        let frame = batch.frame
        do {
          try controller.write(batch.output, to: outputFileDescriptor, budget: writeBudget)
          recordWriteCompletion(of: frame)
        } catch let error as TerminalHostError {
          recordWriteFailure(error, frame: frame)
          return
        } catch {
          recordWriteFailure(.failedToWrite(errno: EIO), frame: frame)
          return
        }
      }
    }

    private func recordWriteFailure(_ error: TerminalHostError, frame: TerminalPresentationFrame) {
      var superseded: TerminalPresentationFrame?
      state.withLock { state in
        superseded = state.pending
        state.pending = nil
        state.supplementalOutput = ""
        state.isWriting = false
        state.pendingError = error
      }
      recordSupersessionIfNeeded(of: superseded)
      recordOutcome(of: frame, outcome: .failed, writtenAt: nil)
    }

    /// Records a completed `write(2)` — called from the writer queue, right
    /// after the bytes are on the wire.
    private func recordWriteCompletion(of frame: TerminalPresentationFrame) {
      recordOutcome(of: frame, outcome: .written, writtenAt: .now())
    }

    /// Records a pending submission that will never be written.
    ///
    /// Called at each of the three discard sites (supersede on submit,
    /// supersede before planning, discard on write failure). Each captures the
    /// displaced frame *under* the lock that clears `pending` — so a
    /// submission is recorded as written or as superseded, never both and
    /// never neither — and calls this *outside* it, keeping the sink's own
    /// write off the presentation lock.
    private func recordSupersessionIfNeeded(of frame: TerminalPresentationFrame?) {
      guard let frame else { return }
      recordOutcome(of: frame, outcome: .superseded, writtenAt: nil)
    }

    private func recordOutcome(
      of frame: TerminalPresentationFrame,
      outcome: PresentationWriteSample.Outcome,
      writtenAt: MonotonicInstant?
    ) {
      guard let writeSink, let frameOrdinal = frame.frameOrdinal else { return }
      writeSink.record(
        PresentationWriteSample(
          frame: frameOrdinal,
          submittedAt: frame.submittedAt,
          writtenAt: writtenAt,
          bytes: frame.output.utf8.count,
          outcome: outcome
        )
      )
    }
  }

  /// Retained presentation state for one terminal session.
  ///
  /// The diff baseline is the last surface known to have reached the terminal
  /// write. Each submitted frame is tracked in flight until `reconcile` learns
  /// its fate from the writer: a committed frame becomes the new baseline; a
  /// dropped frame never reached the terminal, so the baseline stays put and
  /// the Kitty bookkeeping rolls back to its pre-submission snapshot. Recovery
  /// after a drop is therefore an ordinary incremental diff — a full repaint
  /// happens when the baseline is unknown or explicit damage requires it.
  struct TerminalPresentationSession {
    /// A submitted content frame whose write outcome is not yet known.
    struct InFlightFrame {
      var sequence: UInt64
      var surface: RasterSurface
      /// Kitty bookkeeping as it stood before this frame's emission was
      /// built, restored wholesale if the frame is dropped (its placements
      /// and data transmissions never reached the terminal).
      var transmittedKittyImagesBeforeSubmission: Set<UInt32>
      var residentKittyImageDataBeforeSubmission: Set<UInt32>
    }

    /// Surface of the last content frame known to have reached the terminal
    /// write — the only sound diff baseline.
    var lastWrittenSurface: RasterSurface?
    var inFlightFrame: InFlightFrame?
    var nextFrameSequence: UInt64 = 1
    /// Cleared when an in-flight frame is dropped: the pipeline computes its
    /// damage hint against the frame it last *presented*, so after a drop the
    /// hint is too narrow for the rolled-back baseline. Restored once the next
    /// plan has consumed (ignored) the stale hint.
    var requestedDamageTrustsBaseline = true
    /// Kitty image ids with a *placement* we can re-place by id. Cleared on
    /// invalidation / repaint so the recovery frame re-transmits (the
    /// on-screen placement can no longer be trusted).
    var transmittedKittyImages: Set<UInt32> = []
    /// Kitty image ids whose *pixel data* is resident in the terminal's store.
    /// Unlike placements, stored image data survives a screen clear — kitty
    /// only releases it on an explicit delete (`d=I` / `d=A`). So this is
    /// preserved across invalidations, letting the recovery frame free the
    /// images it superseded instead of leaking one per repaint.
    var residentKittyImageData: Set<UInt32> = []
    var writer: TerminalPresentationWriter?

    mutating func reset() {
      lastWrittenSurface = nil
      inFlightFrame = nil
      nextFrameSequence = 1
      requestedDamageTrustsBaseline = true
      transmittedKittyImages.removeAll()
      residentKittyImageData.removeAll()
      writer = nil
    }

    mutating func invalidateRetainedState() {
      lastWrittenSurface = nil
      inFlightFrame = nil
      requestedDamageTrustsBaseline = true
      transmittedKittyImages.removeAll()
    }

    /// Resolves the in-flight frame against the writer's committed sequence:
    /// committed frames become the written baseline; dropped frames roll the
    /// Kitty bookkeeping back and leave the baseline untouched.
    mutating func reconcile(lastCommittedSequence: UInt64) {
      guard let inFlightFrame else {
        return
      }
      if inFlightFrame.sequence <= lastCommittedSequence {
        lastWrittenSurface = inFlightFrame.surface
      } else {
        transmittedKittyImages = inFlightFrame.transmittedKittyImagesBeforeSubmission
        residentKittyImageData = inFlightFrame.residentKittyImageDataBeforeSubmission
        requestedDamageTrustsBaseline = false
      }
      self.inFlightFrame = nil
    }

    var previousSurface: RasterSurface? {
      lastWrittenSurface
    }

    func presentationDamage(
      requested damage: PresentationDamage?
    ) -> PresentationDamage? {
      guard !requestedDamageTrustsBaseline, let damage else { return damage }
      guard
        damage.requiresFullTextRepaint || damage.requiresFullGraphicsReplay
          || !damage.graphicsInvalidation.isEmpty
      else { return nil }
      guard let surface = previousSurface else { return damage }
      return PresentationDamage(
        dirtyRows: Set(0..<max(0, surface.size.height)),
        graphicsInvalidation: damage.graphicsInvalidation,
        requiresFullTextRepaint: damage.requiresFullTextRepaint,
        requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay)
    }

    /// Resolves a run-loop scroll-translation candidate against the trust
    /// latch. The candidate claims "this surface is the previous *presented*
    /// surface shifted by dy" — but after a writer drop the previously
    /// presented surface never reached the terminal and the written baseline
    /// rolled back, so the claim is unsound for exactly the one recovery
    /// frame the latch already flags for the damage hint. Must be read at
    /// plan time, BEFORE the latch re-arms, like
    /// ``presentationDamage(requested:)``.
    func presentationTranslationCandidate(
      requested candidate: ScrollTranslationCandidate?
    ) -> ScrollTranslationCandidate? {
      requestedDamageTrustsBaseline ? candidate : nil
    }
  }
#endif
