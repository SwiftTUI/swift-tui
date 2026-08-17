import Synchronization

// Plain (internal) imports: with the reset action holding an opaque
// TerminalModeSnapshot, no libc type appears in this file's package surface.
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
  package struct TerminalProcessExitResetAction: Sendable {
    package let inputFileDescriptor: Int32
    package let outputFileDescriptor: Int32
    package let savedSnapshot: TerminalModeSnapshot
    package let resetBytes: [UInt8]

    package func perform() {
      if !resetBytes.isEmpty {
        unsafe resetBytes.withUnsafeBytes { bytes in
          guard let baseAddress = bytes.baseAddress else {
            return
          }

          var offset = 0
          while offset < bytes.count {
            let written = unsafe terminalPlatformWrite(
              outputFileDescriptor,
              unsafe baseAddress.advanced(by: offset),
              bytes.count - offset
            )
            guard written > 0 else {
              break
            }
            offset += written
          }
        }
      }

      // Restores inline rather than through a controller: this runs from an
      // atexit handler, where allocation and actor hops are off-limits.
      #if canImport(ucrt)
        // The Windows console-mode/code-page restore arrives with Stage 4 of
        // the Windows plan.
      #else
        _ = fcntl(inputFileDescriptor, F_SETFL, savedSnapshot.inputFileStatusFlags)
        var attributes = savedSnapshot.attributes
        _ = unsafe tcsetattr(inputFileDescriptor, TCSAFLUSH, &attributes)
      #endif
    }
  }

  package enum TerminalProcessExitCleanupRegistry {
    private struct State {
      var didInstallHandler = false
      var nextToken: UInt64 = 0
      var actions: [(token: UInt64, action: TerminalProcessExitResetAction)] = []
    }

    private static let state = Mutex(State())

    package static func register(
      _ action: TerminalProcessExitResetAction
    ) -> UInt64? {
      state.withLock { state in
        if !state.didInstallHandler {
          guard atexit(runTerminalProcessExitCleanup) == 0 else {
            return nil
          }
          state.didInstallHandler = true
        }

        let token = state.nextToken
        state.nextToken += 1
        state.actions.append((token: token, action: action))
        return token
      }
    }

    package static func unregister(
      _ token: UInt64?
    ) {
      guard let token else {
        return
      }

      state.withLock { state in
        state.actions.removeAll { $0.token == token }
      }
    }

    package static func runForTesting() {
      let actions = state.withLock { state in
        let actions = state.actions
          .sorted { lhs, rhs in lhs.token > rhs.token }
          .map(\.action)
        state.actions.removeAll()
        return actions
      }

      for action in actions {
        action.perform()
      }
    }
  }

  private func runTerminalProcessExitCleanup() {
    TerminalProcessExitCleanupRegistry.runForTesting()
  }
#endif
