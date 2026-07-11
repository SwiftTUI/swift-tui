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
