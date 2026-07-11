import Observation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressStateIdentityTests {}

// MARK: - Attempt 001: Graph-scoped state seed isolation

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 001 fresh graph ignores a prior graph mutation")
  func stateIdentity001FreshGraphSeedIsolation() throws {
    // Hypothesis: graph-backed writes also update StateBox.seedValue, so mounting the exact
    // same view value in a later graph may inherit the retired graph's final mutation.
    let shared = StateIdentitySharedCounter(label: "001")
    let first = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity001", "first"),
      size: .init(width: 42, height: 8)
    ) {
      shared
    }
    for expected in 1...4 {
      let frame = try first.clickText("001 Increment")
      #expect(frame.contains("001 Count \(expected)"))
    }
    first.shutdown()

    let second = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity001", "second"),
      size: .init(width: 42, height: 8)
    ) {
      shared
    }
    defer { second.shutdown() }

    withKnownIssue(
      "A reused stateful view value seeds a fresh graph from the retired graph's mutation"
    ) {
      #expect(second.frame.contains("001 Count 0"))
    }
  }
}

// MARK: - Attempt 002: Reused StateBox across explicit identity replacement

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 002 explicit id replacement resets a reused view value")
  func stateIdentity002ExplicitIDReplacementResetsReusedValue() throws {
    // Hypothesis: a newly routed entity can be seeded from a StateBox mutated by the entity
    // it replaced when the authored view value itself is deliberately reused.
    let shared = StateIdentitySharedCounter(label: "002")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity002"),
      size: .init(width: 48, height: 9)
    ) {
      StateIdentity002Root(shared: shared)
    }
    defer { harness.shutdown() }

    var replacementFrames: [String] = []
    for generation in 0..<4 {
      _ = try harness.clickText("002 Increment")
      let frame = try harness.clickText("Replace 002")
      #expect(frame.contains("002 Owner \(generation + 1)"))
      replacementFrames.append(frame)
    }

    withKnownIssue("A reused StateBox carries its mutation across explicit-ID replacement") {
      #expect(replacementFrames.allSatisfy { $0.contains("002 Count 0") })
    }
  }

  private struct StateIdentity002Root: View {
    let shared: StateIdentitySharedCounter
    @State private var generation = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("002 Owner \(generation)")
        Button("Replace 002") { generation += 1 }
        shared.id("state-identity-002-\(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: Reinserted reused value starts a fresh lifetime

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 003 removal and reinsertion do not resurrect state")
  func stateIdentity003RemovalReinsertionDoesNotResurrectState() throws {
    // Hypothesis: retained owner values on a long-lived StateBox can outlive graph-node teardown
    // and silently seed the next lifetime when the exact authored value is reinserted.
    let shared = StateIdentitySharedCounter(label: "003")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity003"),
      size: .init(width: 48, height: 9)
    ) {
      StateIdentity003Root(shared: shared)
    }
    defer { harness.shutdown() }

    var reinsertionFrames: [String] = []
    for _ in 0..<4 {
      _ = try harness.clickText("003 Increment")
      var frame = try harness.clickText("Remove 003")
      #expect(!frame.contains("003 Count"))
      frame = try harness.clickText("Insert 003")
      reinsertionFrames.append(frame)
    }

    withKnownIssue("A reused StateBox resurrects its mutation after committed removal") {
      #expect(reinsertionFrames.allSatisfy { $0.contains("003 Count 0") })
    }
  }

  private struct StateIdentity003Root: View {
    let shared: StateIdentitySharedCounter
    @State private var isVisible = true

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(isVisible ? "Remove 003" : "Insert 003") { isVisible.toggle() }
        if isVisible {
          shared
        }
      }
    }
  }
}

// MARK: - Attempt 004: One StateBox mounted under two live owners

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 004 duplicated view value keeps owners isolated")
  func stateIdentity004DuplicatedViewValueKeepsOwnersIsolated() throws {
    // Hypothesis: two mounted copies share one reference-backed StateBox, so alternating
    // imperative dispatch can expose a last-bound-owner bug even when their graph nodes differ.
    let shared = StateIdentity004Counter()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity004"),
      size: .init(width: 54, height: 12)
    ) {
      StateIdentity004Root(shared: shared)
    }
    defer { harness.shutdown() }

    var ownersStayedIsolated = true
    for expected in 1...4 {
      var frame = try harness.clickText("Increment 004")
      ownersStayedIsolated =
        ownersStayedIsolated
        && frame.contains("Left 004 Count \(expected)")
        && frame.contains("Right 004 Count \(expected - 1)")

      frame = try harness.clickText("Increment 004", chooseLast: true)
      ownersStayedIsolated =
        ownersStayedIsolated
        && frame.contains("Left 004 Count \(expected)")
        && frame.contains("Right 004 Count \(expected)")
    }

    withKnownIssue("Two live owners of one stateful view value share StateBox mutations") {
      #expect(ownersStayedIsolated)
    }
  }

  private struct StateIdentity004Root: View {
    let shared: StateIdentity004Counter

    var body: some View {
      VStack(alignment: .leading, spacing: 1) {
        shared
          .environment(\.stress004OwnerLabel, "Left")
          .id("state-identity-004-left")
        shared
          .environment(\.stress004OwnerLabel, "Right")
          .id("state-identity-004-right")
      }
    }
  }

  private struct StateIdentity004Counter: View {
    @Environment(\.stress004OwnerLabel) private var ownerLabel
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("\(ownerLabel) 004 Count \(count)")
        Button("Increment 004") { count += 1 }
      }
    }
  }
}

