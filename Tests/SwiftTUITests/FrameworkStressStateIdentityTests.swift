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

// MARK: - Attempt 007: Conditional co-reader dependency churn

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 007 conditional co-reader dependencies stay current")
  func stateIdentity007ConditionalCoReaderDependenciesStayCurrent() throws {
    // Hypothesis: removing and re-adding one reader of a shared slot can leave a stale
    // ViewNodeID in the reverse dependency index or fail to attach the replacement reader.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity007"),
      size: .init(width: 56, height: 11)
    ) {
      StateIdentity007Root()
    }
    defer { harness.shutdown() }

    var expected = 0
    for _ in 0..<4 {
      expected += 1
      var frame = try harness.clickText("Increment 007")
      #expect(frame.contains("007 First \(expected)"))
      #expect(frame.contains("007 Second \(expected)"))

      frame = try harness.clickText("Hide Second 007")
      #expect(!frame.contains("007 Second"))
      expected += 1
      frame = try harness.clickText("Increment 007")
      #expect(frame.contains("007 First \(expected)"))
      #expect(!frame.contains("007 Second"))

      frame = try harness.clickText("Show Second 007")
      #expect(frame.contains("007 Second \(expected)"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity007Root: View {
    @State private var value = 0
    @State private var showsSecond = true

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button("Increment 007") { value += 1 }
        Button(showsSecond ? "Hide Second 007" : "Show Second 007") {
          showsSecond.toggle()
        }
        StateIdentity007Reader(label: "First", value: $value)
        if showsSecond {
          StateIdentity007Reader(label: "Second", value: $value)
        }
      }
    }
  }

  private struct StateIdentity007Reader: View {
    let label: String
    @Binding var value: Int

    var body: some View {
      Text("007 \(label) \(value)")
    }
  }
}

// MARK: - Attempt 008: onChange baseline ownership under ordinal shifts

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 008 surviving onChange keeps its own baseline")
  func stateIdentity008SurvivingOnChangeKeepsOwnBaseline() throws {
    // Hypothesis: when an earlier modifier disappears, the surviving onChange can claim its
    // ordinal and read the departed modifier's identity-keyed previous value.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity008"),
      size: .init(width: 72, height: 11)
    ) {
      StateIdentity008Root()
    }
    defer { harness.shutdown() }

    var expectedChanges = 0
    var expectedValue = 100
    for _ in 0..<4 {
      expectedChanges += 1
      expectedValue += 1
      var frame = try harness.clickText("Bump B 008")
      #expect(frame.contains("008 B changes \(expectedChanges)"))
      #expect(frame.contains("008 B old \(expectedValue - 1) new \(expectedValue)"))

      frame = try harness.clickText("Remove First 008")
      #expect(frame.contains("008 First absent"))

      expectedChanges += 1
      expectedValue += 1
      frame = try harness.clickText("Bump B 008")
      #expect(frame.contains("008 B changes \(expectedChanges)"))
      #expect(frame.contains("008 B old \(expectedValue - 1) new \(expectedValue)"))

      frame = try harness.clickText("Add First 008")
      #expect(frame.contains("008 First present"))
    }
  }

  private struct StateIdentity008Root: View {
    @State private var first = 0
    @State private var second = 100
    @State private var includesFirst = true
    @State private var secondChangeCount = 0
    @State private var lastSecondOld = -1
    @State private var lastSecondNew = -1

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text(includesFirst ? "008 First present" : "008 First absent")
        Text("008 B changes \(secondChangeCount)")
        Text("008 B old \(lastSecondOld) new \(lastSecondNew)")
        Button("Bump B 008") { second += 1 }
        Button(includesFirst ? "Remove First 008" : "Add First 008") {
          includesFirst.toggle()
        }
        if includesFirst {
          Text("008 observer")
            .onChange(of: first) { _, _ in }
            .onChange(of: second) { oldValue, newValue in
              secondChangeCount += 1
              lastSecondOld = oldValue
              lastSecondNew = newValue
            }
            .id("state-identity-008-observer")
        } else {
          Text("008 observer")
            .onChange(of: second) { oldValue, newValue in
              secondChangeCount += 1
              lastSecondOld = oldValue
              lastSecondNew = newValue
            }
            .id("state-identity-008-observer")
        }
      }
    }
  }
}

