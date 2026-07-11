import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI toast lifecycle stress behavior", .serialized)
struct FrameworkStressToastLifecycleTests {}

@MainActor
private func toastLifecycleEntryCount<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> Int {
  harness.runLoop.renderer.debugRuntimeSubsystemSnapshot().presentationPortalState.overlayEntries
    .filter { $0.kindName == "ToastPresentation" }
    .count
}

// MARK: - Attempt 001: active message refresh

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 001 active message follows source generations")
  func toastLifecycle001ActiveMessageFollowsSourceGenerations() throws {
    // Hypothesis: a stable toast item can retain the first declared Text payload while its source
    // keeps emitting fresh generations under the same portal entry identity.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle001"),
      size: .init(width: 58, height: 10)
    ) {
      ToastLifecycle001Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Advance Toast Message 001")
      #expect(frame.contains("toast message generation \(generation)"))
      #expect(!frame.contains("toast message generation \(generation - 1)"))
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle001Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Toast Message 001") { generation += 1 }
      Text("source generation \(generation)")
    }
    .toast(
      "toast message generation \(generation)",
      isPresented: $isPresented,
      duration: nil
    )
  }
}

// MARK: - Attempt 002: content cardinality replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 002 active content replaces its child cardinality")
  func toastLifecycle002ActiveContentReplacesItsChildCardinality() throws {
    // Hypothesis: a retained ToastContent attachment can preserve the previous one-child or
    // two-child topology even after the source emits a freshly built payload group.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle002"),
      size: .init(width: 62, height: 12)
    ) {
      ToastLifecycle002Root()
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      let frame = try harness.clickText("Replace Toast Topology 002")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("compact toast generation \(generation)"))
        #expect(!frame.contains("detail toast generation \(generation)"))
      } else {
        #expect(frame.contains("primary toast generation \(generation)"))
        #expect(frame.contains("detail toast generation \(generation)"))
        #expect(!frame.contains("compact toast generation \(generation)"))
      }
      #expect(toastLifecycleEntryCount(in: harness) == 1)
    }
  }
}

@MainActor
private struct ToastLifecycle002Root: View {
  @State private var generation = 0
  @State private var expanded = false
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Topology 002") {
      generation += 1
      expanded.toggle()
    }
    .toast(isPresented: $isPresented, duration: nil) {
      if expanded {
        VStack(alignment: .leading, spacing: 0) {
          Text("primary toast generation \(generation)")
          Text("detail toast generation \(generation)")
        }
      } else {
        Text("compact toast generation \(generation)")
      }
    }
  }
}

// MARK: - Attempt 003: erased style family replacement

extension FrameworkStressToastLifecycleTests {
  @Test("stress toast lifecycle 003 active toast adopts each replacement style family")
  func toastLifecycle003ActiveToastAdoptsEachReplacementStyleFamily() throws {
    // Hypothesis: AnyToastStyle can retain its first concrete box while the active item keeps the
    // same ID, leaving the toast icon and semantic chrome on the previous style family.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToastLifecycle003"),
      size: .init(width: 56, height: 10)
    ) {
      ToastLifecycle003Root()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Replace Toast Style 003")
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("ℹ"))
        #expect(!frame.contains("✓"))
      } else {
        #expect(frame.contains("✓"))
        #expect(!frame.contains("ℹ"))
      }
      #expect(frame.contains("style family generation \(generation)"))
    }
  }
}

@MainActor
private struct ToastLifecycle003Root: View {
  @State private var generation = 0
  @State private var isPresented = true

  var body: some View {
    Button("Replace Toast Style 003") { generation += 1 }
      .toast(
        "style family generation \(generation)",
        isPresented: $isPresented,
        style: generation.isMultiple(of: 2) ? .info : .success,
        duration: nil
      )
  }
}
