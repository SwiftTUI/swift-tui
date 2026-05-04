import Testing

@testable import SwiftTUICore

@MainActor
@Suite("Animation sink storage")
struct AnimationSinkStorageTests {
  @Test("task-local animation registration sink overrides static fallback")
  func taskLocalRegistrationSinkOverridesStaticFallback() async throws {
    let fallback = RecordingAnimationSink()
    let taskLocal = RecordingAnimationSink()

    AnimationRegistrationStorage.currentSink = fallback
    defer {
      AnimationRegistrationStorage.currentSink = nil
    }

    let observedInside = await AnimationRegistrationStorage.withSink(taskLocal) {
      sinkID(AnimationRegistrationStorage.effectiveSink)
    }

    #expect(observedInside == ObjectIdentifier(taskLocal))
    #expect(sinkID(AnimationRegistrationStorage.effectiveSink) == ObjectIdentifier(fallback))
  }

  @Test("task-local animation registration sinks are isolated across concurrent tasks")
  func taskLocalRegistrationSinksAreIsolatedAcrossConcurrentTasks() async throws {
    let first = RecordingAnimationSink()
    let second = RecordingAnimationSink()

    async let firstObserved = AnimationRegistrationStorage.withSink(first) {
      await Task.yield()
      return await MainActor.run {
        sinkID(AnimationRegistrationStorage.effectiveSink)
      }
    }
    async let secondObserved = AnimationRegistrationStorage.withSink(second) {
      await Task.yield()
      return await MainActor.run {
        sinkID(AnimationRegistrationStorage.effectiveSink)
      }
    }

    let (firstID, secondID) = await (firstObserved, secondObserved)

    #expect(firstID == ObjectIdentifier(first))
    #expect(secondID == ObjectIdentifier(second))
  }

  @Test("task-local completion and transition sinks override static fallbacks")
  func taskLocalCompletionAndTransitionSinksOverrideStaticFallbacks() async throws {
    let fallback = RecordingAnimationSink()
    let taskLocal = RecordingAnimationSink()

    AnimationCompletionStorage.currentSink = fallback
    TransitionRegistrationStorage.currentSink = fallback
    defer {
      AnimationCompletionStorage.currentSink = nil
      TransitionRegistrationStorage.currentSink = nil
    }

    let observedCompletion = await AnimationCompletionStorage.withSink(taskLocal) {
      sinkID(AnimationCompletionStorage.effectiveSink)
    }
    let observedTransition = await TransitionRegistrationStorage.withSink(taskLocal) {
      sinkID(TransitionRegistrationStorage.effectiveSink)
    }

    #expect(observedCompletion == ObjectIdentifier(taskLocal))
    #expect(observedTransition == ObjectIdentifier(taskLocal))
    #expect(sinkID(AnimationCompletionStorage.effectiveSink) == ObjectIdentifier(fallback))
    #expect(sinkID(TransitionRegistrationStorage.effectiveSink) == ObjectIdentifier(fallback))
  }
}

@MainActor
private final class RecordingAnimationSink:
  AnimationRegistrationSink, AnimationCompletionSink, TransitionRegistrationSink
{
  func registerAnimationBox(_: AnimationBox, payload _: any Sendable) {}

  func registerCompletion(
    batchID _: AnimationBatchID,
    closure _: @escaping @Sendable () -> Void
  ) {}

  func registerTransition(
    for _: Identity,
    transition _: any Sendable
  ) {}
}

private func sinkID(
  _ sink: (any AnimationRegistrationSink)?
) -> ObjectIdentifier? {
  guard let sink else { return nil }
  return ObjectIdentifier(sink)
}

private func sinkID(
  _ sink: (any AnimationCompletionSink)?
) -> ObjectIdentifier? {
  guard let sink else { return nil }
  return ObjectIdentifier(sink)
}

private func sinkID(
  _ sink: (any TransitionRegistrationSink)?
) -> ObjectIdentifier? {
  guard let sink else { return nil }
  return ObjectIdentifier(sink)
}
