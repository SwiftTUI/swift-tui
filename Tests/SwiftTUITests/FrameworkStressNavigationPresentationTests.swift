import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI navigation and presentation stress behavior", .serialized)
struct FrameworkStressNavigationPresentationTests {}

// MARK: - Attempt 001: live Boolean destination payload refresh

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 001 Boolean destination refreshes live payload")
  func stress001BooleanDestinationRefreshesLivePayload() throws {
    // Hypothesis: a Boolean destination's stable activation can retain its
    // opening payload when source state changes, or remint its local state.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP001", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      StressNP001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Boolean Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Destination Local")
      let frame = try harness.clickText("Refresh Boolean Payload")
      #expect(frame.contains("Boolean payload \(generation) local \(generation)"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressNP001Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    NavigationStack(id: "stress-np-001-stack") {
      Button("Open Boolean Destination") { isPresented = true }
        .navigationDestination(isPresented: $isPresented) {
          StressNP001Destination(
            generation: generation,
            generationBinding: $generation
          )
        }
    }
  }
}

@MainActor
private struct StressNP001Destination: View {
  let generation: Int
  @Binding var generationBinding: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Boolean payload \(generation) local \(local)")
      Button("Increment Destination Local") { local += 1 }
      Button("Refresh Boolean Payload") { generationBinding += 1 }
    }
  }
}

// MARK: - Attempt 002: item destination identity replacement

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 002 item ID replacement starts a fresh lifetime")
  func stress002ItemIDReplacementStartsFreshLifetime() throws {
    // Hypothesis: changing an active item's ID can keep the preceding
    // activation's state slots or render the new payload under the old route.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP002", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressNP002Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Item A")
    for version in 1...8 {
      _ = try harness.clickText("Increment Item Local")
      let frame = try harness.clickText("Replace Item ID")
      let expectedID = version.isMultiple(of: 2) ? "a" : "b"
      #expect(frame.contains("item \(expectedID) version \(version) local 0"))
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

private struct StressNP002Item: Identifiable, Sendable {
  var id: String
  var version: Int
}

@MainActor
private struct StressNP002Fixture: View {
  @State private var item: StressNP002Item?

  var body: some View {
    NavigationStack(id: "stress-np-002-stack") {
      Button("Open Item A") {
        item = StressNP002Item(id: "a", version: 0)
      }
      .navigationDestination(item: $item) { item in
        StressNP002Destination(item: item, activeItem: $item)
      }
    }
  }
}

@MainActor
private struct StressNP002Destination: View {
  let item: StressNP002Item
  @Binding var activeItem: StressNP002Item?
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("item \(item.id) version \(item.version) local \(local)")
      Button("Increment Item Local") { local += 1 }
      Button("Replace Item ID") {
        activeItem = StressNP002Item(
          id: item.id == "a" ? "b" : "a",
          version: item.version + 1
        )
      }
    }
  }
}

// MARK: - Attempt 003: same-ID item destination reactivation

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 003 reactivated item starts fresh state")
  func stress003ReactivatedItemStartsFreshState() throws {
    // Hypothesis: clearing and restoring an item with the same ID can reuse a
    // departed activation's local state or stale payload generation.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP003", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      StressNP003Fixture()
    }
    defer { harness.shutdown() }

    for version in 0..<8 {
      var frame = try harness.clickText("Open Stable Item")
      #expect(frame.contains("stable item version \(version) local 0"))
      frame = try harness.clickText("Increment Stable Item Local")
      #expect(frame.contains("stable item version \(version) local 1"))
      frame = try harness.clickText("Close Stable Item")
      #expect(frame.contains("Open Stable Item"))
      #expect(!frame.contains("stable item version"))
      #expect(harness.actionRegistrationCount <= 1)
    }
  }
}

private struct StressNP003Item: Identifiable, Sendable {
  let id = "stable"
  var version: Int
}

@MainActor
private struct StressNP003Fixture: View {
  @State private var item: StressNP003Item?
  @State private var nextVersion = 0

  var body: some View {
    NavigationStack(id: "stress-np-003-stack") {
      Button("Open Stable Item") {
        item = StressNP003Item(version: nextVersion)
        nextVersion += 1
      }
      .navigationDestination(item: $item) { item in
        StressNP003Destination(item: item, activeItem: $item)
      }
    }
  }
}

@MainActor
private struct StressNP003Destination: View {
  let item: StressNP003Item
  @Binding var activeItem: StressNP003Item?
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("stable item version \(item.version) local \(local)")
      Button("Increment Stable Item Local") { local += 1 }
      Button("Close Stable Item") { activeItem = nil }
    }
  }
}

// MARK: - Attempt 004: active source identity remint

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 004 reminted source replaces active destination")
  func stress004RemintedSourceReplacesActiveDestination() throws {
    // Hypothesis: reminting the declaration source while its external binding
    // stays true can strand the old destination or reuse its state lifetime.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP004", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressNP004Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Remintable Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Reminted Local")
      let frame = try harness.clickText("Remint Destination Source")
      #expect(frame.contains("reminted generation \(generation) local 0"))
      #expect(
        frame.components(separatedBy: "reminted generation").count - 1 == 1
      )
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressNP004Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    NavigationStack(id: "stress-np-004-stack") {
      Button("Open Remintable Destination") { isPresented = true }
        .id("stress-np-004-source-\(generation)")
        .navigationDestination(isPresented: $isPresented) {
          StressNP004Destination(
            generation: generation,
            sourceGeneration: $generation
          )
        }
    }
  }
}

