import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Spinner task cancellation", .timeLimit(.minutes(1)))
struct SpinnerCancellationRuntimeTests {
  @Test("a cancelled sleep cannot advance the glyph or invalidate state", arguments: [false, true])
  func cancelledSleepDoesNotAdvance(throwsCancellation: Bool) async throws {
    let harness = SpinnerCancellationHarness()
    let sleeper = ControlledSpinnerSleeper()
    var entries = sleeper.entered.stream.makeAsyncIterator()
    let task = try harness.start(sleeper: sleeper)

    // Acknowledgement is sent only after the exact task has installed its
    // continuation. Cancellation and release are separate, ordered actions.
    _ = await entries.next()
    task.cancel()
    #expect(task.isCancelled)
    sleeper.release(throwsCancellation: throwsCancellation)
    await task.value

    #expect(harness.runner.activeTaskCount == 0)
    #expect(harness.invalidator.requests.isEmpty)
    #expect(harness.renderGlyph() == "A")
  }

  @Test("an uncancelled sleep advances the glyph and invalidates state")
  func completedSleepAdvances() async throws {
    let harness = SpinnerCancellationHarness()
    let sleeper = ControlledSpinnerSleeper()
    var entries = sleeper.entered.stream.makeAsyncIterator()
    let task = try harness.start(sleeper: sleeper)

    _ = await entries.next()
    sleeper.release(throwsCancellation: false)
    // The next installed sleep proves that the preceding tick completed.
    _ = await entries.next()
    #expect(!harness.invalidator.requests.isEmpty)
    #expect(harness.renderGlyph() == "B")

    task.cancel()
    sleeper.release(throwsCancellation: true)
    await task.value
    #expect(harness.runner.activeTaskCount == 0)
  }

  @Test("retiring a suspended spinner releases its graph before cancelled work completes")
  func retiredOwnerIsReleased() async throws {
    var harness: SpinnerCancellationHarness? = SpinnerCancellationHarness()
    let runner = try #require(harness).runner
    let invalidator = try #require(harness).invalidator
    weak let graph = try #require(harness).graph
    let sleeper = ControlledSpinnerSleeper()
    var entries = sleeper.entered.stream.makeAsyncIterator()
    let task = try #require(harness).start(sleeper: sleeper)

    _ = await entries.next()
    task.cancel()
    harness = nil
    #expect(graph == nil)
    sleeper.release(throwsCancellation: true)
    await task.value

    #expect(runner.activeTaskCount == 0)
    #expect(invalidator.requests.isEmpty)
    // The imperative issue queue is process-global, so it cannot provide
    // an isolated diagnostic oracle here. The retained-owner cases above
    // provide the mutation oracle; the guard precedes the iteration read.
  }
}

@MainActor
private final class SpinnerCancellationHarness {
  let runner = TaskRunner()
  let invalidator = SpinnerCancellationInvalidator()
  private let renderer = DefaultRenderer()
  private let registry = LocalTaskRegistry()
  private let identity = testIdentity("SpinnerCancellation")
  var graph: ViewGraph { renderer.viewGraph }

  func start(sleeper: ControlledSpinnerSleeper) throws -> Task<Void, Never> {
    let snapshot = render()
    #expect(snapshot.rasterSurface.lines.first == "A")
    #expect(invalidator.requests.isEmpty)
    let starts = snapshot.commitPlan.lifecycle.filter {
      if case .taskStart = $0.operation { return true }
      return false
    }
    #expect(starts.count == 1)
    let entry = try #require(starts.first)
    let nodeID = try #require(entry.viewNodeID)
    guard case .taskStart(let descriptor) = entry.operation else {
      Issue.record("expected a Spinner task start")
      throw SpinnerCancellationTestError.missingTaskStart
    }
    let registration = try #require(
      registry.registration(for: entry.identity, descriptor: descriptor))
    // TaskRunner inherits this task-local dependency into the registered
    // Spinner operation; no replacement operation stands in for the view.
    return SpinnerTaskClock.$sleep.withValue({ duration in
      try await sleeper.suspendTick(duration: duration)
    }) {
      runner.start(viewNodeID: nodeID, identity: entry.identity, registration: registration)
    }
  }

  func renderGlyph() -> String {
    let snapshot = render()
    return snapshot.rasterSurface.lines.first ?? ""
  }

  private func render() -> RenderSnapshot {
    var context = ResolveContext(
      identity: identity,
      invalidatedIdentities: [identity],
      localTaskRegistry: registry,
      applyEnvironmentValues: true
    )
    context.invalidationProxy = ResolveInvalidationProxy(invalidator: invalidator)
    // Keeping the renderer alive retains the state owner. The old cancelled
    // loop therefore visibly advances to B instead of merely losing its write.
    return renderer.render(
      Spinner().spinnerStyle(GlyphSpinnerStyle(activeFrames: ["A", "B"])),
      context: context,
      proposal: .init(width: 1, height: 1)
    )
  }
}

@MainActor
private final class ControlledSpinnerSleeper {
  let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  private var continuation: CheckedContinuation<Void, any Error>?

  func suspendTick(duration: Duration) async throws {
    #expect(duration > .zero)
    try await withCheckedThrowingContinuation { continuation in
      #expect(self.continuation == nil)
      self.continuation = continuation
      entered.continuation.yield(())
    }
  }

  func release(throwsCancellation: Bool) {
    let suspended = continuation
    continuation = nil
    #expect(suspended != nil)
    if throwsCancellation {
      suspended?.resume(throwing: CancellationError())
    } else {
      suspended?.resume()
    }
  }
}

private final class SpinnerCancellationInvalidator: Invalidating {
  private(set) var requests: [Set<Identity>] = []

  func requestInvalidation(of identities: Set<Identity>) {
    requests.append(identities)
  }
}

private enum SpinnerCancellationTestError: Error {
  case missingTaskStart
}
