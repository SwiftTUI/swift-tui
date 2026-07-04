import SwiftTUICore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#endif

#if !canImport(WASILibc)
  struct TerminalRawModeRestorePlan {
    var savedAttributes: termios?
    var savedInputFileStatusFlags: Int32?
    var mouseCoordinateMode: MouseCoordinateMode
    var pointerHoverEnabled: Bool
    var kittyKeyboardPushed: Bool
  }

  struct TerminalRawModeSession {
    private var savedAttributes: termios?
    private var savedInputFileStatusFlags: Int32?
    private var processExitCleanupToken: UInt64?

    var isEnabled = false
    var mouseCoordinateMode = MouseCoordinateMode.cells
    var pointerHoverEnabled = false
    var kittyKeyboardPushed = false

    mutating func activate(
      savedAttributes: termios,
      inputFileStatusFlags: Int32,
      mouseCoordinateMode: MouseCoordinateMode,
      inputFileDescriptor: Int32,
      outputFileDescriptor: Int32
    ) {
      self.savedAttributes = savedAttributes
      savedInputFileStatusFlags = inputFileStatusFlags
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
        savedAttributes: savedAttributes,
        savedInputFileStatusFlags: savedInputFileStatusFlags,
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
        let savedAttributes,
        let savedInputFileStatusFlags
      else {
        return
      }

      processExitCleanupToken = TerminalProcessExitCleanupRegistry.register(
        .init(
          inputFileDescriptor: inputFileDescriptor,
          outputFileDescriptor: outputFileDescriptor,
          inputFileStatusFlags: savedInputFileStatusFlags,
          savedAttributes: savedAttributes,
          resetBytes: processExitResetBytes()
        )
      )
    }

    private mutating func unregisterProcessExitCleanup() {
      TerminalProcessExitCleanupRegistry.unregister(processExitCleanupToken)
      processExitCleanupToken = nil
    }

    private mutating func reset() {
      savedAttributes = nil
      savedInputFileStatusFlags = nil
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