@MainActor
private struct StressNP004Destination: View {
  let generation: Int
  @Binding var sourceGeneration: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("reminted generation \(generation) local \(local)")
      Button("Increment Reminted Local") { local += 1 }
      Button("Remint Destination Source") { sourceGeneration += 1 }
    }
  }
}

// MARK: - Attempt 005: active NavigationStack scope identity churn

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 005 stack scope ID churn preserves destination pop")
  func stress005StackScopeIDChurnPreservesDestinationPop() throws {
    // Hypothesis: changing a NavigationStack's command-scope ID while its
    // destination is active can reset the structural lifetime or strand pop.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP005", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressNP005Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Stack Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Stack Local")
      let frame = try harness.clickText("Remint Navigation Stack")
      #expect(frame.contains("stack generation \(generation) local \(generation)"))
      #expect(harness.actionRegistrationCount <= 3)
    }

    let frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("root stack generation 8"))
    #expect(!frame.contains("stack generation 8 local"))
  }
}

@MainActor
private struct StressNP005Fixture: View {
  @State private var isPresented = false
  @State private var generation = 0

  var body: some View {
    NavigationStack(id: "stress-np-005-stack-\(generation)") {
      VStack(alignment: .leading, spacing: 0) {
        Text("root stack generation \(generation)")
        Button("Open Stack Destination") { isPresented = true }
      }
      .navigationDestination(isPresented: $isPresented) {
        StressNP005Destination(
          generation: generation,
          stackGeneration: $generation
        )
      }
    }
  }
}

@MainActor
private struct StressNP005Destination: View {
  let generation: Int
  @Binding var stackGeneration: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("stack generation \(generation) local \(local)")
      Button("Increment Stack Local") { local += 1 }
      Button("Remint Navigation Stack") { stackGeneration += 1 }
    }
  }
}

// MARK: - Attempt 006: active destination source reorder

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 006 reordered source preserves active destination")
  func stress006ReorderedSourcePreservesActiveDestination() throws {
    // Hypothesis: moving a stable declaration source across a sibling can
    // drop its active instance or recreate the destination's local state.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP006", "Root"),
      size: .init(width: 50, height: 10)
    ) {
      StressNP006Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Reorder Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Reorder Local")
      let frame = try harness.clickText("Reorder Destination Source")
      withKnownIssue("Reordered destination source splits local state by structural slot") {
        #expect(
          frame.contains(
            "source reversed \(!generation.isMultiple(of: 2)) local \(generation)"
          )
        )
      }
      #expect(harness.actionRegistrationCount <= 3)
    }
  }
}

@MainActor
private struct StressNP006Fixture: View {
  @State private var isPresented = false
  @State private var reversed = false

  var body: some View {
    NavigationStack(id: "stress-np-006-stack") {
      VStack(alignment: .leading, spacing: 0) {
        if reversed {
          peer
          source
        } else {
          source
          peer
        }
      }
    }
  }

  private var source: some View {
    Button("Open Reorder Destination") { isPresented = true }
      .id("stress-np-006-source")
      .navigationDestination(isPresented: $isPresented) {
        StressNP006Destination(reversed: $reversed)
      }
  }

  private var peer: some View {
    Text("stable reorder peer")
      .id("stress-np-006-peer")
  }
}

@MainActor
private struct StressNP006Destination: View {
  @Binding var reversed: Bool
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("source reversed \(reversed) local \(local)")
      Button("Increment Reorder Local") { local += 1 }
      Button("Reorder Destination Source") { reversed.toggle() }
    }
  }
}

// MARK: - Attempt 007: active source cardinality churn

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 007 source cardinality preserves active route")
  func stress007SourceCardinalityPreservesActiveRoute() throws {
    // Hypothesis: changing a destination source from one resolved child to a
    // grouped pair can shift its declaration identity or activation slot.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP007", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      StressNP007Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Cardinality Destination")
    for generation in 1...8 {
      _ = try harness.clickText("Increment Cardinality Local")
      let frame = try harness.clickText("Toggle Source Cardinality")
      withKnownIssue("Source cardinality churn splits destination state lifetimes") {
        #expect(
          frame.contains(
            "source expanded \(!generation.isMultiple(of: 2)) local \(generation)"
          )
        )
      }
      // Identity-replacement teardown (removalPlan) tears down the departed
      // destination surface, but a cardinality-churn residual in the
      // hosted-detached ledger still evicts a frame late under parallel-gate
      // load, so the registration count lands at 3 or 4 depending on timing.
      // Intermittent until the ledger sweep (RC-3) lands.
      withKnownIssue(
        "Source cardinality churn retains departed action registrations",
        isIntermittent: true
      ) {
        #expect(harness.actionRegistrationCount <= 3)
      }
    }
  }
}

@MainActor
private struct StressNP007Fixture: View {
  @State private var isPresented = false
  @State private var expanded = false

  var body: some View {
    NavigationStack(id: "stress-np-007-stack") {
      Group {
        if expanded {
          Button("Open Cardinality Destination") { isPresented = true }
          Text("cardinality peer")
        } else {
          Button("Open Cardinality Destination") { isPresented = true }
        }
      }
      .id("stress-np-007-source")
      .navigationDestination(isPresented: $isPresented) {
        StressNP007Destination(expanded: $expanded)
      }
    }
  }
}

@MainActor
private struct StressNP007Destination: View {
  @Binding var expanded: Bool
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("source expanded \(expanded) local \(local)")
      Button("Increment Cardinality Local") { local += 1 }
      Button("Toggle Source Cardinality") { expanded.toggle() }
    }
  }
}

