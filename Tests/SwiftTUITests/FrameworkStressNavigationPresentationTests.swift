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
