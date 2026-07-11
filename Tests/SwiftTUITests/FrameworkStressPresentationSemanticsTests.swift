import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI presentation and semantics stress behavior", .serialized)
struct FrameworkStressPresentationSemanticsTests {}

@MainActor
private final class StressPresentationProbe {
  var markers: [String] = []
  var firstBool = false
  var secondBool = false
  var firstInt = 0
  var secondInt = 0
  var selection = "b"

  func firstBoolBinding() -> Binding<Bool> {
    Binding(get: { self.firstBool }, set: { self.firstBool = $0 })
  }

  func secondBoolBinding() -> Binding<Bool> {
    Binding(get: { self.secondBool }, set: { self.secondBool = $0 })
  }

  func firstIntBinding() -> Binding<Int> {
    Binding(get: { self.firstInt }, set: { self.firstInt = $0 })
  }

  func secondIntBinding() -> Binding<Int> {
    Binding(get: { self.secondInt }, set: { self.secondInt = $0 })
  }

  func selectionBinding() -> Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
private func stressPresentationEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .count
}

@MainActor
private func stressAccessibilityNodes<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> [AccessibilityNode] {
  harness.runLoop.latestSemanticSnapshot.accessibilityNodes
}

// MARK: - Attempt 001: retained overlay host one-to-two transition

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 001 opening a sheet appends to an open menu overlay")
  func stress001OpeningSheetAppendsToOpenMenuOverlay() throws {
    // Hypothesis: retained overlay-host reuse may serve the committed one-entry
    // child list when opening a second menu only invalidates its trigger source.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS001", "Root"),
      size: .init(width: 72, height: 18)
    ) {
      StressPS001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Actions")
    let frame = try harness.clickText("Open sheet from menu")

    #expect(frame.contains("Sheet overlay body"))
    #expect(stressPresentationEntryCount(in: harness) == 2)
  }
}

@MainActor
private struct StressPS001Fixture: View {
  @State private var showsSheet = false

  var body: some View {
    Menu("Actions") {
      Button("Open sheet from menu") {
        showsSheet = true
      }
    }
    .sheet("Stress sheet", isPresented: $showsSheet) {
      Text("Sheet overlay body")
    }
    .frame(width: 70, height: 16, alignment: .topLeading)
  }
}

// MARK: - Attempt 002: retained overlay host two-to-one transition

extension FrameworkStressPresentationSemanticsTests {
  @Test("stress presentation semantics 002 dismissing a sheet preserves its underlying menu")
  func stress002DismissingSheetPreservesUnderlyingMenu() throws {
    // Hypothesis: after a two-entry commit, retained overlay-host reuse may
    // leave the dismissed sheet child present or discard the surviving menu.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressPS002", "Root"),
      size: .init(width: 72, height: 18)
    ) {
      StressPS001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Actions")
    _ = try harness.clickText("Open sheet from menu")
    let frame = try harness.pressKey(KeyPress(.escape))

    #expect(frame.contains("Open sheet from menu"))
    #expect(!frame.contains("Sheet overlay body"))
    #expect(stressPresentationEntryCount(in: harness) == 1)
  }
}
