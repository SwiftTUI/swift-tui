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
      await withKnownIssue("STUI-1036: unchecked PTY dimensions trap during UInt16 conversion") {
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
      withKnownIssue("STUI-1037: embedded NUL is silently truncated by argv construction") {
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
      withKnownIssue("STUI-1038: unrelated PTY descriptors lack close-on-exec isolation") {
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
      try await child.start()
      let guardTask = killAtDeadline(child)
      defer { guardTask.cancel() }
      let pair = try #require(await child.pair)
      do {
        var started: [UInt8] = []
        for await chunk in await pair.read() {
          started += chunk
          if String(decoding: started, as: UTF8.self).contains("READY") { break }
        }
        try #require(String(decoding: started, as: UTF8.self).contains("READY"))
        try await pair.write([3])
        let status = await child.waitForExit()
        #expect(status == .signalled(signal: SIGINT))
        await pair.close()
      } catch {
        await child.requestSignal(SIGKILL)
        _ = await child.waitForExit()
        await pair.close()
        throw error
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
      try await child.start()
      let pair = try #require(await child.pair)
      let guardTask = killAtDeadline(child)
      defer { guardTask.cancel() }
      let entered = Mutex(0)
      let completed = Mutex<[ChildProcessPty.ExitStatus]>([])
      let ready = ConditionSignal()
      let results = await withTaskGroup(of: ChildProcessPty.ExitStatus.self) { group in
        for _ in 0..<2 {
          group.addTask {
            entered.withLock { $0 += 1 }
            ready.notify()
            let result = await child.waitForExit()
            completed.withLock { $0.append(result) }
            ready.notify()
            return result
          }
        }
        await ready.wait(until: { entered.withLock { $0 == 2 } })
        // An early result witnesses the current defect while the child is held.
        // A fixed implementation waits until release. The scheduling bound is
        // not an oracle: only the actual final statuses are asserted below.
        await withTaskGroup(of: Void.self) { observation in
          observation.addTask { await ready.wait(until: { completed.withLock { !$0.isEmpty } }) }
          observation.addTask { try? await Task.sleep(for: .seconds(1)) }
          await observation.next()
          observation.cancelAll()
        }
        try? await pair.write(Array("release\n".utf8))
        var statuses: [ChildProcessPty.ExitStatus] = []
        for await status in group { statuses.append(status) }
        return statuses
      }
      await pair.close()
      #expect(results.count == 2)
      withKnownIssue("STUI-1039: a second exit observer returns unknown before the child exits") {
        #expect(results.allSatisfy { $0 == .exited(code: 23) }, "Observed statuses: \(results)")
      }
      #expect(await child.waitForExit() == .exited(code: 23))
    }

    @Test func setA1099ClosingOneTerminalCannotHangUpAnIndependentChild() async throws {
      // Hypothesis: process-group or descriptor ownership crosses terminal instances during one session's teardown.
      let first = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "read line"],
        initialSize: .init(width: 80, height: 24))
      let second = ChildProcessPty(
        executable: "/bin/sh", arguments: ["-c", "read line; printf 'survivor:%s' \"$line\""],
        initialSize: .init(width: 80, height: 24))
      try await first.start()
      let firstGuard = killAtDeadline(first)
      defer { firstGuard.cancel() }
      do { try await second.start() } catch {
        await first.requestSignal(SIGKILL)
        _ = await first.waitForExit()
        await first.pair?.close()
        throw error
      }
      let secondGuard = killAtDeadline(second)
      defer { secondGuard.cancel() }
      let a = try #require(await first.pair)
      let b = try #require(await second.pair)
      await a.close()
      // A leaked unrelated descriptor can delay hangup; explicitly reap this owned child as cleanup.
      await first.requestSignal(SIGTERM)
      _ = await first.waitForExit()
      do {
        try await b.write(Array("ok\n".utf8))
        var bytes: [UInt8] = []
        for await chunk in await b.read() { bytes += chunk }
        let status = await second.waitForExit()
        await b.close()
        #expect(status == .exited(code: 0))
        #expect(String(decoding: bytes, as: UTF8.self).contains("survivor:ok"))
      } catch {
        await second.requestSignal(SIGKILL)
        _ = await second.waitForExit()
        await b.close()
        throw error
      }
    }

    @Test func setA1100RepeatedExitQueriesRetainStatusWithoutLeavingReapableChildren() async throws
    {
      // Hypothesis: post-exit queries re-wait the pid or rapid terminal churn leaves unreaped children and open masters.
      for code in 20..<28 {
        let child = ChildProcessPty(
          executable: "/bin/sh", arguments: ["-c", "exit \(code)"],
          initialSize: .init(width: 80, height: 24))
        try await child.start()
        let guardTask = killAtDeadline(child)
        let pid = await child.pid
        let first = await child.waitForExit()
        let again = await child.waitForExit()
        let pair = try #require(await child.pair)
        for await _ in await pair.read() {}
        await pair.close()
        guardTask.cancel()
        #expect(first == .exited(code: Int32(code)))
        #expect(again == first)
        var status: Int32 = 0
        let reapedAgain = unsafe waitpid(pid, &status, WNOHANG)
        let failure = errno
        #expect(reapedAgain == -1 && failure == ECHILD)
        #expect(await pair.rawMasterFD == -1)
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
      try await child.start()
      let guardTask = killAtDeadline(child)
      defer { guardTask.cancel() }
      let pair = try #require(await child.pair)
      var bytes: [UInt8] = []
      for await chunk in await pair.read() { bytes += chunk }
      let status = await child.waitForExit()
      await pair.close()
      return (status, String(decoding: bytes, as: UTF8.self))
    }

    private func killAtDeadline(_ child: ChildProcessPty) -> Task<Void, Never> {
      Task {
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        await child.requestSignal(SIGKILL)
        await child.pair?.close()
      }
    }
  }
#endif
