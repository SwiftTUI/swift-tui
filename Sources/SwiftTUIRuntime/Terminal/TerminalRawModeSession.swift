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
    var savedSnapshot: TerminalModeSnapshot?
    var mouseCoordinateMode: MouseCoordinateMode
    var pointerHoverEnabled: Bool
    var kittyKeyboardPushed: Bool
  }

  struct TerminalRawModeSession {
    private var savedSnapshot: TerminalModeSnapshot?
    private var processExitCleanupToken: UInt64?

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
      savedSnapshot = snapshot
      self.mouseCoordinateMode = mouseCoordinateMode
      isEnabled = true
      refreshProcessExitCleanupRegistration(
        inputFileDescriptor: inputFileDescriptor,
        outputFileDescriptor: outputFileDescriptor
      )
    }

    mutating func deactivate() -> TerminalRawModeRestorePlan {
      unregisterProcessExitCleanup()
      let restorePlan = TerminalRawModeRestorePlan(
        savedSnapshot: savedSnapshot,
        mouseCoordinateMode: mouseCoordinateMode,
        pointerHoverEnabled: pointerHoverEnabled,
        kittyKeyboardPushed: kittyKeyboardPushed
      )
      reset()
      return restorePlan
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
      mouseCoordinateMode = .cells
      pointerHoverEnabled = false
      kittyKeyboardPushed = false
    }

    private func processExitResetBytes() -> [UInt8] {
      Array(
        TerminalHostEscapeSequences.processExitReset(
          mouseCoordinateMode: mouseCoordinateMode,
          hoverEnabled: pointerHoverEnabled,
          kittyKeyboardPushed: kittyKeyboardPushed
        ).utf8
      )
    }
  }
#endif