// MARK: - Attempt 008: active destination binding retarget

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 008 pop writes retargeted Boolean binding")
  func stress008PopWritesRetargetedBooleanBinding() throws {
    // Hypothesis: a stable Boolean destination can retain the dismiss closure
    // for the binding that originally activated it after the modifier retargets.
    let probe = StressNP008Probe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP008", "Root"),
      size: .init(width: 54, height: 10)
    ) {
      StressNP008Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open First Destination Binding")
    _ = try harness.clickText("Retarget Destination Binding")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(probe.first)
    #expect(!probe.second)
    #expect(frame.contains("binding first true second false"))
    #expect(!frame.contains("retargeted destination"))
  }
}

@MainActor
private final class StressNP008Probe {
  var first = false
  var second = false

  func firstBinding() -> Binding<Bool> {
    Binding(get: { self.first }, set: { self.first = $0 })
  }

  func secondBinding() -> Binding<Bool> {
    Binding(get: { self.second }, set: { self.second = $0 })
  }
}

@MainActor
private struct StressNP008Fixture: View {
  let probe: StressNP008Probe
  @State private var usesSecond = false

  var body: some View {
    NavigationStack(id: "stress-np-008-stack") {
      VStack(alignment: .leading, spacing: 0) {
        Text("binding first \(probe.first) second \(probe.second)")
        Button("Open First Destination Binding") {
          probe.first = true
        }
      }
      .navigationDestination(
        isPresented: usesSecond ? probe.secondBinding() : probe.firstBinding()
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("retargeted destination")
          Button("Retarget Destination Binding") {
            probe.second = true
            usesSecond = true
          }
        }
      }
    }
  }
}

// MARK: - Attempt 009: three-level mixed destination chain

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 009 Escape unwinds mixed destination chain")
  func stress009EscapeUnwindsMixedDestinationChain() throws {
    // Hypothesis: Boolean and item activations nested three levels deep can
    // publish pop entries out of order or tear down an ancestor's local state.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP009", "Root"),
      size: .init(width: 52, height: 11)
    ) {
      StressNP009Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Outer Destination")
    _ = try harness.clickText("Increment Outer Local")
    _ = try harness.clickText("Open Middle Item")
    _ = try harness.clickText("Increment Middle Local")
    _ = try harness.clickText("Open Inner Destination")
    _ = try harness.focusText("Inner Focus Target")

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("middle item middle local 1"))
    #expect(!frame.contains("Inner Focus Target"))

    _ = try harness.focusText("Middle Focus Target")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("outer destination local 1"))
    #expect(!frame.contains("middle item middle"))

    _ = try harness.focusText("Outer Focus Target")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Open Outer Destination"))
    #expect(!frame.contains("outer destination local"))
  }
}

private struct StressNP009Item: Identifiable, Sendable {
  let id = "middle"
}

@MainActor
private struct StressNP009Fixture: View {
  @State private var outer = false

  var body: some View {
    NavigationStack(id: "stress-np-009-stack") {
      Button("Open Outer Destination") { outer = true }
        .navigationDestination(isPresented: $outer) {
          StressNP009OuterDestination()
        }
    }
  }
}

@MainActor
private struct StressNP009OuterDestination: View {
  @State private var local = 0
  @State private var middleItem: StressNP009Item?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("outer destination local \(local)")
      Button("Outer Focus Target") { local += 1 }
      Button("Increment Outer Local") { local += 1 }
      Button("Open Middle Item") { middleItem = StressNP009Item() }
    }
    .navigationDestination(item: $middleItem) { item in
      StressNP009MiddleDestination(item: item)
    }
  }
}

@MainActor
private struct StressNP009MiddleDestination: View {
  let item: StressNP009Item
  @State private var local = 0
  @State private var inner = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("middle item \(item.id) local \(local)")
      Button("Middle Focus Target") { local += 1 }
      Button("Increment Middle Local") { local += 1 }
      Button("Open Inner Destination") { inner = true }
    }
    .navigationDestination(isPresented: $inner) {
      Button("Inner Focus Target") {}
    }
  }
}

// MARK: - Attempt 010: intermediate item payload refresh under a deep route

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 010 deep route follows intermediate item refresh")
  func stress010DeepRouteFollowsIntermediateItemRefresh() throws {
    // Hypothesis: refreshing a same-ID item in an intermediate destination can
    // collapse its active child route or leave the deepest payload stale.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP010", "Root"),
      size: .init(width: 54, height: 10)
    ) {
      StressNP010Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Versioned Destination")
    _ = try harness.clickText("Open Deep Version Route")
    for version in 1...8 {
      _ = try harness.clickText("Increment Deep Version Local")
      let frame = try harness.clickText("Refresh Intermediate Item")
      #expect(frame.contains("deep outer version \(version) local \(version)"))
      #expect(harness.actionRegistrationCount <= 4)
    }
  }
}

private struct StressNP010Item: Identifiable, Sendable {
  let id = "versioned"
  var version: Int
}

@MainActor
private struct StressNP010Fixture: View {
  @State private var item: StressNP010Item?

  var body: some View {
    NavigationStack(id: "stress-np-010-stack") {
      Button("Open Versioned Destination") {
        item = StressNP010Item(version: 0)
      }
      .navigationDestination(item: $item) { item in
        StressNP010Intermediate(item: item, activeItem: $item)
      }
    }
  }
}

@MainActor
private struct StressNP010Intermediate: View {
  let item: StressNP010Item
  @Binding var activeItem: StressNP010Item?
  @State private var showsDeep = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("intermediate version \(item.version)")
      Button("Open Deep Version Route") { showsDeep = true }
    }
    .navigationDestination(isPresented: $showsDeep) {
      StressNP010DeepDestination(
        outerVersion: item.version,
        activeItem: $activeItem
      )
    }
  }
}

