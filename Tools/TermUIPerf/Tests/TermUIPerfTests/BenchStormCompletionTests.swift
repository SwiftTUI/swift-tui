import Foundation
@_spi(Runners) import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import TermUIPerf

@MainActor
struct BenchStormCompletionTests {
  @Test("the unchanged storm view renders every observed counter update")
  func actualStormViewTracksRepeatedCounterUpdates() {
    let model = PerfStormModel()
    let root = PerfStormView(model: model, rowCount: BenchStormScenario.rowCount)
    let renderer = DefaultRenderer()
    let proposal = ProposedSize(width: 100, height: 40)
    _ = renderer.render(root, proposal: proposal)

    for tick in [1, 2, 25] {
      model.advance(tick)
      // Each synchronous render is a complete frame barrier before the next
      // mutation, isolating observation re-arming from writer/scheduler timing.
      let snapshot = renderer.render(root, proposal: proposal)
      let expected = (0..<8).map { "c\($0) \(tick &+ $0)" }.joined(separator: " ")
      let header = snapshot.rasterSurface.lines.first { $0.contains("c0 ") } ?? "<none>"
      print("[storm-observation] tick=\(tick) model=\(model.counters) frame=\(header)")
      #expect(model.counters == (0..<8).map { tick &+ $0 })
      #expect(header.split(whereSeparator: \.isWhitespace).joined(separator: " ") == expected)
    }
  }

  @Test("storm completion clamps the final visible row for reduced and full drives")
  func finalRowUsesVisibleViewport() throws {
    let initial = try frame(headerTick: 0, rows: [0, 31])
    let reduced = try StormFrameCompletion(
      initialFrame: initial, writerTicks: 25, notchCount: 12, rowCount: 200)
    let full = try StormFrameCompletion(
      initialFrame: initial, writerTicks: 750, notchCount: 180, rowCount: 200)
    #expect(reduced.expectedBottomRow == 43)
    #expect(full.expectedBottomRow == 199)
    #expect(reduced.matches(try frame(headerTick: 25, rows: [12, 43])))
    #expect(full.matches(try frame(headerTick: 750, rows: [168, 199])))
  }

  @Test("storm completion requires exact counters and the last row in one frame")
  func finalFrameRejectsPrefixesAndPartialData() throws {
    let completion = try StormFrameCompletion(
      initialFrame: frame(headerTick: 0, rows: [0, 31]),
      writerTicks: 750, notchCount: 180, rowCount: 200)
    #expect(!completion.matches(try frame(headerTick: 7500, rows: [168, 199])))
    #expect(!completion.matches(try frame(headerTick: 750, rows: [168, 1990])))
    #expect(!completion.matches(try frame(headerTick: 750, rows: [168, 198])))
    #expect(!completion.matches(try frame(headerTick: 750, rows: [199, 200])))
    let correct = try frame(headerTick: 750, rows: [168, 199])
    var wrongCounter = correct
    wrongCounter.text = correct.text.replacingOccurrences(of: "c7 757", with: "c7 758")
    #expect(!completion.matches(wrongCounter))
    var missingCounter = correct
    missingCounter.text = correct.text.replacingOccurrences(of: "c7 757", with: "")
    #expect(!completion.matches(missingCounter))
  }

