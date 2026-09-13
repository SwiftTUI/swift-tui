/// The playback owner shared by the view and deterministic clock tests.
@MainActor
enum AnimatedImagePlayback {
  static func run(
    _ sequence: AnimatedImageSequence,
    reduceMotion: Bool = false,
    onFrame: (Int) -> Void,
    sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
  ) async {
    guard !Task.isCancelled else { return }
    onFrame(0)
    guard !reduceMotion, sequence.frames.count > 1 else { return }
    let repeatsForever = sequence.loopCount == 0
    var remainingRepeats = sequence.loopCount ?? 0
    var index = 0
    while !Task.isCancelled {
      do { try await sleep(sequence.delayNanoseconds[index]) } catch { return }
      guard !Task.isCancelled else { return }
      if index == sequence.frames.count - 1 {
        guard repeatsForever || remainingRepeats > 0 else { return }
        if !repeatsForever { remainingRepeats -= 1 }
        index = 0
      } else {
        index += 1
      }
      onFrame(index)
    }
  }
}
