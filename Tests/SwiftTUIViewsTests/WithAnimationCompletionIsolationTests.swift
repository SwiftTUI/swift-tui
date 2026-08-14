import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// `withAnimation`'s completion closure is main-actor isolated, matching every
/// other authored action closure on this surface (``Button``'s `action`,
/// `.onAppear`, toolbar and key-command handlers) and matching SwiftUI, whose
/// completion is a plain non-`Sendable` closure that inherits main-actor
/// isolation from the `@MainActor` call site.
///
/// This file is the compile-time half of that contract: the completion bodies
/// below write main-actor state and capture a non-`Sendable` value **without a
/// `MainActor.assumeIsolated` hop**. Dropping `@MainActor` from the closure type
/// makes the closure `nonisolated` and this file stops compiling.
@MainActor
struct WithAnimationCompletionIsolationTests {
  @Test("completion writes main-actor state without an isolation hop")
  func completionWritesMainActorStateDirectly() {
    let model = AnimationDemoModel()
    let sink = CapturingCompletionSink()

    AnimationCompletionStorage.withSink(sink) {
      withAnimation(.easeInOut(duration: .milliseconds(100))) {
        model.accentIsHighlighted.toggle()
      } completion: {
        // No `MainActor.assumeIsolated`: the closure is `@MainActor`, so a
        // main-actor-isolated write is a direct call.
        model.completionRuns += 1
      }
    }

    #expect(model.accentIsHighlighted, "the body runs eagerly inside the scope")
    #expect(model.completionRuns == 0, "the completion fires only when the batch drains")

    guard let captured = sink.captured else {
      Issue.record("withAnimation must register its completion with the effective sink")
      return
    }
    captured()

    #expect(model.completionRuns == 1)
  }

  @Test("completion captures non-Sendable state, as a view body's would")
  func completionCapturesNonSendableState() {
    let counter = NonSendableCounter()
    let sink = CapturingCompletionSink()

    AnimationCompletionStorage.withSink(sink) {
      withAnimation(nil) {
      } completion: {
        // A `@State`-backed value or a captured view-local reference is not
        // `Sendable`. A main-actor-isolated closure may capture it because it
        // can only ever run on the main actor.
        counter.value += 1
      }
    }

    sink.captured?()

    #expect(counter.value == 1)
  }

  @Test("a completion registered for the same batch is last-writer-wins")
  func repeatedRegistrationReplacesTheEarlierClosure() {
    let model = AnimationDemoModel()
    let sink = CapturingCompletionSink()
    let batchID = AnimationBatchID(7)

    sink.registerCompletion(batchID: batchID) { model.completionRuns += 10 }
    sink.registerCompletion(batchID: batchID) { model.completionRuns += 1 }
    sink.captured?()

    #expect(model.completionRuns == 1)
  }

  @Test("completion criteria reach the runtime sink")
  func completionCriteriaReachRuntimeSink() {
    let sink = CapturingCompletionSink()

    AnimationCompletionStorage.withSink(sink) {
      withAnimation(
        nil,
        completionCriteria: .removed,
        {}
      ) {}
    }

    #expect(sink.barrier == .removed)
  }
}

/// Stands in for the main-actor view state a completion closure exists to
/// mutate — the gallery's `completionRuns` / accent toggle.
@MainActor
private final class AnimationDemoModel {
  var completionRuns = 0
  var accentIsHighlighted = false
}

/// Deliberately non-`Sendable`: proves the completion may close over view-local
/// reference state, not just over `Sendable` values.
private final class NonSendableCounter {
  var value = 0
}

@MainActor
private final class CapturingCompletionSink: AnimationCompletionSink {
  private(set) var captured: (@MainActor @Sendable () -> Void)?
  private(set) var barrier: AnimationCompletionBarrier?

  func registerCompletion(
    batchID _: AnimationBatchID,
    barrier: AnimationCompletionBarrier = .logicallyComplete,
    closure: @escaping @MainActor @Sendable () -> Void
  ) {
    self.barrier = barrier
    captured = closure
  }
}
