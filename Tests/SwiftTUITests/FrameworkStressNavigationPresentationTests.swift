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
      withKnownIssue("Item destination ID replacement retains departed action registrations") {
        #expect(harness.actionRegistrationCount <= 3)
      }
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
      withKnownIssue("Source remint retains departed destination action registrations") {
        #expect(harness.actionRegistrationCount <= 3)
      }
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
      withKnownIssue("Source cardinality churn retains departed action registrations") {
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
