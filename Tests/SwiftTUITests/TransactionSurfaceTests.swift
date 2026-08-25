import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage T0 pins for the additive transaction surface (plan 2026-08-25-002
/// §6, T1): `Transaction(animation:)`, the key-path `withTransaction`, and
/// `View.transaction(value:_:)`.
@MainActor
@Suite("Transaction surface")
struct TransactionSurfaceTests {
  // MARK: - Transaction(animation:)

  @Test("Transaction(animation:) round-trips the animation and nil disables")
  func transactionAnimationInitRoundTrips() {
    let animation = Animation.easeOut(duration: .milliseconds(300))
    let animated = Transaction(animation: animation)
    #expect(animated.animation == animation)
    #expect(!animated.disablesAnimations)
    #expect(!animated.isInert)

    let disabled = Transaction(animation: nil)
    #expect(disabled.animation == nil)
    #expect(disabled.disablesAnimations)
  }

  @Test("isInert is false for a completion-only transaction")
  func completionOnlyTransactionIsNotInert() {
    var transaction = Transaction()
    #expect(transaction.isInert)
    transaction.addAnimationCompletion {}
    #expect(!transaction.isInert)
    #expect(transaction.pendingCompletions.count == 1)
  }

  // MARK: - withTransaction key path

  @Test("withTransaction(\\.disablesAnimations, true) snaps inside an outer withAnimation")
  func keyPathWithTransactionSnapsInsideAnimationScope() throws {
    // Write-side segmentation is per state owner, so the animated control
    // write and the snapped write live in different views: the inner
    // key-path scope governs its own owner's write, the outer scope the
    // other's.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("KeyPathTransactionRoot"),
      size: .init(width: 40, height: 8)
    ) {
      KeyPathTransactionFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      try harness.clickText("snap")
      _ = try harness.renderAfterExternalMutation()
    }
    var scopes = Set(controller.debugStateSnapshot().activeAnimationKeys.map(\.scope))
    #expect(
      !scopes.contains(.property(.opacity)),
      "the write inside withTransaction(\\.disablesAnimations, true) must snap"
    )

    try withAnimationSinks(controller) {
      try harness.clickText("go")
      _ = try harness.renderAfterExternalMutation()
    }
    scopes = Set(controller.debugStateSnapshot().activeAnimationKeys.map(\.scope))
    #expect(scopes.contains(.property(.offset)), "the plain withAnimation write animates")
    #expect(!scopes.contains(.property(.opacity)))
  }

  @Test("withTransaction(keyPath:) keeps the enclosing scope's continuity and custom values")
  func keyPathWithTransactionInheritsEnclosingMetadata() {
    var outer = Transaction()
    outer.isContinuous = true
    outer[TransactionSurfaceSourceKey.self] = "drag"
    var observed: (continuous: Bool, source: String, request: AnimationRequest)?
    withTransaction(outer) {
      withTransaction(\.disablesAnimations, true) {
        observed = (
          AnimationContextStorage.currentIsContinuous,
          AnimationContextStorage.currentCustomValues[
            ObjectIdentifier(TransactionSurfaceSourceKey.self)
          ]?.unwrap(as: String.self) ?? "",
          AnimationContextStorage.currentRequest
        )
      }
    }
    #expect(observed?.continuous == true)
    #expect(observed?.source == "drag")
    #expect(observed?.request == .disabled)
  }

  // MARK: - .transaction(value:)

  @Test(".transaction(value:) fires only when its value changes and registers the curve")
  func valueTransactionGatesOnValueAndRegisters() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ValueTransactionRoot"),
      size: .init(width: 40, height: 6)
    ) {
      ValueTransactionFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    // An unrelated change: the gated value is untouched, so the offset snaps.
    try withAnimationSinks(controller) {
      try harness.clickText("nudge")
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(controller.activeAnimationCount == 0, "a write that leaves the gate value alone snaps")

    // A change that flips the gate value animates with the transformed
    // transaction, and the curve survives its first tick (the modifier
    // registered the box with the sink).
    try withAnimationSinks(controller) {
      try harness.clickText("cross")
      _ = try harness.renderAfterExternalMutation()
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(
      controller.activeAnimationCount == 1, "the gated change must animate and stay registered")
    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values.contains(
        ValueTransactionFixture.animation.animationBox
      )
    )
  }

  @Test(".transaction(value:) stacks with .animation(_:value:) without ordinal aliasing")
  func valueTransactionStacksWithValueAnimation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StackedGateRoot"),
      size: .init(width: 40, height: 6)
    ) {
      StackedGateFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    // A steady-state resolve must not manufacture a phantom change.
    try withAnimationSinks(controller) {
      _ = try harness.renderAfterExternalMutation()
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(controller.activeAnimationCount == 0)

    try withAnimationSinks(controller) {
      try harness.clickText("outer")
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values.contains(
        StackedGateFixture.outerAnimation.animationBox
      ),
      "flipping the outer gate animates with the outer curve"
    )

    try withAnimationSinks(controller) {
      try harness.clickText("inner")
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values.contains(
        StackedGateFixture.innerAnimation.animationBox
      ),
      "flipping the inner gate animates with the inner curve"
    )
  }
}

// MARK: - Fixtures

private struct TransactionSurfaceSourceKey: TransactionKey {
  static let defaultValue = ""
}

@MainActor
private struct KeyPathTransactionFixture: View {
  @State private var offsetX = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        withAnimation(.linear(duration: .seconds(2))) {
          offsetX += 5
        }
      }
      Text("moved").offset(x: offsetX, y: 0)
      KeyPathFadeLeaf()
    }
  }
}

@MainActor
private struct KeyPathFadeLeaf: View {
  @State private var faded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("snap") {
        withAnimation(.linear(duration: .seconds(2))) {
          withTransaction(\.disablesAnimations, true) {
            faded.toggle()
          }
        }
      }
      Text("faded").opacity(faded ? 0.2 : 1.0)
    }
  }
}

@MainActor
private struct ValueTransactionFixture: View {
  nonisolated static let animation = Animation.linear(duration: .seconds(2))
  @State private var offsetX = 0
  @State private var gate = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("nudge") { offsetX += 1 }
      Button("cross") {
        offsetX += 1
        gate += 1
      }
      Text("subject")
        .offset(x: offsetX, y: 0)
        .transaction(value: gate) { $0.animation = Self.animation }
    }
  }
}

@MainActor
private struct StackedGateFixture: View {
  nonisolated static let outerAnimation = Animation.linear(duration: .seconds(2))
  nonisolated static let innerAnimation = Animation.easeIn(duration: .seconds(3))
  @State private var outerGate = 0
  @State private var innerGate = false
  @State private var offsetX = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("outer") {
        offsetX += 1
        outerGate += 1
      }
      Button("inner") {
        offsetX += 1
        innerGate.toggle()
      }
      Text("subject")
        .offset(x: offsetX, y: 0)
        .transaction(value: innerGate) { $0.animation = Self.innerAnimation }
        .animation(Self.outerAnimation, value: outerGate)
    }
  }
}
