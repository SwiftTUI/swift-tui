import SwiftTUICore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(ucrt)
  import CRT
#endif

// Positive host test, not "not WASI" (Stage 3.5 of the Windows plan).
#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(ucrt)
  struct TerminalRawModeRestorePlan {
    var readerMode = false
    var savedSnapshot: TerminalModeSnapshot?
    var mouseCoordinateMode: MouseCoordinateMode
    var pointerHoverEnabled: Bool
    var kittyKeyboardPushed: Bool

    var resetOutput: String {
      readerMode
        ? TerminalHostEscapeSequences.disableBracketedPaste
          + TerminalHostEscapeSequences.showCursor + TerminalHostEscapeSequences.resetStyle
        : TerminalHostEscapeSequences.processExitReset(
          mouseCoordinateMode: mouseCoordinateMode,
          hoverEnabled: pointerHoverEnabled, kittyKeyboardPushed: kittyKeyboardPushed)
    }
  }

  struct TerminalRawModeSession {
    var readerMode = false
    private var savedSnapshot: TerminalModeSnapshot?
    private var processExitCleanupToken: UInt64?
    /// The process-exit fallback of a failed entry whose rollback could not
    /// finish (STUI-1121). It is owed apart from the session, which a failed
    /// entry always clears, until the next activation supersedes it.
    private var owedProcessExitCleanupToken: UInt64?
    /// The saved mode of a failed entry whose restore failed: the terminal is
    /// still raw, so the next entry's own capture would be a raw snapshot.
    private var unrestoredSnapshot: TerminalModeSnapshot?

    var ownsScreen = false
    var isEnabled = false
    var mouseCoordinateMode = MouseCoordinateMode.cells
    var pointerHoverEnabled = false
    var kittyKeyboardPushed = false

    mutating func activate(
      snapshot: TerminalModeSnapshot,
      mouseCoordinateMode: MouseCoordinateMode,
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32
    ) {
      savedSnapshot = unrestoredSnapshot ?? snapshot
      unrestoredSnapshot = nil
      self.mouseCoordinateMode = mouseCoordinateMode
      isEnabled = true
      refreshProcessExitCleanupRegistration(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor
      )
      // This session's own fallback carries the reset bytes and the original
      // snapshot, so a failed entry's owed fallback is superseded.
      TerminalProcessExitCleanupRegistry.unregister(owedProcessExitCleanupToken)
      owedProcessExitCleanupToken = nil
    }

    mutating func deactivate() -> TerminalRawModeRestorePlan {
      unregisterProcessExitCleanup()
      let plan = restorePlan
      reset()
      return plan
    }

    /// Clears the session after a failed entry, so a retry or a later session
    /// performs a fresh entry (STUI-1182). What the rollback could not finish
    /// stays owed apart from the session: when the reset bytes or the restore
    /// failed, the process-exit fallback stays registered (STUI-1121), and an
    /// unrestored snapshot becomes the next entry's saved mode.
    mutating func abandonFailedEntry(restoredOutput: Bool, restoredMode: Bool) {
      if restoredOutput, restoredMode {
        unregisterProcessExitCleanup()
      } else {
        TerminalProcessExitCleanupRegistry.unregister(owedProcessExitCleanupToken)
        owedProcessExitCleanupToken = processExitCleanupToken
        processExitCleanupToken = nil
        if !restoredMode { unrestoredSnapshot = savedSnapshot }
      }
      reset()
    }

    var restorePlan: TerminalRawModeRestorePlan {
      TerminalRawModeRestorePlan(
        readerMode: readerMode,
        savedSnapshot: savedSnapshot,
        mouseCoordinateMode: mouseCoordinateMode,
        pointerHoverEnabled: pointerHoverEnabled,
        kittyKeyboardPushed: kittyKeyboardPushed
      )
    }

    mutating func refreshProcessExitCleanupRegistration(
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32
    ) {
      unregisterProcessExitCleanup()
      guard isEnabled,
        let savedSnapshot
      else {
        return
      }

      processExitCleanupToken = TerminalProcessExitCleanupRegistry.register(
        .init(
          inputFileDescriptor: inputFileDescriptor,
          outputFileDescriptor: outputFileDescriptor,
          savedSnapshot: savedSnapshot,
          resetBytes: processExitResetBytes()
        )
      )
    }

    private mutating func unregisterProcessExitCleanup() {
      TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
      processExitCleanupToken = nil
    }

    private mutating func reset() {
      savedSnapshot = nil
      isEnabled = false
      ownsScreen = false
      mouseCoordinateMode = .cells
      // Hover is requested configuration, like readerMode, not active state.
      kittyKeyboardPushed = false
    }

    private func processExitResetBytes() -> [UInt8] {
      if readerMode {
        return Array(
          (TerminalHostEscapeSequences.disableBracketedPaste
            + TerminalHostEscapeSequences.showCursor + TerminalHostEscapeSequences.resetStyle).utf8)
      }
      return Array(
        TerminalHostEscapeSequences.processExitReset(
          mouseCoordinateMode: mouseCoordinateMode,
          hoverEnabled: pointerHoverEnabled,
          kittyKeyboardPushed: kittyKeyboardPushed
        ).utf8
      )
    }
  }
#endif