@MainActor
private struct StressNP010DeepDestination: View {
  let outerVersion: Int
  @Binding var activeItem: StressNP010Item?
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("deep outer version \(outerVersion) local \(local)")
      Button("Increment Deep Version Local") { local += 1 }
      Button("Refresh Intermediate Item") {
        activeItem = StressNP010Item(version: outerVersion + 1)
      }
    }
  }
}

// MARK: - Attempt 011: nested NavigationStack pop scoping

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 011 nested stack pops innermost scope first")
  func stress011NestedStackPopsInnermostScopeFirst() throws {
    // Hypothesis: pop-entry depth comparison can select the enclosing stack's
    // destination while focus is inside a nested NavigationStack destination.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP011", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      StressNP011Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open Outer Stack Destination")
    _ = try harness.clickText("Open Inner Stack Destination")
    _ = try harness.focusText("Inner Stack Focus Target")

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("outer stack destination"))
    #expect(frame.contains("Open Inner Stack Destination"))
    #expect(!frame.contains("Inner Stack Focus Target"))

    _ = try harness.focusText("Open Inner Stack Destination")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Open Outer Stack Destination"))
    #expect(!frame.contains("outer stack destination"))
  }
}

@MainActor
private struct StressNP011Fixture: View {
  @State private var outer = false

  var body: some View {
    NavigationStack(id: "stress-np-011-outer-stack") {
      Button("Open Outer Stack Destination") { outer = true }
        .navigationDestination(isPresented: $outer) {
          StressNP011OuterDestination()
        }
    }
  }
}

@MainActor
private struct StressNP011OuterDestination: View {
  @State private var inner = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("outer stack destination")
      NavigationStack(id: "stress-np-011-inner-stack") {
        Button("Open Inner Stack Destination") { inner = true }
          .navigationDestination(isPresented: $inner) {
            Button("Inner Stack Focus Target") {}
          }
      }
    }
  }
}

// MARK: - Attempt 012: sibling NavigationStack focus-scoped pop routing

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 012 focused sibling stack receives Escape pop")
  func stress012FocusedSiblingStackReceivesEscapePop() throws {
    // Hypothesis: when sibling stacks both publish active pop entries, global
    // last-wins reduction can pop the unfocused sibling's destination.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP012", "Root"),
      size: .init(width: 72, height: 9)
    ) {
      StressNP012Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Right Destination Target")
    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Left Destination Target"))
    #expect(frame.contains("Right Root Target"))
    #expect(!frame.contains("Right Destination Target"))

    _ = try harness.focusText("Left Destination Target")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Left Root Target"))
    #expect(frame.contains("Right Root Target"))
    #expect(!frame.contains("Left Destination Target"))
  }
}

@MainActor
private struct StressNP012Fixture: View {
  @State private var left = true
  @State private var right = true

  var body: some View {
    HStack(alignment: .top, spacing: 2) {
      NavigationStack(id: "stress-np-012-left") {
        Button("Left Root Target") { left = true }
          .navigationDestination(isPresented: $left) {
            Button("Left Destination Target") {}
          }
      }
      NavigationStack(id: "stress-np-012-right") {
        Button("Right Root Target") { right = true }
          .navigationDestination(isPresented: $right) {
            Button("Right Destination Target") {}
          }
      }
    }
  }
}

// MARK: - Attempt 013: active sibling stack removal

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 013 removed sibling stack prunes pop entry")
  func stress013RemovedSiblingStackPrunesPopEntry() throws {
    // Hypothesis: removing one of two active sibling stacks can leave its pop
    // closure in the aggregate preference and intercept the survivor's Escape.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP013", "Root"),
      size: .init(width: 72, height: 10)
    ) {
      StressNP013Fixture()
    }
    defer { harness.shutdown() }

    var frame = try harness.clickText("Remove Left Active Stack")
    #expect(!frame.contains("Left Removed Destination"))
    #expect(frame.contains("left binding true"))
    #expect(frame.contains("Right Surviving Destination"))

    _ = try harness.focusText("Right Surviving Destination")
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Right Surviving Root"))
    #expect(frame.contains("left binding true"))
    #expect(!frame.contains("Right Surviving Destination"))
    #expect(harness.actionRegistrationCount <= 2)
  }
}

@MainActor
private struct StressNP013Fixture: View {
  @State private var showsLeft = true
  @State private var left = true
  @State private var right = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Button("Remove Left Active Stack") { showsLeft = false }
        Text("left binding \(left)")
      }
      HStack(alignment: .top, spacing: 2) {
        if showsLeft {
          NavigationStack(id: "stress-np-013-left") {
            Button("Left Removed Root") { left = true }
              .navigationDestination(isPresented: $left) {
                Button("Left Removed Destination") {}
              }
          }
        }
        NavigationStack(id: "stress-np-013-right") {
          Button("Right Surviving Root") { right = true }
            .navigationDestination(isPresented: $right) {
              Button("Right Surviving Destination") {}
            }
        }
      }
    }
  }
}

// MARK: - Attempt 014: repeated navigation focus restoration

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 014 pop restores root focus repeatedly")
  func stress014PopRestoresRootFocusRepeatedly() throws {
    // Hypothesis: detached-root focus bookkeeping can retain a departed
    // destination identity or lose the root focus target after repeated pops.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP014", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      StressNP014Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...8 {
      _ = try harness.focusText("Push Focus Destination")
      _ = try harness.clickText("Push Focus Destination")
      _ = try harness.focusText("Destination Focus Target")
      let frame = try harness.pressKey(KeyPress(.escape))
      let rootFocus = try harness.focusIdentity(forText: "Push Focus Destination")

      #expect(frame.contains("root focus surface"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == rootFocus)
      #expect(harness.focusRegionCount == 1)
    }
  }
}

