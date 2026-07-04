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
  /// The writer keeps only the newest pending frame. When a newer frame
  /// replaces an unwritten one, `consumeDropFlag()` tells `TerminalHost` to
  /// recover with a full repaint so retained terminal state is not trusted.
  final class TerminalPresentationWriter: Sendable {
    private struct State: Sendable {
      var pending: TerminalPresentationFrame?
      var isWriting = false
      var didDropFrame = false
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
        if state.pending != nil {
          state.didDropFrame = true
        }
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
          state.pending = .init(output: output)
        }
      }
    }

    func consumeDropFlag() -> Bool {
      state.withLock { state in
        let didDropFrame = state.didDropFrame
        state.didDropFrame = false
        return didDropFrame
      }
    }

    func hasPendingFrame() -> Bool {
      state.withLock { state in
        state.pending != nil
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
  /// A dropped queued frame invalidates both the retained raster surface and
  /// the Kitty image-id cache. The next submitted frame must full repaint so
  /// the terminal's screen contents and graphics placements are known again.
  struct TerminalPresentationSession {
    var lastSubmittedSurface: RasterSurface?
    /// Kitty image ids with a *placement* we can re-place by id. Cleared on drop
    /// / invalidation / repaint so the recovery frame re-transmits (the on-screen
    /// placement can no longer be trusted).
    var transmittedKittyImages: Set<UInt32> = []
    /// Kitty image ids whose *pixel data* is resident in the terminal's store.
    /// Unlike placements, stored image data survives a screen clear or a dropped
    /// frame — kitty only releases it on an explicit delete (`d=I` / `d=A`). So
    /// this is preserved across drops/invalidations, letting the recovery frame
    /// free the images it superseded instead of leaking one per drop.
    var residentKittyImageData: Set<UInt32> = []
    var forceFullRepaint = false
    var writer: TerminalPresentationWriter?

    mutating func reset() {
      lastSubmittedSurface = nil
      transmittedKittyImages.removeAll()
      residentKittyImageData.removeAll()
      forceFullRepaint = false
      writer = nil
    }

    mutating func invalidateRetainedState() {
      lastSubmittedSurface = nil
      transmittedKittyImages.removeAll()
      forceFullRepaint = false
    }

    mutating func markDroppedFrame() {
      forceFullRepaint = true
      transmittedKittyImages.removeAll()
    }

    var previousSurface: RasterSurface? {
      forceFullRepaint ? nil : lastSubmittedSurface
    }

    func presentationDamage(
      requested damage: PresentationDamage?
    ) -> PresentationDamage? {
      forceFullRepaint ? nil : damage
    }
  }
#endif