// MARK: - Attempt 009: Default-focus ordinals under conditional modifier churn

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 009 default focus follows the arriving modifier shape")
  func stateIdentity009DefaultFocusFollowsArrivingModifierShape() throws {
    // Hypothesis: removing the first of two default-focus modifiers shifts ordinal-backed
    // seed state and can leave a fresh owner with no usable default candidate.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity009"),
      size: .init(width: 58, height: 10)
    ) {
      StateIdentity009Root()
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("009 Focus first"))
    var defaultsFollowedModifierShape = true
    for generation in 1...4 {
      let frame = try harness.clickText("Churn 009")
      #expect(frame.contains("009 Generation \(generation)"))
      let field = generation.isMultiple(of: 2) ? "first" : "second"
      defaultsFollowedModifierShape =
        defaultsFollowedModifierShape
        && frame.contains("009 Focus \(field)")
      #expect(harness.defaultFocusRegistrationCount <= 2)
    }

    withKnownIssue("Default-focus ordinal churn clears the requested replacement focus") {
      #expect(defaultsFollowedModifierShape)
    }
  }

  private enum StateIdentity009Field: Hashable {
    case first
    case second
  }

  private struct StateIdentity009Root: View {
    @State private var generation = 0
    @FocusState private var focusedField: StateIdentity009Field?

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("009 Generation \(generation)")
        Text("009 Focus \(focusLabel)")
        Button("Churn 009") { generation += 1 }
        StateIdentity009Controls(
          generation: generation,
          focusedField: $focusedField,
          includesFirstDefault: generation.isMultiple(of: 2)
        )
        .id("state-identity-009-owner-\(generation)")
      }
    }

    private var focusLabel: String {
      switch focusedField {
      case .first: "first"
      case .second: "second"
      case nil: "none"
      }
    }

  }

  private struct StateIdentity009Controls: View {
    let generation: Int
    let focusedField: FocusState<StateIdentity009Field?>.Binding
    let includesFirstDefault: Bool

    var body: some View {
      if includesFirstDefault {
        controls
          .defaultFocus(focusedField, .second)
          .defaultFocus(focusedField, .first)
      } else {
        controls
          .defaultFocus(focusedField, .second)
      }
    }

    private var controls: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button("First 009") {}
          .id(testIdentity("StateIdentity009", "first", "\(generation)"))
          .focused(focusedField, equals: .first)
        Button("Second 009") {}
          .id(testIdentity("StateIdentity009", "second", "\(generation)"))
          .focused(focusedField, equals: .second)
      }
    }
  }
}

// MARK: - Attempt 010: Navigation activation state under modifier ordinal shifts

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 010 surviving destination keeps activation state")
  func stateIdentity010SurvivingDestinationKeepsActivationState() throws {
    // Hypothesis: removing an earlier navigationDestination shifts the surviving modifier's
    // ordinal and lets it inherit a different destination's activation record.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity010"),
      size: .init(width: 62, height: 11)
    ) {
      StateIdentity010Root()
    }
    defer { harness.shutdown() }

    for _ in 0..<4 {
      var frame = try harness.clickText("Open Second 010")
      #expect(frame.contains("Second Destination 010"))
      #expect(!frame.contains("First Destination 010"))
      frame = try harness.clickText("Back Second 010")
      #expect(frame.contains("010 Root"))

      frame = try harness.clickText("Remove First Destination 010")
      #expect(frame.contains("010 First modifier absent"))
      frame = try harness.clickText("Open Second 010")
      #expect(frame.contains("Second Destination 010"))
      #expect(!frame.contains("First Destination 010"))
      frame = try harness.clickText("Back Second 010")
      #expect(frame.contains("010 Root"))

      frame = try harness.clickText("Add First Destination 010")
      #expect(frame.contains("010 First modifier present"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity010Root: View {
    @State private var includesFirst = true
    @State private var presentsFirst = false
    @State private var presentsSecond = false

    var body: some View {
      NavigationStack(id: "state-identity-010-stack") {
        if includesFirst {
          rootContent
            .navigationDestination(isPresented: $presentsFirst) {
              Text("First Destination 010")
            }
            .navigationDestination(isPresented: $presentsSecond) {
              secondDestination
            }
        } else {
          rootContent
            .navigationDestination(isPresented: $presentsSecond) {
              secondDestination
            }
        }
      }
    }

    private var rootContent: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("010 Root")
        Text(includesFirst ? "010 First modifier present" : "010 First modifier absent")
        Button("Open Second 010") { presentsSecond = true }
        Button(includesFirst ? "Remove First Destination 010" : "Add First Destination 010") {
          includesFirst.toggle()
        }
      }
    }

    private var secondDestination: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Second Destination 010")
        Button("Back Second 010") { presentsSecond = false }
      }
    }
  }
}