@MainActor
private struct StressNP014Fixture: View {
  @State private var isPresented = false

  var body: some View {
    NavigationStack(id: "stress-np-014-stack") {
      VStack(alignment: .leading, spacing: 0) {
        Text("root focus surface")
        Button("Push Focus Destination") { isPresented = true }
      }
      .navigationDestination(isPresented: $isPresented) {
        Button("Destination Focus Target") {}
      }
    }
  }
}

// MARK: - Attempt 015: nested navigation focus restoration chain

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 015 nested pops restore each focus level")
  func stress015NestedPopsRestoreEachFocusLevel() throws {
    // Hypothesis: the first pop can discard or overwrite the focus identity
    // needed by the next ancestor when a nested destination chain unwinds.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP015", "Root"),
      size: .init(width: 52, height: 9)
    ) {
      StressNP015Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Push Outer Focus Level")
    _ = try harness.clickText("Push Outer Focus Level")
    _ = try harness.focusText("Push Inner Focus Level")
    _ = try harness.clickText("Push Inner Focus Level")
    _ = try harness.focusText("Innermost Focus Level")

    var frame = try harness.pressKey(KeyPress(.escape))
    let outerFocus = try harness.focusIdentity(forText: "Push Inner Focus Level")
    #expect(frame.contains("outer focus level"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == outerFocus)

    frame = try harness.pressKey(KeyPress(.escape))
    let rootFocus = try harness.focusIdentity(forText: "Push Outer Focus Level")
    #expect(frame.contains("root focus level"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == rootFocus)
    #expect(harness.focusRegionCount == 1)
  }
}

@MainActor
private struct StressNP015Fixture: View {
  @State private var outer = false

  var body: some View {
    NavigationStack(id: "stress-np-015-stack") {
      VStack(alignment: .leading, spacing: 0) {
        Text("root focus level")
        Button("Push Outer Focus Level") { outer = true }
      }
      .navigationDestination(isPresented: $outer) {
        StressNP015OuterDestination()
      }
    }
  }
}

@MainActor
private struct StressNP015OuterDestination: View {
  @State private var inner = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("outer focus level")
      Button("Push Inner Focus Level") { inner = true }
    }
    .navigationDestination(isPresented: $inner) {
      Button("Innermost Focus Level") {}
    }
  }
}

@MainActor
private func stressNPPresentationEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .count
}

// MARK: - Attempt 016: sheet focus over repeated navigation activation

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 016 sheet and destination restore focus in order")
  func stress016SheetAndDestinationRestoreFocusInOrder() throws {
    // Hypothesis: alternating modal restoration and navigation pop can leave a
    // sheet focus identity on the stack or skip the destination focus owner.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP016", "Root"),
      size: .init(width: 56, height: 12)
    ) {
      StressNP016Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...6 {
      _ = try harness.focusText("Push Sheet Destination")
      _ = try harness.clickText("Push Sheet Destination")
      _ = try harness.focusText("Open Destination Sheet")
      _ = try harness.clickText("Open Destination Sheet")
      _ = try harness.focusText("Sheet Focus Target")
      #expect(stressNPPresentationEntryCount(in: harness) == 1)

      var frame = try harness.pressKey(KeyPress(.escape))
      let destinationFocus = try harness.focusIdentity(forText: "Open Destination Sheet")
      #expect(frame.contains("sheet destination body"))
      #expect(!frame.contains("Sheet Focus Target"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == destinationFocus)

      frame = try harness.pressKey(KeyPress(.escape))
      let rootFocus = try harness.focusIdentity(forText: "Push Sheet Destination")
      #expect(frame.contains("sheet navigation root"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == rootFocus)
      #expect(harness.focusModalRestorationStackCount == 0)
    }
  }
}

@MainActor
private struct StressNP016Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-016-stack") {
      VStack(alignment: .leading, spacing: 0) {
        Text("sheet navigation root")
        Button("Push Sheet Destination") { destination = true }
      }
      .navigationDestination(isPresented: $destination) {
        StressNP016Destination()
      }
    }
  }
}

@MainActor
private struct StressNP016Destination: View {
  @State private var sheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("sheet destination body")
      Button("Open Destination Sheet") { sheet = true }
    }
    .sheet("Destination Sheet", isPresented: $sheet) {
      Button("Sheet Focus Target") {}
    }
  }
}

// MARK: - Attempt 017: menu dismissal before navigation pop

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 017 menu dismisses before destination pop")
  func stress017MenuDismissesBeforeDestinationPop() throws {
    // Hypothesis: a nonmodal menu rooted in a detached destination can lose
    // ordering against that destination's pop action after repeated cycles.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP017", "Root"),
      size: .init(width: 54, height: 11)
    ) {
      StressNP017Fixture()
    }
    defer { harness.shutdown() }

    for _ in 1...6 {
      _ = try harness.clickText("Push Menu Destination")
      _ = try harness.focusText("Destination Actions")
      _ = try harness.clickText("Destination Actions")
      _ = try harness.focusText("Menu Overlay Target")
      #expect(stressNPPresentationEntryCount(in: harness) == 1)

      var frame = try harness.pressKey(KeyPress(.escape))
      let menuTriggerFocus = try harness.focusIdentity(forText: "Destination Actions")
      #expect(frame.contains("menu destination body"))
      #expect(!frame.contains("Menu Overlay Target"))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == menuTriggerFocus)

      frame = try harness.pressKey(KeyPress(.escape))
      #expect(frame.contains("Push Menu Destination"))
      #expect(!frame.contains("menu destination body"))
      #expect(stressNPPresentationEntryCount(in: harness) == 0)
    }
  }
}

