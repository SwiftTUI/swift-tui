import SwiftTUICore
import SwiftTUIViews

// Runtime environment-action factories.
//
// Several `Environment` actions ship as inert placeholders so views can read
// them before a run loop exists. When the run loop assembles a frame's
// `ResolveContext` (see `resolveContext(for:)`), it swaps any still-placeholder
// action for the live runtime implementation built here: focus reset wired to
// the scheduler, and clipboard read/write wired to the presentation surface.
extension RunLoop {
  /// Live termination action. The scheduler wake lets requests from lifecycle
  /// tasks leave a run loop even when no input event is pending.
  package func runtimeRequestTerminationAction() -> RequestTerminationAction {
    RequestTerminationAction(
      snapshotLabel: "RequestTerminationAction.runtime",
      isPlaceholder: false
    ) { [weak self] in
      guard let self, isSessionActive else { return false }
      hasPendingProgrammaticTermination = true
      scheduler.requestExternalWake(reason: "programmatic-termination")
      return true
    }
  }

  package func consumeProgrammaticTerminationRequest() -> RunLoopExitReason? {
    guard hasPendingProgrammaticTermination else { return nil }
    hasPendingProgrammaticTermination = false
    if terminationDisposition(for: .programmatic) == .cancel {
      scheduler.requestInvalidation(of: [rootIdentity])
      return nil
    }
    return .programmatic
  }

  /// Live `resetFocus` action: clears local default-focus state for the given
  /// namespace and asks the scheduler to re-resolve the root.
  package func runtimeResetFocusAction() -> ResetFocusAction {
    ResetFocusAction(
      snapshotLabel: "ResetFocusAction.runtime",
      isPlaceholder: false,
      handler: { [weak scheduler, localDefaultFocusRegistry, rootIdentity] namespace in
        localDefaultFocusRegistry.requestReset(in: namespace)
        scheduler?.requestInvalidation(of: [rootIdentity])
        return true
      }
    )
  }

  /// Live `clipboardWrite` action. Returns `false` when the presentation
  /// surface cannot write to a clipboard or the write throws.
  package func runtimeClipboardWriteAction() -> ClipboardWriteAction {
    ClipboardWriteAction(
      snapshotLabel: "ClipboardWriteAction.runtime",
      isPlaceholder: false
    ) { [weak self] text in
      guard let self, !terminalHandoffInProgress,
        let surface = presentationSurface as? any ClipboardWritingPresentationSurface
      else {
        return false
      }

      do {
        return try surface.writeClipboard(text)
      } catch {
        return false
      }
    }
  }

  /// Live `clipboardRead` action. Returns `nil` when the presentation surface
  /// cannot read a clipboard or the read throws.
  package func runtimeClipboardReadAction() -> ClipboardReadAction {
    ClipboardReadAction(
      snapshotLabel: "ClipboardReadAction.runtime",
      isPlaceholder: false
    ) { [weak self] in
      guard let self, !terminalHandoffInProgress,
        let surface = presentationSurface as? any ClipboardReadingPresentationSurface
      else {
        return nil
      }

      do {
        return try surface.readClipboard()
      } catch {
        return nil
      }
    }
  }

  /// Live terminal handoff action. The run loop owns suspension, terminal
  /// modes, capability synchronization, and repaint recovery; authored code
  /// supplies only the asynchronous operation to run while the shell owns the
  /// terminal.
  package func runtimeTerminalHandoffAction() -> TerminalHandoffAction {
    TerminalHandoffAction(
      snapshotLabel: "TerminalHandoffAction.runtime",
      isPlaceholder: false
    ) { [weak self] operation in
      guard let self else {
        throw TerminalHandoffError.unavailable
      }
      try await self.performTerminalHandoff(operation)
    }
  }