// MARK: - Attempt 011: Non-zero-based RandomAccessCollection identity

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 011 array slice rows retain identity")
  func stateIdentity011ArraySliceRowsRetainIdentity() throws {
    // Hypothesis: ForEach's zero-based element offset can be confused with an ArraySlice's
    // non-zero collection index when routes are rebuilt across window movement.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity011"),
      size: .init(width: 56, height: 12)
    ) {
      StateIdentity011Root()
    }
    defer { harness.shutdown() }

    for expected in 1...4 {
      var frame = try harness.clickText("Row 3 Increment 011")
      #expect(frame.contains("Row 3 Count \(expected)"))
      frame = try harness.clickText("Advance Slice 011")
      #expect(frame.contains("011 Slice 3...5"))
      #expect(frame.contains("Row 3 Count \(expected)"))
      frame = try harness.clickText("Retreat Slice 011")
      #expect(frame.contains("011 Slice 2...4"))
      #expect(frame.contains("Row 3 Count \(expected)"))
    }
  }

  private struct StateIdentity011Root: View {
    private let items = Array(0..<8)
    @State private var lowerBound = 2

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("011 Slice \(lowerBound)...\(lowerBound + 2)")
        Button("Advance Slice 011") { lowerBound = 3 }
        Button("Retreat Slice 011") { lowerBound = 2 }
        ForEach(items[lowerBound..<(lowerBound + 3)], id: \.self) { value in
          StateIdentity011Row(value: value)
        }
      }
    }
  }

  private struct StateIdentity011Row: View {
    let value: Int
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Row \(value) Count \(count)")
        Button("Row \(value) Increment 011") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 012: Nested entity scope follows an outer reorder

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 012 nested row state follows outer entity reorder")
  func stateIdentity012NestedRowStateFollowsOuterReorder() throws {
    // Hypothesis: inner ForEach entity scope includes the outer row's positional structural
    // path, so moving the outer entity can reset or misroute otherwise-stable inner state.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity012"),
      size: .init(width: 66, height: 14)
    ) {
      StateIdentity012Root()
    }
    defer { harness.shutdown() }

    var stateFollowedOuterEntity = true
    for expected in 1...4 {
      var frame = try harness.clickText("Outer 1 Inner 10 Increment 012")
      stateFollowedOuterEntity =
        stateFollowedOuterEntity
        && frame.contains("Outer 1 Inner 10 Count \(expected)")
      frame = try harness.clickText("Reverse Outer 012")
      stateFollowedOuterEntity =
        stateFollowedOuterEntity
        && frame.contains("Outer 1 Inner 10 Count \(expected)")
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }

    withKnownIssue("Nested ForEach row actions lose their live state owner after outer reorder") {
      #expect(stateFollowedOuterEntity)
    }
  }

  private struct StateIdentity012Root: View {
    @State private var isReversed = false

    private var outerValues: [Int] {
      isReversed ? [2, 1] : [1, 2]
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button("Reverse Outer 012") { isReversed.toggle() }
        ForEach(outerValues, id: \.self) { outer in
          VStack(alignment: .leading, spacing: 0) {
            Text("Outer \(outer)")
            ForEach([10, 11], id: \.self) { inner in
              StateIdentity012InnerRow(outer: outer, inner: inner)
            }
          }
        }
      }
    }
  }

  private struct StateIdentity012InnerRow: View {
    let outer: Int
    let inner: Int
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Outer \(outer) Inner \(inner) Count \(count)")
        Button("Outer \(outer) Inner \(inner) Increment 012") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 013: Empty ForEach element teardown anchoring

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 013 empty foreach elements leave no graph orphans")
  func stateIdentity013EmptyForEachElementsLeaveNoOrphans() throws {
    // Hypothesis: ForEach drops an EmptyView element with a bare continue while its neighboring
    // Group path explicitly anchors the minted element node to the hosted-detached ledger.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity013"),
      size: .init(width: 58, height: 12)
    ) {
      StateIdentity013Root()
    }
    defer { harness.shutdown() }

    for _ in 0..<4 {
      var frame = try harness.clickText("Hide Row Content 013")
      #expect(!frame.contains("Visible Row 013"))
      frame = try harness.clickText("Remove Collection 013")
      #expect(!frame.contains("Visible Row 013"))
      frame = try harness.clickText("Insert Collection 013")
      #expect(!frame.contains("Visible Row 013"))
      frame = try harness.clickText("Show Row Content 013")
      #expect(frame.contains("Visible Row 013 1"))
      frame = try harness.clickText("Remove Collection 013")
      #expect(!frame.contains("Visible Row 013"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
      frame = try harness.clickText("Insert Collection 013")
      #expect(frame.contains("Visible Row 013 1"))
    }
  }

  private struct StateIdentity013Root: View {
    @State private var showsContent = true
    @State private var showsCollection = true

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(showsContent ? "Hide Row Content 013" : "Show Row Content 013") {
          showsContent.toggle()
        }
        Button(showsCollection ? "Remove Collection 013" : "Insert Collection 013") {
          showsCollection.toggle()
        }
        if showsCollection {
          ForEach([1, 2, 3], id: \.self) { value in
            StateIdentity013Row(value: value, isVisible: showsContent)
          }
        }
      }
    }
  }

  private struct StateIdentity013Row: View {
    let value: Int
    let isVisible: Bool

    @ViewBuilder
    var body: some View {
      if isVisible {
        Text("Visible Row 013 \(value)")
      }
    }
  }
}