private enum Stress004OwnerLabelKey: EnvironmentKey {
  static let defaultValue = "Unlabeled"
}

extension EnvironmentValues {
  fileprivate var stress004OwnerLabel: String {
    get { self[Stress004OwnerLabelKey.self] }
    set { self[Stress004OwnerLabelKey.self] = newValue }
  }
}

// MARK: - Attempt 005: Dynamic-member Binding across owner churn

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 005 dynamic member binding follows the live owner")
  func stateIdentity005DynamicMemberBindingFollowsLiveOwner() throws {
    // Hypothesis: a derived Binding closes over the pre-churn graph location and can either
    // write a retired node or overwrite unrelated fields when its owner is re-minted.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity005"),
      size: .init(width: 58, height: 10)
    ) {
      StateIdentity005Root()
    }
    defer { harness.shutdown() }

    for generation in 0..<4 {
      _ = try harness.focus(StateIdentity005Root.fieldIdentity)
      var frame = try harness.paste("x")
      #expect(frame.contains("005 Value \(String(repeating: "x", count: generation + 1))"))
      #expect(frame.contains("005 Marker 41"))

      frame = try harness.clickText("Churn 005")
      #expect(frame.contains("005 Generation \(generation + 1)"))
      #expect(frame.contains("005 Marker 41"))
    }
  }

  private struct StateIdentity005Root: View {
    static let fieldIdentity = testIdentity("StateIdentity005", "field")

    struct Profile {
      var name = ""
    }

    struct Form {
      var profile = Profile()
      var marker = 41
    }

    @State private var form = Form()
    @State private var generation = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("005 Generation \(generation)")
        Text("005 Value \(form.profile.name)")
        Text("005 Marker \(form.marker)")
        Button("Churn 005") { generation += 1 }
        Group {
          TextField("Name 005", text: $form.profile.name)
            .id(Self.fieldIdentity)
        }
        .id(testIdentity("StateIdentity005", "owner", "\(generation)"))
      }
    }
  }
}

// MARK: - Attempt 006: Persistent task writes through a re-minted owner

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 006 persistent task writes the live state owner")
  func stateIdentity006PersistentTaskWritesLiveOwner() async throws {
    // Hypothesis: task churn suppression preserves the original closure while outer identity
    // replacement retires the state node that closure first captured.
    let clock = StateIdentity006Clock()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity006"),
      size: .init(width: 54, height: 10)
    ) {
      StateIdentity006Root(clock: clock)
    }
    defer {
      clock.finish()
      harness.shutdown()
    }

    var taskStayedLive = true
    #expect(harness.activeTaskCount == 1)
    for generation in 0..<4 {
      clock.send(1)
      let processed = await clock.waitUntilProcessedOrStopped(generation + 1)
      let frame = try harness.render()
      taskStayedLive =
        taskStayedLive
        && processed
        && frame.contains("006 Ticks \(generation + 1)")

      let churnedFrame = try harness.clickText("Churn 006")
      #expect(churnedFrame.contains("006 Generation \(generation + 1)"))
      #expect(harness.activeTaskCount == 1)
    }

    withKnownIssue("A persistent task loses its live state owner across outer identity churn") {
      #expect(taskStayedLive)
    }
  }

  private struct StateIdentity006Root: View {
    let clock: StateIdentity006Clock
    @State private var generation = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("006 Generation \(generation)")
        Button("Churn 006") { generation += 1 }
        StateIdentity006Owner(clock: clock)
          .id("state-identity-006-owner-\(generation)")
      }
    }
  }

  private struct StateIdentity006Owner: View {
    let clock: StateIdentity006Clock

    var body: some View {
      StateIdentity006Worker(clock: clock)
        .id(testIdentity("StateIdentity006", "worker"))
    }
  }

  private struct StateIdentity006Worker: View {
    let clock: StateIdentity006Clock
    @State private var ticks = 0

    var body: some View {
      Text("006 Ticks \(ticks)")
        .task(id: "state-identity-006-task") {
          defer { clock.recordTaskStopped() }
          for await delta in clock.stream {
            ticks += delta
            clock.recordProcessedTick()
          }
        }
    }
  }
}

@MainActor
private final class StateIdentity006Clock {
  let stream: AsyncStream<Int>
  private var continuation: AsyncStream<Int>.Continuation!
  private let processedSignal = MainActorConditionSignal()
  private(set) var processedCount = 0
  private var taskStopped = false

  init() {
    var capturedContinuation: AsyncStream<Int>.Continuation?
    stream = AsyncStream { capturedContinuation = $0 }
    continuation = capturedContinuation
  }

  func send(_ value: Int) {
    continuation.yield(value)
  }

  func recordProcessedTick() {
    processedCount += 1
    processedSignal.notify()
  }

  func recordTaskStopped() {
    taskStopped = true
    processedSignal.notify()
  }

  func waitUntilProcessedOrStopped(_ expectedCount: Int) async -> Bool {
    await processedSignal.wait { [self] in
      processedCount >= expectedCount || taskStopped
    }
    return processedCount >= expectedCount
  }

  func finish() {
    continuation.finish()
  }
}

private struct StateIdentitySharedCounter: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) Count \(count)")
      Button("\(label) Increment") { count += 1 }
    }
  }
}
