import SwiftTUICore
import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
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
  }

  struct TerminalPresentationEmission {
    var output = ""
    var graphicsReplayScope = TerminalPresentationMetrics.GraphicsReplayScope.none
    var graphicsAttachmentsReplayed = 0
    var editOperationLowering = TerminalPresentationMetrics.EditOperationLowering.none
    var editOperationCount = 0

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

    func metrics(
      for plan: TerminalPresentationPlan,
      output: String,
      usedSynchronizedOutput: Bool
    ) -> TerminalPresentationMetrics {
      TerminalPresentationMetrics(
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
      var isWriting = false
      var lastCommittedSequence: UInt64 = 0
      var pendingError: TerminalHostError?
    }

    private let controller: any TerminalControlling
    private let outputFileDescriptor: Int32
    private let queue = DispatchQueue(label: "swift-tui.presentation-writer")
    private let state = Mutex(State())

    init(
      controller: any TerminalControlling,
      outputFileDescriptor: Int32
    ) {
      self.controller = controller
      self.outputFileDescriptor = outputFileDescriptor
    }

    func submit(
      _ frame: TerminalPresentationFrame
    ) {
      startWriterIfNeeded { state in
        state.pending = frame
      }
    }

    func submitSupplementalOutput(_ output: String) {
      guard !output.isEmpty else {
        return
      }

      startWriterIfNeeded { state in
        if state.pending != nil {
          state.pending?.output.append(output)
        } else {
          state.pending = .init(sequence: nil, output: output)
        }
      }
    }

    /// Discards any still-pending content frame — the caller is about to
    /// supersede it, and once removed under the lock it can never be written —
    /// and returns the sequence of the last content frame handed to the
    /// terminal write. Supplemental-only pending output is left in place: it
    /// carries no cell content, so it cannot invalidate a diff baseline.
    func reconcileBeforePlanning() -> UInt64 {
      state.withLock { state in
        if state.pending?.sequence != nil {
          state.pending = nil
        }
        return state.lastCommittedSequence
      }
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

    private func startWriterIfNeeded(
      updatePendingFrame: (inout State) -> Void
    ) {
      let shouldStart = state.withLock { state in
        guard state.pendingError == nil else {
          return false
        }

        updatePendingFrame(&state)

        guard !state.isWriting else {
          return false
        }

        state.isWriting = true
        return true
      }

      guard shouldStart else {
        return
      }

      queue.async { [self] in
        writePendingFrames()
      }
    }

    private func writePendingFrames() {
      while true {
        let frame: TerminalPresentationFrame? = state.withLock { state in
          guard let frame = state.pending else {
            state.isWriting = false
            return nil
          }

          state.pending = nil
          if let sequence = frame.sequence {
            state.lastCommittedSequence = sequence
          }
          return frame
        }

        guard let frame else {
          return
        }

        do {
          try controller.write(frame.output, to: outputFileDescriptor)
        } catch let error as TerminalHostError {
          recordWriteFailure(error)
          return
        } catch {
          recordWriteFailure(.failedToWrite(errno: EIO))
          return
        }
      }
    }

    private func recordWriteFailure(_ error: TerminalHostError) {
      state.withLock { state in
        state.pending = nil
        state.isWriting = false
        state.pendingError = error
      }
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
  /// happens only when no written baseline exists at all.
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
      requestedDamageTrustsBaseline ? damage : nil
    }
  }
#endif