// MARK: - Attempt 014: Spliced Group row state across reorder

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 014 spliced group row state follows entity")
  func stateIdentity014SplicedGroupRowStateFollowsEntity() throws {
    // Hypothesis: a multi-element ForEach row is spliced out of the committed tree, leaving
    // its stateful descendants dependent on entity stamping plus a detached host anchor.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity014"),
      size: .init(width: 60, height: 14)
    ) {
      StateIdentity014Root()
    }
    defer { harness.shutdown() }

    for expected in 1...4 {
      var frame = try harness.clickText("Increment Group Row 1 014")
      #expect(frame.contains("Group Row 1 Count \(expected)"))
      frame = try harness.clickText("Reverse Group Rows 014")
      #expect(frame.contains("Group Row 1 Count \(expected)"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity014Root: View {
    @State private var isReversed = false

    private var values: [Int] {
      isReversed ? [3, 2, 1] : [1, 2, 3]
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button("Reverse Group Rows 014") { isReversed.toggle() }
        ForEach(values, id: \.self) { value in
          Text("Group Row Label \(value)")
          StateIdentity014Counter(value: value)
        }
      }
    }
  }

  private struct StateIdentity014Counter: View {
    let value: Int
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Group Row \(value) Count \(count)")
        Button("Increment Group Row \(value) 014") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 015: ForEach row cardinality crosses the Group boundary

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 015 row cardinality churn preserves stable child state")
  func stateIdentity015RowCardinalityChurnPreservesStableChildState() throws {
    // Hypothesis: changing a row from one resolved child to a spliced Group changes which node
    // absorbs its entity route and can reset or detach the always-present stateful child.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity015"),
      size: .init(width: 58, height: 11)
    ) {
      StateIdentity015Root()
    }
    defer { harness.shutdown() }

    for expected in 1...4 {
      var frame = try harness.clickText("Increment Stable Row 015")
      #expect(frame.contains("015 Stable Count \(expected)"))
      frame = try harness.clickText("Expand Row 015")
      #expect(frame.contains("015 Optional Child"))
      #expect(frame.contains("015 Stable Count \(expected)"))
      frame = try harness.clickText("Collapse Row 015")
      #expect(!frame.contains("015 Optional Child"))
      #expect(frame.contains("015 Stable Count \(expected)"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity015Root: View {
    @State private var isExpanded = false

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(isExpanded ? "Collapse Row 015" : "Expand Row 015") {
          isExpanded.toggle()
        }
        ForEach([1], id: \.self) { _ in
          StateIdentity015StableCounter()
          if isExpanded {
            Text("015 Optional Child")
          }
        }
      }
    }
  }

  private struct StateIdentity015StableCounter: View {
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("015 Stable Count \(count)")
        Button("Increment Stable Row 015") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 016: Same-ID payload changes refresh action captures

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 016 same id row action captures current payload")
  func stateIdentity016SameIDRowActionCapturesCurrentPayload() throws {
    // Hypothesis: entity routing preserves the row node while retained registration restore
    // can keep the first action closure after non-identity item data changes.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity016"),
      size: .init(width: 58, height: 10)
    ) {
      StateIdentity016Root()
    }
    defer { harness.shutdown() }

    var expectedTotal = 0
    for generation in 0..<4 {
      expectedTotal += generation + 1
      var frame = try harness.clickText("Apply Amount 016")
      #expect(frame.contains("016 Total \(expectedTotal)"))
      frame = try harness.clickText("Advance Payload 016")
      #expect(frame.contains("016 Amount \(generation + 2)"))
      #expect(harness.actionRegistrationCount <= 2)
    }
  }

  private struct StateIdentity016Item: Identifiable {
    let id: Int
    let amount: Int
  }

  private struct StateIdentity016Root: View {
    @State private var generation = 0
    @State private var total = 0

    private var items: [StateIdentity016Item] {
      [.init(id: 1, amount: generation + 1)]
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("016 Total \(total)")
        Button("Advance Payload 016") { generation += 1 }
        ForEach(items) { item in
          VStack(alignment: .leading, spacing: 0) {
            Text("016 Amount \(item.amount)")
            Button("Apply Amount 016") { total += item.amount }
          }
        }
      }
    }
  }
}