@MainActor
private struct StressNP017Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-017-stack") {
      Button("Push Menu Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          VStack(alignment: .leading, spacing: 0) {
            Text("menu destination body")
            Menu("Destination Actions") {
              Button("Menu Overlay Target") {}
            }
          }
        }
    }
  }
}

// MARK: - Attempt 018: item popover identity replacement in a destination

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 018 item popover ID starts fresh lifetime")
  func stress018ItemPopoverIDStartsFreshLifetime() throws {
    // Hypothesis: replacing an open item popover's ID inside a detached
    // destination can preserve the old portal subtree's state or payload.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP018", "Root"),
      size: .init(width: 60, height: 13)
    ) {
      StressNP018Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Item Popover Destination")
    _ = try harness.clickText("Open Popover Item A")
    for version in 1...8 {
      _ = try harness.clickText("Increment Popover Item Local")
      let frame = try harness.clickText("Replace Popover Item ID")
      let expectedID = version.isMultiple(of: 2) ? "a" : "b"
      #expect(frame.contains("popover item \(expectedID) version \(version) local 0"))
      #expect(stressNPPresentationEntryCount(in: harness) == 1)
      #expect(harness.actionRegistrationCount <= 4)
    }
  }
}

private struct StressNP018Item: Identifiable, Sendable {
  var id: String
  var version: Int
}

@MainActor
private struct StressNP018Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-018-stack") {
      Button("Push Item Popover Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP018Destination()
        }
    }
  }
}

@MainActor
private struct StressNP018Destination: View {
  @State private var item: StressNP018Item?

  var body: some View {
    Button("Open Popover Item A") {
      item = StressNP018Item(id: "a", version: 0)
    }
    .popover(item: $item, arrowEdge: .trailing) { item in
      StressNP018Popover(item: item, activeItem: $item)
    }
  }
}

@MainActor
private struct StressNP018Popover: View {
  let item: StressNP018Item
  @Binding var activeItem: StressNP018Item?
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("popover item \(item.id) version \(item.version) local \(local)")
      Button("Increment Popover Item Local") { local += 1 }
      Button("Replace Popover Item ID") {
        activeItem = StressNP018Item(
          id: item.id == "a" ? "b" : "a",
          version: item.version + 1
        )
      }
    }
  }
}

// MARK: - Attempt 019: active popover binding retarget

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 019 Escape writes retargeted popover binding")
  func stress019EscapeWritesRetargetedPopoverBinding() throws {
    // Hypothesis: an open popover can retain the dismiss closure captured from
    // its original Boolean binding after the modifier switches bindings.
    let probe = StressNP019Probe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP019", "Root"),
      size: .init(width: 58, height: 12)
    ) {
      StressNP019Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Open First Popover Binding")
    _ = try harness.clickText("Retarget Popover Binding")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(probe.first)
    #expect(!probe.second)
    #expect(frame.contains("Open First Popover Binding"))
    #expect(!frame.contains("Retarget Popover Binding"))
    #expect(stressNPPresentationEntryCount(in: harness) == 0)
  }
}

@MainActor
private final class StressNP019Probe {
  var first = false
  var second = false

  func firstBinding() -> Binding<Bool> {
    Binding(get: { self.first }, set: { self.first = $0 })
  }

  func secondBinding() -> Binding<Bool> {
    Binding(get: { self.second }, set: { self.second = $0 })
  }
}

@MainActor
private struct StressNP019Fixture: View {
  let probe: StressNP019Probe
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("popover binding first \(probe.first) second \(probe.second)")
      Button("Open First Popover Binding") { probe.first = true }
        .popover(
          isPresented: usesSecond ? probe.secondBinding() : probe.firstBinding(),
          arrowEdge: .trailing
        ) {
          Button("Retarget Popover Binding") {
            probe.second = true
            usesSecond = true
          }
        }
    }
  }
}

// MARK: - Attempt 020: sheet source remint inside an active destination

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 020 reminted sheet source preserves navigation route")
  func stress020RemintedSheetSourcePreservesNavigationRoute() throws {
    // Hypothesis: replacing a sheet declaration source inside a detached
    // destination can duplicate the overlay or corrupt the destination pop.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP020", "Root"),
      size: .init(width: 58, height: 13)
    ) {
      StressNP020Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Reminted Sheet Destination")
    _ = try harness.clickText("Open Nested Reminted Sheet")
    for generation in 1...8 {
      let frame = try harness.clickText("Remint Nested Sheet Source", chooseLast: true)
      #expect(frame.contains("nested sheet generation \(generation)"))
      #expect(
        frame.components(separatedBy: "nested sheet generation").count - 1 == 1
      )
      #expect(stressNPPresentationEntryCount(in: harness) == 1)
      #expect(harness.actionRegistrationCount <= 4)
    }

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("nested sheet destination generation 8"))
    #expect(!frame.contains("Remint Nested Sheet Source"))
    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Push Reminted Sheet Destination"))
  }
}

@MainActor
private struct StressNP020Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-020-stack") {
      Button("Push Reminted Sheet Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP020Destination()
        }
    }
  }
}

@MainActor
private struct StressNP020Destination: View {
  @State private var sheet = false
  @State private var generation = 0

