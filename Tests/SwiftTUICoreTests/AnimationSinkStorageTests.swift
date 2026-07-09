import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite("Animation sink storage")
struct AnimationSinkStorageTests {
  @Test("the registration sink is task-local only: bound inside withSink, nil outside")
  func registrationSinkIsTaskLocalOnly() async throws {
    // F116: the `static weak var` fallback (assigned only from tests — the
    // last-bound-global anti-pattern) is deleted; outside a binding there is
    // deliberately NO sink.
    let taskLocal = RecordingAnimationSink()

    let observedInside = await AnimationRegistrationStorage.withSink(taskLocal) {
      sinkID(AnimationRegistrationStorage.effectiveSink)
    }

    #expect(observedInside == ObjectIdentifier(taskLocal))
    #expect(AnimationRegistrationStorage.effectiveSink == nil)

    let observedSync = AnimationRegistrationStorage.withSink(taskLocal) {
      sinkID(AnimationRegistrationStorage.effectiveSink)
    }
    #expect(observedSync == ObjectIdentifier(taskLocal))
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

  @Test("completion and transition sinks are task-local only")
  func completionAndTransitionSinksAreTaskLocalOnly() async throws {
    let taskLocal = RecordingAnimationSink()

    let observedCompletion = await AnimationCompletionStorage.withSink(taskLocal) {
      sinkID(AnimationCompletionStorage.effectiveSink)
    }
    let observedTransition = await TransitionRegistrationStorage.withSink(taskLocal) {
      sinkID(TransitionRegistrationStorage.effectiveSink)
    }

    #expect(observedCompletion == ObjectIdentifier(taskLocal))
    #expect(observedTransition == ObjectIdentifier(taskLocal))
    #expect(AnimationCompletionStorage.effectiveSink == nil)
    #expect(TransitionRegistrationStorage.effectiveSink == nil)
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