// MARK: - Attempt 017: In-place entity ID mutation

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 017 changed row id resets only that lifetime")
  func stateIdentity017ChangedRowIDResetsOnlyThatLifetime() throws {
    // Hypothesis: replacing an entity in an occupied structural slot can either adopt the
    // departing state or over-remove the stable neighboring entity during displacement.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity017"),
      size: .init(width: 64, height: 12)
    ) {
      StateIdentity017Root()
    }
    defer { harness.shutdown() }

    var changingID = 1
    for stableCount in 1...4 {
      var frame = try harness.clickText("Increment Row \(changingID) 017")
      #expect(frame.contains("017 Row \(changingID) Count 1"))
      frame = try harness.clickText("Increment Row 100 017")
      #expect(frame.contains("017 Row 100 Count \(stableCount)"))

      frame = try harness.clickText("Mutate Row ID 017")
      changingID += 1
      #expect(frame.contains("017 Row \(changingID) Count 0"))
      #expect(frame.contains("017 Row 100 Count \(stableCount)"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity017Root: View {
    @State private var changingID = 1

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button("Mutate Row ID 017") { changingID += 1 }
        ForEach([changingID, 100], id: \.self) { value in
          StateIdentity017Row(value: value)
        }
      }
    }
  }

  private struct StateIdentity017Row: View {
    let value: Int
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("017 Row \(value) Count \(count)")
        Button("Increment Row \(value) 017") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 018: Entity route release across a committed absence

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 018 reinserted entity starts a fresh row lifetime")
  func stateIdentity018ReinsertedEntityStartsFreshLifetime() throws {
    // Hypothesis: an inactive entity route or deferred-removal node can survive an empty frame
    // and resurrect row-local state when the same data ID later returns.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity018"),
      size: .init(width: 62, height: 12)
    ) {
      StateIdentity018Root()
    }
    defer { harness.shutdown() }

    for stableCount in 1...4 {
      var frame = try harness.clickText("Increment Row 1 018")
      #expect(frame.contains("018 Row 1 Count 1"))
      frame = try harness.clickText("Increment Row 2 018")
      #expect(frame.contains("018 Row 2 Count \(stableCount)"))

      frame = try harness.clickText("Remove Row 1 018")
      #expect(!frame.contains("018 Row 1 Count"))
      frame = try harness.clickText("Insert Row 1 018")
      #expect(frame.contains("018 Row 1 Count 0"))
      #expect(frame.contains("018 Row 2 Count \(stableCount)"))
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }
  }

  private struct StateIdentity018Root: View {
    @State private var includesFirst = true

    private var values: [Int] {
      includesFirst ? [1, 2] : [2]
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(includesFirst ? "Remove Row 1 018" : "Insert Row 1 018") {
          includesFirst.toggle()
        }
        ForEach(values, id: \.self) { value in
          StateIdentity018Row(value: value)
        }
      }
    }
  }

  private struct StateIdentity018Row: View {
    let value: Int
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("018 Row \(value) Count \(count)")
        Button("Increment Row \(value) 018") { count += 1 }
      }
    }
  }
}

