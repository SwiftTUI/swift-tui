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