  @Test("separate historical frames cannot jointly satisfy storm completion")
  func matchingDoesNotCombineFrames() async throws {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 100, rows: 3))
    let completion = try StormFrameCompletion(
      initialFrame: frame(headerTick: 0, rows: [0, 31]),
      writerTicks: 750, notchCount: 180, rowCount: 200)
    _ = try host.present(frame(headerTick: 750, rows: [167, 198]).surface)
    _ = try host.present(frame(headerTick: 749, rows: [168, 199]).surface)
    var now = ContinuousClock().now
    var sleeps = 0
    do {
      _ = try await PerfScenarioRunner.waitForFrameMatching(
        in: host, afterFrame: 0, timeout: .milliseconds(2), hardCap: .milliseconds(3),
        timeoutMarker: completion.description, now: { now },
        sleep: {
          sleeps += 1
          now = now.advanced(by: .milliseconds(1))
          _ = try host.present(
            frame(
              headerTick: sleeps.isMultiple(of: 2) ? 750 : 749,
              rows: sleeps.isMultiple(of: 2) ? [167, 198] : [168, 199]
            ).surface
          )
        },
        matches: completion.matches
      )
      Issue.record("two incomplete frames must not satisfy the endpoint")
    } catch {
      #expect(error as? PerfScenarioError == .markerTimedOut(completion.description))
    }
    #expect(sleeps == 3, "continuous wrong frames must hit the hard cap, not the idle deadline")
  }

  @Test(
    "writer cancellation and drive failure join suspended work before returning",
    arguments: [false, true], [false, true])
  func writerCleanupIsJoined(cancelParent: Bool, throwsSleep: Bool) async throws {
    let model = PerfStormModel()
    let sleeper = ControlledPerfSleeper()
    var writerEntered = sleeper.entered.stream.makeAsyncIterator()
    var writerCancelled = sleeper.cancelled.stream.makeAsyncIterator()
    let driveEntered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let driveExited = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    var driveEntry = driveEntered.stream.makeAsyncIterator()
    var driveExit = driveExited.stream.makeAsyncIterator()
    var resumeDrive: CheckedContinuation<Void, any Error>?
    var returned = false
    let task = Task { @MainActor in
      defer { returned = true }
      try await BenchStormScenario.withOwnedWriter(
        ticks: 2, cadence: .milliseconds(1), advance: { model.advance($0) },
        sleep: { try await sleeper.sleep(for: $0) }
      ) {
        defer { driveExited.continuation.yield(()) }
        try await withCheckedThrowingContinuation { continuation in
          resumeDrive = continuation
          driveEntered.continuation.yield(())
        }
      }
    }
    _ = await driveEntry.next()
    _ = await writerEntered.next()
    if cancelParent {
      task.cancel()
      #expect(sleeper.didObserveCancellation, "cancel the writer before the owner drive resumes")
      resumeDrive?.resume()
    } else {
      resumeDrive?.resume(throwing: WriterTestError.driveFailed)
    }
    _ = await driveExit.next()
    _ = await writerCancelled.next()
    #expect(!returned, "the owner must join its still-suspended writer")
    await sleeper.release(throwsCancellation: throwsSleep)
    do {
      try await task.value
      Issue.record("expected the owner's cancellation or drive error")
    } catch {
      if cancelParent {
        #expect(error is CancellationError)
      } else {
        #expect(error as? WriterTestError == .driveFailed)
      }
    }
    #expect(returned)
    #expect(model.counters == Array(repeating: 0, count: 8))
  }

  @Test("successful writer completion joins every ordered counter update")
  func successfulWriterCompletes() async throws {
    let model = PerfStormModel()
    var ticks: [Int] = []
    try await BenchStormScenario.withOwnedWriter(
      ticks: 2, cadence: .milliseconds(1),
      advance: {
        ticks.append($0)
        model.advance($0)
      },
      sleep: { _ in }
    ) {}
    #expect(ticks == [1, 2])
    #expect(model.counters == Array(2...9))
  }

  private func frame(headerTick: Int, rows: [Int]) throws -> PerfPresentedFrame {
    let host = PerfTerminalHost(size: PerfTerminalSize(columns: 100, rows: rows.count + 1))
    let header = (0..<8).map { "c\($0) \(headerTick &+ $0)" }.joined(separator: " ")
    _ = try host.present(
      RasterSurface(
        size: CellSize(width: 100, height: rows.count + 1),
        lines: [header] + rows.map { "│wrow \($0) meta 0│" }
      ))
    return try #require(host.presentedFrames.last)
  }
}

private enum WriterTestError: Error, Equatable {
  case driveFailed
}