// MARK: - Attempt 019: Duplicate entity occurrence cardinality

extension FrameworkStressStateIdentityTests {
  @Test("stress state identity 019 duplicate occurrences keep independent lifetimes")
  func stateIdentity019DuplicateOccurrencesKeepIndependentLifetimes() throws {
    // Hypothesis: duplicate occurrences share the runtime identity index, so removing and
    // recreating occurrence one can alias occurrence zero's state or keep its retired node.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StateIdentity019"),
      size: .init(width: 64, height: 12)
    ) {
      StateIdentity019Root()
    }
    defer { harness.shutdown() }

    var occurrencesStayedIndependent = true
    for primaryCount in 1...4 {
      var frame = try harness.clickText("Increment Primary 019")
      occurrencesStayedIndependent =
        occurrencesStayedIndependent
        && frame.contains("019 Primary Count \(primaryCount)")
        && frame.contains("019 Secondary Count 0")
      frame = try harness.clickText("Increment Secondary 019")
      occurrencesStayedIndependent =
        occurrencesStayedIndependent
        && frame.contains("019 Primary Count \(primaryCount)")
        && frame.contains("019 Secondary Count 1")

      frame = try harness.clickText("Remove Secondary 019")
      #expect(!frame.contains("019 Secondary Count"))
      occurrencesStayedIndependent =
        occurrencesStayedIndependent
        && frame.contains("019 Primary Count \(primaryCount)")
      frame = try harness.clickText("Insert Secondary 019")
      occurrencesStayedIndependent =
        occurrencesStayedIndependent
        && frame.contains("019 Secondary Count 0")
        && frame.contains("019 Primary Count \(primaryCount)")
      #expect(harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    }

    withKnownIssue("Duplicate-ID row actions dispatch into the wrong occurrence owner") {
      #expect(occurrencesStayedIndependent)
    }
  }

  private struct StateIdentity019Item: Identifiable {
    let id = 7
    let label: String
  }

  private struct StateIdentity019Root: View {
    @State private var includesSecondary = true

    private var items: [StateIdentity019Item] {
      var result = [StateIdentity019Item(label: "Primary")]
      if includesSecondary {
        result.append(.init(label: "Secondary"))
      }
      return result
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Button(includesSecondary ? "Remove Secondary 019" : "Insert Secondary 019") {
          includesSecondary.toggle()
        }
        ForEach(items) { item in
          StateIdentity019Row(label: item.label)
        }
      }
    }
  }

  private struct StateIdentity019Row: View {
    let label: String
    @State private var count = 0

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("019 \(label) Count \(count)")
        Button("Increment \(label) 019") { count += 1 }
      }
    }
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