  var body: some View {
    Group {
      VStack(alignment: .leading, spacing: 0) {
        Text("nested sheet destination generation \(generation)")
        Button("Open Nested Reminted Sheet") { sheet = true }
      }
    }
    .id("stress-np-020-sheet-source-\(generation)")
    .sheet("Nested Reminted Sheet", isPresented: $sheet) {
      VStack(alignment: .leading, spacing: 0) {
        Text("nested sheet generation \(generation)")
        Button("Remint Nested Sheet Source") { generation += 1 }
      }
    }
  }
}

// MARK: - Attempt 021: live alert action refresh in a destination

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 021 alert actions capture current destination state")
  func stress021AlertActionsCaptureCurrentDestinationState() throws {
    // Hypothesis: a retained alert portal payload can render updated text while
    // dispatching the action closure captured by an earlier activation.
    let probe = StressNP021Probe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP021", "Root"),
      size: .init(width: 62, height: 14)
    ) {
      StressNP021Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Alert Destination")
    for generation in 1...6 {
      _ = try harness.clickText("Open Stateful Alert")
      let refreshed = try harness.clickText("Advance Alert Generation", chooseLast: true)
      #expect(refreshed.contains("alert generation \(generation)"))
      _ = try harness.clickText("Record Alert Generation", chooseLast: true)
      #expect(probe.markers == Array(1...generation).map { "record \($0)" })
      #expect(stressNPPresentationEntryCount(in: harness) == 0)
      #expect(harness.actionRegistrationCount <= 2)
    }
  }
}

@MainActor
private final class StressNP021Probe {
  var markers: [String] = []
}

@MainActor
private struct StressNP021Fixture: View {
  let probe: StressNP021Probe
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-021-stack") {
      Button("Push Alert Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP021Destination(probe: probe)
        }
    }
  }
}

@MainActor
private struct StressNP021Destination: View {
  let probe: StressNP021Probe
  @State private var alert = false
  @State private var generation = 0

  var body: some View {
    Button("Open Stateful Alert") { alert = true }
      .alert(
        "Stateful Alert",
        isPresented: $alert,
        actions: {
          Button("Advance Alert Generation") { generation += 1 }
          Button("Record Alert Generation") {
            probe.markers.append("record \(generation)")
            alert = false
          }
        },
        message: {
          Text("alert generation \(generation)")
        }
      )
  }
}

// MARK: - Attempt 022: active confirmation source reorder

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 022 reordered confirmation keeps current actions")
  func stress022ReorderedConfirmationKeepsCurrentActions() throws {
    // Hypothesis: moving an active confirmation declaration across a sibling
    // can duplicate its portal entry or retain a stale action payload.
    let probe = StressNP022Probe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP022", "Root"),
      size: .init(width: 64, height: 15)
    ) {
      StressNP022Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Confirmation Destination")
    _ = try harness.clickText("Open Reorder Confirmation")
    for generation in 1...6 {
      let frame = try harness.clickText("Reorder Confirmation Source", chooseLast: true)
      #expect(frame.contains("confirmation generation \(generation)"))
      #expect(stressNPPresentationEntryCount(in: harness) == 1)
    }

    _ = try harness.clickText("Commit Confirmation Generation", chooseLast: true)
    #expect(probe.markers == ["commit 6"])
    #expect(stressNPPresentationEntryCount(in: harness) == 0)
  }
}

@MainActor
private final class StressNP022Probe {
  var markers: [String] = []
}

@MainActor
private struct StressNP022Fixture: View {
  let probe: StressNP022Probe
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-022-stack") {
      Button("Push Confirmation Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP022Destination(probe: probe)
        }
    }
  }
}

@MainActor
private struct StressNP022Destination: View {
  let probe: StressNP022Probe
  @State private var confirmation = false
  @State private var reversed = false
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if reversed {
        peer
        source
      } else {
        source
        peer
      }
    }
  }

  private var source: some View {
    Button("Open Reorder Confirmation") { confirmation = true }
      .id("stress-np-022-confirmation-source")
      .confirmationDialog(
        "Reorder Confirmation",
        isPresented: $confirmation,
        actions: {
          Button("Reorder Confirmation Source") {
            generation += 1
            reversed.toggle()
          }
          Button("Commit Confirmation Generation") {
            probe.markers.append("commit \(generation)")
            confirmation = false
          }
        },
        message: {
          Text("confirmation generation \(generation)")
        }
      )
  }

  private var peer: some View {
    Text("confirmation stable peer")
      .id("stress-np-022-peer")
  }
}

// MARK: - Attempt 023: alert over sheet over navigation destination

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 023 Escape unwinds alert sheet destination")
  func stress023EscapeUnwindsAlertSheetDestination() throws {
    // Hypothesis: fixed presentation-family z-order composed with navigation
    // can skip the sheet layer or consume the destination pop too early.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP023", "Root"),
      size: .init(width: 64, height: 16)
    ) {
      StressNP023Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Push Layered Destination")
    _ = try harness.clickText("Push Layered Destination")
    _ = try harness.focusText("Open Layered Sheet")
    _ = try harness.clickText("Open Layered Sheet")
    _ = try harness.focusText("Open Alert Above Sheet")
    _ = try harness.clickText("Open Alert Above Sheet")
    _ = try harness.focusText("Alert Layer Target")
    #expect(stressNPPresentationEntryCount(in: harness) == 2)

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("layered sheet body"))
    #expect(!frame.contains("Alert Layer Target"))
    #expect(stressNPPresentationEntryCount(in: harness) == 1)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("layered destination body"))
    #expect(!frame.contains("layered sheet body"))
    #expect(stressNPPresentationEntryCount(in: harness) == 0)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Push Layered Destination"))
    #expect(!frame.contains("layered destination body"))
  }
}

