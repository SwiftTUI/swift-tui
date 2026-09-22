// Excluded from Windows builds (Windows plan, Stage 6 item 3): exercises a
// POSIX-only subsystem whose modules build empty (or not at all) on Windows.
#if !os(Windows)

  // © OPTIONAL.DEV

  //===----------------------------------------------------------------------===//
  //
  // This source file is part of the SwiftServiceLifecycle open source project
  //
  // Copyright (c) 2023 Apple Inc. and the SwiftServiceLifecycle project authors
  // Licensed under Apache License v2.0
  //
  // See LICENSE.txt for license information
  // See CONTRIBUTORS.txt for the list of SwiftServiceLifecycle project authors
  //
  // SPDX-License-Identifier: Apache-2.0
  //
  //===----------------------------------------------------------------------===//

  #if !os(Windows)

    import Testing
    import SwiftTUIVendorUnixSignals
    #if canImport(Darwin)
      import Darwin
    #elseif canImport(Glibc)
      import Glibc
    #elseif canImport(Musl)
      import Musl
    #elseif canImport(Android)
      import Android
    #endif

    // These tests trap and raise process-global UNIX signals, so they must run
    // serially — parallel cases would steal each other's signal deliveries.
    @Suite(.serialized)
    struct UnixSignalTests {
      @Test func singleSignal() async {
        let signal = UnixSignal.sigalrm
        let signals = await UnixSignalsSequence(trapping: signal)
        let pid = getpid()

        var signalIterator = signals.makeAsyncIterator()
        kill(pid, signal.rawValue)  // ignore-unacceptable-language
        let caught = await signalIterator.next()
        #expect(caught == signal)
      }

      @Test func catchingMultipleSignals() async {
        let signal = UnixSignal.sigalrm
        let signals = await UnixSignalsSequence(trapping: signal)
        let pid = getpid()

        var signalIterator = signals.makeAsyncIterator()
        for _ in 0..<5 {
          kill(pid, signal.rawValue)  // ignore-unacceptable-language

          let caught = await signalIterator.next()
          #expect(caught == signal)
        }
      }

      @Test(arguments: [false, true])
      func cancelOnSignal(delayConsumer: Bool) async throws {
        enum GroupResult {
          case timedOut
          case cancelled
          case caughtSignal
        }

        // The async initializer acknowledges DispatchSource registration on
        // Darwin and Linux. Sending is safe even if the consumer has not run.
        let signals = await UnixSignalsSequence(trapping: .sigalrm)
        let start = AsyncStream<Void>.makeStream()
        defer { start.continuation.finish() }

        try await withThrowingTaskGroup(of: GroupResult.self) { group in
          defer { group.cancelAll() }
          group.addTask {
            do {
              // Diagnostic hang bound, not an expected scheduling duration.
              try await Task.sleep(for: .seconds(60))
              return .timedOut
            } catch {
              #expect(error is CancellationError)
              return .cancelled
            }
          }

          group.addTask {
            if delayConsumer {
              for await _ in start.stream { break }
            }
            for await _ in signals {
              return .caughtSignal
            }
            return .cancelled
          }

          let pid = getpid()
          kill(pid, UnixSignal.sigalrm.rawValue)  // ignore-unacceptable-language
          // Exercise signal buffering with the consumer deliberately held
          // until after delivery, without a sleep or scheduler-speed premise.
          start.continuation.yield(())

          let first = try await group.next()
          #expect(first == .caughtSignal)

          // Caught the signal; cancel the remaining task.
          group.cancelAll()
          let second = try await group.next()
          #expect(second == .cancelled)
        }
      }

      @Test func emptySequence() async {
        let signals = await UnixSignalsSequence(trapping: [])
        for await _ in signals {
          Issue.record("Unexpected signal")
        }
      }

      @Test func correctSignalIsGiven() async {
        let signals = await UnixSignalsSequence(
          trapping: .sigterm, .sigusr1, .sigusr2, .sighup, .sigint, .sigalrm)
        var signalIterator = signals.makeAsyncIterator()

        let signal = UnixSignal.sigalrm
        let pid = getpid()

        for _ in 0..<10 {
          kill(pid, signal.rawValue)  // ignore-unacceptable-language
          let trapped = await signalIterator.next()
          #expect(trapped == signal)
        }
      }

      @Test func signalRawValue() {
        func assert(_ signal: UnixSignal, rawValue: Int32) {
          #expect(signal.rawValue == rawValue)
        }

        assert(.sigalrm, rawValue: SIGALRM)
        assert(.sigint, rawValue: SIGINT)
        assert(.sigquit, rawValue: SIGQUIT)
        assert(.sighup, rawValue: SIGHUP)
        assert(.sigusr1, rawValue: SIGUSR1)
        assert(.sigusr2, rawValue: SIGUSR2)
        assert(.sigterm, rawValue: SIGTERM)
      }

      @Test func signalCustomStringConvertible() {
        func assert(_ signal: UnixSignal, description: String) {
          #expect(String(describing: signal) == description)
        }

        assert(.sigalrm, description: "SIGALRM")
        assert(.sigint, description: "SIGINT")
        assert(.sigquit, description: "SIGQUIT")
        assert(.sighup, description: "SIGHUP")
        assert(.sigusr1, description: "SIGUSR1")
        assert(.sigusr2, description: "SIGUSR2")
        assert(.sigterm, description: "SIGTERM")
        assert(.sigwinch, description: "SIGWINCH")
      }

      @Test func cancelledTask() async {
        let task = Task {
          try? await Task.sleep(nanoseconds: 1_000_000_000)

          let UnixSignalsSequence = await UnixSignalsSequence(trapping: .sigterm)

          for await _ in UnixSignalsSequence {}
        }

        task.cancel()

        await task.value
      }
    }

  #endif

#endif
