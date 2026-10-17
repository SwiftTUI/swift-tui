#if canImport(Darwin) || canImport(Glibc)
  import Foundation
  import Synchronization
  import Testing
  import SwiftTUIRuntime
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUIPTYPrimitives

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(Android)
    import Android
  #elseif canImport(Musl)
    import Musl
  #endif

  @Suite(.serialized, .timeLimit(.minutes(1)))
  struct AdversarialSetATerminalProcessBoundaryTests {
    @Test func setA1091OutOfRangePTYDimensionsFailSafelyInsteadOfTrapping() async {
      // Hypothesis: unchecked UInt16 conversion traps before a throwing PTY resize can reject an external terminal size.
      do {
        await #expect(processExitsWith: .success) {
          let handles = try openPTY()
          defer {
            closeFD(handles.masterFD)
            closeFD(handles.slaveFD)
          }
          for columns in [-1, Int(UInt16.max) + 1, Int.max] {
            do {
              try ptyResize(masterFD: handles.masterFD, cols: columns, rows: 24)
            } catch is PTYError {
              // Both safe rejection and bounded normalization satisfy this oracle.
            }
          }
        }
      }
    }

    @Test func setA1092AnUnrepresentableCArgumentCannotSilentlyRunWithATruncatedValue() async throws
    {
      // Hypothesis: strdup accepts an embedded NUL and exec receives a different argument from the caller's String.
      let control = "space 雪 ' quoted"
      let valid = try await runChild(arguments: ["-c", "printf '%s' \"$1\"", "probe", control])
      #expect(valid.status == .exited(code: 0))
      #expect(valid.text == control)
      var rejected = false
      do {
        let invalid = try await runChild(arguments: [
          "-c", "printf '%s' \"$1\"", "probe", "prefix\0suffix",
        ])
        rejected = invalid.status != .exited(code: 0)
      } catch is PTYError {
        rejected = true
      }
      do {
        #expect(rejected)
      }
    }

    @Test func setA1093AnExecChildCannotInheritAnotherTerminalsOwnedDescriptors() async throws {
      // Hypothesis: openPTY leaves FD_CLOEXEC clear, allowing an unrelated terminal child to keep another session's PTY alive.
      let other = try openPTY()
      defer {
        closeFD(other.masterFD)
        closeFD(other.slaveFD)
      }
      let result = try await runChild(arguments: [
        "-c",
        // Compare device identity, not just a numeric FD the shell could reuse.
        "if [ /dev/fd/\"$1\" -ef \"$2\" ]; then printf leaked-slave; fi",
        "probe", String(other.slaveFD), other.slavePath,
      ])
      #expect(result.status == .exited(code: 0))
      do {
        #expect(result.text.isEmpty)
      }
      #expect(fcntl(other.masterFD, F_GETFD) >= 0)
      #expect(fcntl(other.slaveFD, F_GETFD) >= 0)
    }

    @Test func setA1094WorkingDirectorySelectionDoesNotInterpretPathCharactersOrFallBackOnFailure()
      async throws
    {
      // Hypothesis: a child working directory is shell-interpreted or a failed chdir silently executes in its parent's directory.
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SetA1094 space 雪 ' \(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let result = try await runChild(
        arguments: ["-c", "printf '%s' \"$PWD\""], workingDirectory: directory.path)
      #expect(result.status == .exited(code: 0))
      #expect(
        URL(fileURLWithPath: result.text).resolvingSymlinksInPath().path
          == directory.resolvingSymlinksInPath().path)
      let invalid = try await runChild(
        arguments: ["-c", "printf should-not-execute"],
        workingDirectory: directory.appendingPathComponent("missing").path)
      #expect(invalid.status == .exited(code: 127))
      #expect(invalid.text.isEmpty)
    }

    @Test func setA1095ExplicitChildEnvironmentReplacesInheritanceAndPreservesValueBytes()
      async throws
    {
      // Hypothesis: explicit environment construction merges ambient variables or splits values containing equals/newlines.
      let value = "雪=first\nsecond"
      let result = try await runChild(
        executable: "/usr/bin/env", arguments: [],
        environment: ["SET_A_1095": value])
      #expect(result.status == .exited(code: 0))
      #expect(result.text == "SET_A_1095=雪=first\r\nsecond\r\n")
    }

    @Test func setA1096TerminalInterruptBytesReachTheChildForegroundProcessGroup() async throws {
      // Hypothesis: a spawned child lacks the controlling-terminal foreground group or inherits an ignored interrupt disposition.
      let child = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "printf READY; exec /bin/sleep 10"],
        initialSize: .init(width: 80, height: 24))
      try await withChild(child) { pair in
        var started: [UInt8] = []
        for await chunk in await pair.read() {
          started += chunk
          if String(decoding: started, as: UTF8.self).contains("READY") { break }
        }
        try Task.checkCancellation()
        try #require(String(decoding: started, as: UTF8.self).contains("READY"))
        try await pair.write([3])
        let status = await child.waitForExit()
        try Task.checkCancellation()
        #expect(status == .signalled(signal: SIGINT))
      }
    }

    @Test func setA1097AllThreeChildStandardDescriptorsShareTheControllingTTY() async throws {
      // Hypothesis: child descriptor setup leaves stderr or stdin on the parent's pipes instead of the allocated terminal.
      let result = try await runChild(arguments: [
        "-c", "test -t 0 && test -t 1 && test -t 2 || exit 33; printf 'out'; printf 'err' >&2",
      ])
      #expect(result.status == .exited(code: 0))
      #expect(result.text == "outerr")
    }

    @Test func setA1098ConcurrentExitObserversReceiveTheSameRealStatus() async throws {
      // Hypothesis: one continuation slot makes a second live observer receive a fabricated unknown exit status.
      let child = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "read line; exit 23"],
        initialSize: .init(width: 80, height: 24))
      try await withChild(child) { pair in
        let registered = Mutex(0)
        let ready = ConditionSignal()
        await child.setExitWaiterRegistrationHandlerForTesting {
          registered.withLock { $0 += 1 }
          ready.notify()
        }
        let results = try await withThrowingTaskGroup(of: ChildProcessPty.ExitStatus.self) {
          group in
          for _ in 0..<2 {
            group.addTask { await child.waitForExit() }
          }
          do {
            // The child stays blocked on read until both calls have made their
            // actual actor-isolated registration decision, including rejection.
            await ready.wait(until: { registered.withLock { $0 == 2 } })
            try Task.checkCancellation()
            await child.setExitWaiterRegistrationHandlerForTesting(nil)
            try await pair.write(Array("release\n".utf8))
            var statuses: [ChildProcessPty.ExitStatus] = []
            for try await status in group { statuses.append(status) }
            return statuses
          } catch {
            // waitForExit does not observe cancellation. Releasing the owned
            // child must precede joining the group's pending exit observer.
            await child.requestSignal(SIGKILL)
            throw error
          }
        }
        try Task.checkCancellation()
        #expect(results.count == 2)
        do {
          #expect(results.allSatisfy { $0 == .exited(code: 23) }, "Observed statuses: \(results)")
        }
        #expect(await child.waitForExit() == .exited(code: 23))
      }
    }

    @Test func setA1099ClosingOneTerminalCannotHangUpAnIndependentChild() async throws {
      // Hypothesis: process-group or descriptor ownership crosses terminal instances during one session's teardown.
      let first = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "read line"],
        initialSize: .init(width: 80, height: 24))
      let second = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "read line; printf 'survivor:%s' \"$line\""],
        initialSize: .init(width: 80, height: 24))
      try await withChild(second) { b in
        try await withChild(first) { a in
          await a.close()
          // A leaked unrelated descriptor can delay hangup; explicitly reap this owned child as cleanup.
          await first.requestSignal(SIGTERM)
          _ = await first.waitForExit()
          try Task.checkCancellation()
        }
        // Retire the first child's cancellation owner before awaiting the
        // survivor; its already-reaped pid must no longer receive signals.
        try await b.write(Array("ok\n".utf8))
        var bytes: [UInt8] = []
        for await chunk in await b.read() { bytes += chunk }
        try Task.checkCancellation()
        let status = await second.waitForExit()
        #expect(status == .exited(code: 0))
        #expect(String(decoding: bytes, as: UTF8.self).contains("survivor:ok"))
      }
    }

    @Test func setA1100RepeatedExitQueriesRetainStatusWithoutLeavingReapableChildren() async throws
    {
      // Hypothesis: post-exit queries re-wait the pid or rapid terminal churn leaves unreaped children and open masters.
      for code in 20..<28 {
        let child = ChildProcessPty(
          executable: "/bin/sh", arguments: ["-c", "exit \(code)"],
          initialSize: .init(width: 80, height: 24))
        try await withChild(child) { pair in
          let pid = await child.pid
          let first = await child.waitForExit()
          let again = await child.waitForExit()
          for await _ in await pair.read() {}
          try Task.checkCancellation()
          await pair.close()
          #expect(first == .exited(code: Int32(code)))
          #expect(again == first)
          var status: Int32 = 0
          let reapedAgain = unsafe waitpid(pid, &status, WNOHANG)
          let failure = errno
          #expect(reapedAgain == -1 && failure == ECHILD)
          #expect(await pair.rawMasterFD == -1)
        }
      }
    }

    @Test func processInputsAreValidatedBeforeAllocatingAChild() async {
      let invalidChildren = [
        ChildProcessPty(executable: "/bin/sh\0ignored", initialSize: .init(width: 80, height: 24)),
        ChildProcessPty(
          executable: "/bin/sh", environment: ["bad=key": "value"],
          initialSize: .init(width: 80, height: 24)),
        ChildProcessPty(
          executable: "/bin/sh", environment: ["key": "value\0tail"],
          initialSize: .init(width: 80, height: 24)),
        ChildProcessPty(
          executable: "/bin/sh", workingDirectory: "/tmp\0tail",
          initialSize: .init(width: 80, height: 24)),
        ChildProcessPty(executable: "/bin/sh", initialSize: .init(width: Int.max, height: 24)),
      ]
      for child in invalidChildren {
        // An admission failure must leave no child/PTY and must release the
        // startup latch, so a retry reports the original failure again.
        for _ in 0..<2 {
          do {
            try await child.start()
            Issue.record("invalid process configuration started")
            await child.requestSignal(SIGKILL)
            _ = await child.waitForExit()
            await child.pair?.close()
          } catch {
            #expect(error != .alreadyStarted)
          }
          #expect(await child.pid == 0)
          #expect(await child.pair == nil)
        }
      }
    }

    @Test func bothPTYDescriptorsAreCloseOnExec() throws {
      let handles = try openPTY()
      defer {
        closeFD(handles.masterFD)
        closeFD(handles.slaveFD)
      }
      for descriptor in [handles.masterFD, handles.slaveFD] {
        #expect(fcntl(descriptor, F_GETFD) & FD_CLOEXEC != 0)
      }
    }

    private func runChild(
      executable: String = "/bin/sh", arguments: [String], environment: [String: String]? = nil,
      workingDirectory: String? = nil
    ) async throws -> (status: ChildProcessPty.ExitStatus, text: String) {
      let child = ChildProcessPty(
        executable: executable, arguments: arguments,
        environment: environment, workingDirectory: workingDirectory,
        initialSize: .init(width: 80, height: 24))
      return try await withChild(child) { pair in
        var bytes: [UInt8] = []
        for await chunk in await pair.read() { bytes += chunk }
        try Task.checkCancellation()
        let status = await child.waitForExit()
        return (status, String(decoding: bytes, as: UTF8.self))
      }
    }

    private struct ChildCancellation {
      var finished = false
      var cleanup: Task<Void, Never>?
    }

    private func withChild<Result: Sendable>(
      _ child: ChildProcessPty,
      operation: @Sendable (PTYPair) async throws -> Result
    ) async throws -> Result {
      try await child.start()
      let pair = try #require(await child.pair)
      let cancellation = Mutex(ChildCancellation())
      let result = try await withTaskCancellationHandler {
        do {
          try Task.checkCancellation()
          let result = try await operation(pair)
          let cleanup = cancellation.withLock { state in
            state.finished = true
            return state.cleanup
          }
          await cleanup?.value
          await child.setExitWaiterRegistrationHandlerForTesting(nil)
          _ = await child.waitForExit()
          await pair.close()
          return result
        } catch {
          let cleanup = cancellation.withLock { state in
            state.finished = true
            return state.cleanup
          }
          // Join cancellation cleanup before leaving the fixture so a delayed
          // signal cannot escape this test and target a subsequently reused pid.
          if let cleanup {
            await cleanup.value
          } else {
            await child.requestSignal(SIGKILL)
          }
          await child.setExitWaiterRegistrationHandlerForTesting(nil)
          _ = await child.waitForExit()
          await pair.close()
          throw error
        }
      } onCancel: {
        cancellation.withLock { state in
          guard !state.finished else { return }
          state.cleanup = Task {
            await child.requestSignal(SIGKILL)
            await pair.close()
          }
        }
      }
      // A late cancellation after successful reaping must not enter the error
      // path and signal the child's now-retired pid.
      try Task.checkCancellation()
      return result
    }
  }
#endif