@MainActor
private struct StressNP023Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-023-stack") {
      Button("Push Layered Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP023Destination()
        }
    }
  }
}

@MainActor
private struct StressNP023Destination: View {
  @State private var sheet = false
  @State private var alert = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("layered destination body")
      Button("Open Layered Sheet") { sheet = true }
    }
    .sheet("Layered Sheet", isPresented: $sheet) {
      VStack(alignment: .leading, spacing: 0) {
        Text("layered sheet body")
        Button("Open Alert Above Sheet") { alert = true }
      }
    }
    .alert(
      "Layered Alert",
      isPresented: $alert,
      actions: {
        Button("Alert Layer Target") {}
      },
      message: {
        Text("alert above sheet body")
      }
    )
  }
}

// MARK: - Attempt 024: sheet teardown after nested stack remints

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 024 sheet teardown prunes reminted nested stack")
  func stress024SheetTeardownPrunesRemintedNestedStack() throws {
    // Hypothesis: reminting an active NavigationStack inside sheet content can
    // strand destination actions or a pop entry after the sheet is dismissed.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP024", "Root"),
      size: .init(width: 62, height: 14)
    ) {
      StressNP024Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Nested Sheet Destination")
    _ = try harness.focusText("Open Nested Navigation Sheet")
    _ = try harness.clickText("Open Nested Navigation Sheet")
    for generation in 1...6 {
      let frame = try harness.clickText("Remint Inner Sheet Stack")
      withKnownIssue("Reminted nested stack retains departed actions until sheet teardown") {
        // The strand family also keeps the departed generation's committed
        // children painted, so the reminted stack's fresh generation label
        // does not reach the frame.
        #expect(frame.contains("inner sheet stack generation \(generation)"))
        #expect(harness.actionRegistrationCount <= 5)
      }
    }

    var frame = try harness.pressKey(KeyPress(.escape))
    let destinationFocus = try harness.focusIdentity(forText: "Open Nested Navigation Sheet")
    #expect(frame.contains("outer nested-sheet destination"))
    #expect(!frame.contains("inner sheet stack generation"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == destinationFocus)
    #expect(stressNPPresentationEntryCount(in: harness) == 0)
    #expect(harness.actionRegistrationCount <= 2)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Push Nested Sheet Destination"))
  }
}

@MainActor
private struct StressNP024Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-024-outer-stack") {
      Button("Push Nested Sheet Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP024Destination()
        }
    }
  }
}

@MainActor
private struct StressNP024Destination: View {
  @State private var sheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("outer nested-sheet destination")
      Button("Open Nested Navigation Sheet") { sheet = true }
    }
    .sheet("Nested Navigation Sheet", isPresented: $sheet) {
      StressNP024Sheet()
    }
  }
}

@MainActor
private struct StressNP024Sheet: View {
  @State private var inner = true
  @State private var generation = 0

  var body: some View {
    NavigationStack(id: "stress-np-024-inner-scope") {
      Button("Inner Sheet Stack Root") { inner = true }
        .navigationDestination(isPresented: $inner) {
          VStack(alignment: .leading, spacing: 0) {
            Text("inner sheet stack generation \(generation)")
            Button("Remint Inner Sheet Stack") { generation += 1 }
          }
        }
    }
    .id("stress-np-024-inner-host-\(generation)")
  }
}

// MARK: - Attempt 025: alert over confirmation over destination

extension FrameworkStressNavigationPresentationTests {
  @Test("stress navigation presentation 025 Escape unwinds alert confirmation destination")
  func stress025EscapeUnwindsAlertConfirmationDestination() throws {
    // Hypothesis: two prompt-family coordinators with adjacent z-order can
    // dismiss together or expose the navigation pop before the lower prompt.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressNP025", "Root"),
      size: .init(width: 66, height: 16)
    ) {
      StressNP025Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Push Prompt Destination")
    _ = try harness.clickText("Open Layered Confirmation")
    _ = try harness.clickText("Open Alert Above Confirmation", chooseLast: true)
    _ = try harness.focusText("Alert Above Confirmation Target")
    #expect(stressNPPresentationEntryCount(in: harness) == 2)

    var frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Open Alert Above Confirmation"))
    #expect(!frame.contains("Alert Above Confirmation Target"))
    #expect(stressNPPresentationEntryCount(in: harness) == 1)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("prompt destination body"))
    #expect(!frame.contains("Open Alert Above Confirmation"))
    #expect(stressNPPresentationEntryCount(in: harness) == 0)

    frame = try harness.pressKey(KeyPress(.escape))
    #expect(frame.contains("Push Prompt Destination"))
    #expect(!frame.contains("prompt destination body"))
  }
}

@MainActor
private struct StressNP025Fixture: View {
  @State private var destination = false

  var body: some View {
    NavigationStack(id: "stress-np-025-stack") {
      Button("Push Prompt Destination") { destination = true }
        .navigationDestination(isPresented: $destination) {
          StressNP025Destination()
        }
    }
  }
}

@MainActor
private struct StressNP025Destination: View {
  @State private var confirmation = false
  @State private var alert = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("prompt destination body")
      Button("Open Layered Confirmation") { confirmation = true }
    }
    .confirmationDialog(
      "Layered Confirmation",
      isPresented: $confirmation,
      actions: {
        Button("Open Alert Above Confirmation") { alert = true }
      },
      message: {
        Text("confirmation below alert body")
      }
    )
    .alert(
      "Alert Above Confirmation",
      isPresented: $alert,
      actions: {
        Button("Alert Above Confirmation Target") {}
      },
      message: {
        Text("alert above confirmation body")
      }
    )
  }
}
