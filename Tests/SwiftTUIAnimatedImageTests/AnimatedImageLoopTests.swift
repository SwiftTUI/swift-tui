import SwiftTUI
import Testing

@testable import SwiftTUIAnimatedImage

@MainActor
struct AnimatedImageLoopTests {
  private func sequence(loopCount: Int? = 0) -> AnimatedImageSequence {
    AnimatedImageSequence(
      frames: [
        .init(width: 1, height: 1, pixels: [.init(red: 255, green: 0, blue: 0, alpha: 255)]),
        .init(width: 1, height: 1, pixels: [.init(red: 0, green: 0, blue: 255, alpha: 255)]),
      ], frameDelays: [.milliseconds(30), .milliseconds(70)], loopCount: loopCount)
  }

  @Test("GIF counts preserve absence, infinite and finite repeats; explicit overrides win")
  func codecCounts() throws {
    for count: Int? in [nil, 0, 1, 2, 65535] {
      let source = sequence(loopCount: count)
      let decoded = try AnimatedGIF.decode(data: AnimatedGIF.encode(source))
      #expect(decoded.loopCount == count)
      #expect(decoded == source)
      #expect(decoded.hashValue == source.hashValue)
      #expect(try AnimatedGIF.decode(data: AnimatedGIF.encode(source, loopCount: 3)).loopCount == 3)
      #expect(
        try AnimatedGIF.decode(data: AnimatedGIF.encode(source, loopCount: nil)).loopCount == nil)
      let single = AnimatedImageSequence(
        frames: [source.frames[0]], frameDelays: [.milliseconds(30)], loopCount: count)
      #expect(try AnimatedGIF.decode(data: AnimatedGIF.encode(single)).loopCount == count)
    }
    let originalInitializer = AnimatedImageSequence.init(frames:framesPerSecond:)
    #expect(originalInitializer(sequence().frames, 20).loopCount == 0)
    let originalEncoder: (AnimatedImageSequence, Int) throws -> [UInt8] = AnimatedGIF.encode
    #expect(try AnimatedGIF.decode(data: originalEncoder(sequence(), 4)).loopCount == 4)
    var changed = sequence()
    changed.loopCount = 1
    #expect(changed != sequence())
  }

  @Test("finite playback includes the initial play and stops on the final frame")
  func finitePlayback() async {
    for count: Int? in [nil, 1, 2] {
      var frames: [Int] = []
      var delays: [UInt64] = []
      await AnimatedImagePlayback.run(
        sequence(loopCount: count), onFrame: { frames.append($0) },
        sleep: { delays.append($0) })
      let plays = (count ?? 0) + 1
      #expect(frames == Array(repeating: [0, 1], count: plays).flatMap { $0 })
      #expect(delays == Array(repeating: [30_000_000, 70_000_000], count: plays).flatMap { $0 })
      #expect(frames.last == 1)
    }
  }

  @Test("infinite playback advances until its clock is cancelled; reduce motion does not sleep")
  func infiniteAndReduceMotion() async {
    var frames: [Int] = []
    var sleeps = 0
    await AnimatedImagePlayback.run(
      sequence(), onFrame: { frames.append($0) },
      sleep: { _ in
        sleeps += 1
        if sleeps == 7 { throw CancellationError() }
      })
    #expect(frames == [0, 1, 0, 1, 0, 1, 0])
    frames.removeAll()
    await AnimatedImagePlayback.run(
      sequence(), reduceMotion: true, onFrame: { frames.append($0) },
      sleep: { _ in Issue.record("reduce motion cannot schedule a tick") })
    #expect(frames == [0])
  }

  @Test("cancelled source playback cannot advance after a replacement starts")
  func cancellationAndReplacement() async {
    let clock = PlaybackTestClock()
    var requests = clock.requests.makeAsyncIterator()
    var oldFrames: [Int] = []
    let source = sequence()
    let old = Task { @MainActor in
      await AnimatedImagePlayback.run(
        source, onFrame: { oldFrames.append($0) },
        sleep: { _ in await clock.sleep() })
    }
    _ = await requests.next()
    old.cancel()
    var newFrames: [Int] = []
    await AnimatedImagePlayback.run(
      sequence(loopCount: nil), onFrame: { newFrames.append($0) }, sleep: { _ in })
    await clock.advance()  // deliberately ignores cancellation, like a late wakeup
    await old.value
    #expect(oldFrames == [0])
    #expect(newFrames == [0, 1])
  }
}

private actor PlaybackTestClock {
  nonisolated let requests: AsyncStream<Void>
  private let request: AsyncStream<Void>.Continuation
  private var pending: CheckedContinuation<Void, Never>?
  init() {
    let pair = AsyncStream<Void>.makeStream()
    requests = pair.stream
    request = pair.continuation
  }
  func sleep() async {
    await withCheckedContinuation {
      pending = $0
      request.yield()
    }
  }
  func advance() {
    pending?.resume()
    pending = nil
  }
}