  package func performTerminalHandoff(
    _ operation: @escaping @MainActor @Sendable () async throws -> Void
  ) async throws {
    guard terminalHandoffPlatformSupportsExclusiveInputOwnership,
      runtimeConfiguration.output == .tui,
      let terminalSurface = presentationSurface as? any TerminalCommandPresentationSurface,
      let inputSuspender = terminalInputReader as? any TerminalInputHandoffSuspending,
      let sessionGeneration = activeTerminalHandoffSessionGeneration
    else {
      throw TerminalHandoffError.unavailable
    }
    guard !terminalHandoffInProgress else {
      throw TerminalHandoffError.alreadyInProgress
    }

    terminalHandoffInProgress = true
    var restoredTerminal = false
    defer {
      terminalHandoffInProgress = false
      if restoredTerminal {
        scheduler.requestExternalWake(reason: "terminal-handoff-restored")
      }
    }

    await waitForTerminalRenderPassToFinish()

    try await inputSuspender.withInputSuspended {
      do {
        try terminalSurface.disableRawMode()
      } catch let disableError {
        do {
          try restoreTerminalAfterHandoff(
            using: terminalSurface,
            sessionGeneration: sessionGeneration
          )
          restoredTerminal = true
        } catch let error as TerminalHandoffError {
          throw error
        } catch {
          throw TerminalHandoffError.failedToRestoreTerminal
        }
        throw disableError
      }

      do {
        try await operation()
      } catch {
        do {
          try restoreTerminalAfterHandoff(
            using: terminalSurface,
            sessionGeneration: sessionGeneration
          )
          restoredTerminal = true
        } catch let error as TerminalHandoffError {
          throw error
        } catch {
          throw TerminalHandoffError.failedToRestoreTerminal
        }
        throw error
      }

      do {
        try restoreTerminalAfterHandoff(
          using: terminalSurface,
          sessionGeneration: sessionGeneration
        )
        restoredTerminal = true
      } catch let error as TerminalHandoffError {
        throw error
      } catch {
        throw TerminalHandoffError.failedToRestoreTerminal
      }
    }
  }

  private func restoreTerminalAfterHandoff(
    using terminalSurface: any TerminalCommandPresentationSurface,
    sessionGeneration: UInt64
  ) throws {
    // An unstructured task may outlive the run loop that injected its action.
    // Never reclaim terminal ownership after that session's shutdown, or an
    // old task could strand the shell in raw mode or steal a later session's
    // alternate screen.
    guard activeTerminalHandoffSessionGeneration == sessionGeneration else {
      throw TerminalHandoffError.unavailable
    }
    try terminalSurface.enableRawMode()
    synchronizeInputCapabilities()

    // The external operation owned the primary screen and may have changed
    // every visible cell. Forget both presentation baselines and force the
    // next frame through root evaluation before requesting the wake.
    previousPresentedRasterSurface = nil
    renderer.forceRootEvaluation(source: .terminalHandoff)
    scheduler.requestInvalidation(of: [rootIdentity])
  }

  package func activateTerminalHandoffSession() {
    nextTerminalHandoffSessionGeneration &+= 1
    activeTerminalHandoffSessionGeneration = nextTerminalHandoffSessionGeneration
  }

  package func deactivateTerminalHandoffSession() {
    activeTerminalHandoffSessionGeneration = nil
  }

  package func beginTerminalRenderPassIfAvailable() -> Bool {
    guard !terminalHandoffInProgress else {
      return false
    }
    precondition(!terminalRenderPassInProgress, "terminal render passes must not overlap")
    terminalRenderPassInProgress = true
    return true
  }

  package func endTerminalRenderPass() {
    guard terminalRenderPassInProgress else {
      return
    }
    terminalRenderPassInProgress = false
    let waiters = terminalRenderPassWaiters
    terminalRenderPassWaiters.removeAll(keepingCapacity: true)
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func waitForTerminalRenderPassToFinish() async {
    guard terminalRenderPassInProgress else {
      return
    }
    await withCheckedContinuation { continuation in
      terminalRenderPassWaiters.append(continuation)
    }
  }
}

/// Whether this platform can stop SwiftTUI's input consumer before a handoff.
///
/// WASI's ANSI runner currently reads stdin from a detached polling task. Its
/// cooperative I/O has no pause-and-ack primitive, so allowing a handoff would
/// let SwiftTUI race the external operation for the same bytes. Fail closed
/// until that runner can prove exclusive input ownership.
package var terminalHandoffPlatformSupportsExclusiveInputOwnership: Bool {
  #if canImport(WASILibc)
    false
  #else
    true
  #endif
}
