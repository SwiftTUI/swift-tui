import Foundation
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI animation and temporal stress behavior", .serialized)
struct FrameworkStressAnimationTemporalTests {}

// MARK: - Attempt 001: unchanged value-animation inheritance

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 001 unchanged value animation inherits outer intent")
  func animationTemporal001UnchangedValueAnimationInheritsOuterIntent() throws {
    // Hypothesis: retained value-animation bookkeeping can mistake every outer
    // transaction for a watched-value change and replace its animation intent.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let outerAnimation = Animation.linear(duration: .seconds(4))
    controller.register(outerAnimation)
    let identity = testIdentity("AnimationTemporal001", "Root")
    let proposal = ProposedSize(width: 36, height: 4)

    _ = renderer.render(
      animationTemporal001View(opacity: 0.1, watchedValue: 7),
      context: .init(identity: identity),
      proposal: proposal
    )

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(outerAnimation.animationBox)
    for generation in 1...16 {
      let opacity = generation.isMultiple(of: 2) ? 0.2 : 0.8
      _ = renderer.render(
        animationTemporal001View(opacity: opacity, watchedValue: 7),
        context: .init(identity: identity, transaction: transaction),
        proposal: proposal
      )
      #expect(
        controller.activeAnimationCount == 1,
        "generation \(generation) should retain exactly one outer opacity animation"
      )
    }
  }
}

@MainActor
private func animationTemporal001View(opacity: Double, watchedValue: Int) -> some View {
  Text("animation temporal 001")
    .opacity(opacity)
    .animation(.easeInOut(duration: .milliseconds(80)), value: watchedValue)
}

// MARK: - Attempt 002: nil value-animation suppression lifetime

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 002 nil value animation suppresses only its watched change")
  func animationTemporal002NilAnimationSuppressesOnlyWatchedChange() throws {
    // Hypothesis: a `.animation(nil,value:)` change can leave `.disabled` in
    // retained transaction state and suppress later unrelated outer animations.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let outerAnimation = Animation.linear(duration: .seconds(4))
    controller.register(outerAnimation)
    let identity = testIdentity("AnimationTemporal002", "Root")
    let proposal = ProposedSize(width: 36, height: 4)

    _ = renderer.render(
      animationTemporal002View(opacity: 0.1, watchedValue: 0),
      context: .init(identity: identity),
      proposal: proposal
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(outerAnimation.animationBox)

    _ = renderer.render(
      animationTemporal002View(opacity: 0.5, watchedValue: 1),
      context: .init(identity: identity, transaction: transaction),
      proposal: proposal
    )
    withKnownIssue(
      "`.animation(nil,value:)` does not suppress an inherited animation when its value changes"
    ) {
      #expect(controller.activeAnimationCount == 0)
    }

    _ = renderer.render(
      animationTemporal002View(opacity: 0.9, watchedValue: 1),
      context: .init(identity: identity, transaction: transaction),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 1)
  }
}

@MainActor
private func animationTemporal002View(opacity: Double, watchedValue: Int) -> some View {
  Text("animation temporal 002")
    .opacity(opacity)
    .animation(nil, value: watchedValue)
}

// MARK: - Attempt 003: value-animation baseline through entity reorder

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 003 value animation baselines follow reordered entities")
  func animationTemporal003ValueBaselinesFollowReorderedEntities() throws {
    // Hypothesis: the silent previous-value slot can follow structural row
    // position instead of entity identity and animate unchanged reordered rows.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal003", "Root")
    let proposal = ProposedSize(width: 40, height: 6)
    let initial = [
      AnimationTemporal003Row(id: "a", value: 1, opacity: 0.2),
      AnimationTemporal003Row(id: "b", value: 2, opacity: 0.7),
    ]

    _ = renderer.render(
      animationTemporal003View(rows: initial),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal003View(rows: Array(initial.reversed())),
      context: .init(identity: identity),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 0)

    let changed = [
      AnimationTemporal003Row(id: "b", value: 2, opacity: 0.7),
      AnimationTemporal003Row(id: "a", value: 3, opacity: 0.9),
    ]
    _ = renderer.render(
      animationTemporal003View(rows: changed),
      context: .init(identity: identity),
      proposal: proposal
    )
    withKnownIssue("A reordered ForEach entity loses its value-animation baseline") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

private struct AnimationTemporal003Row: Identifiable, Sendable {
  let id: String
  let value: Int
  let opacity: Double
}

@MainActor
private func animationTemporal003View(rows: [AnimationTemporal003Row]) -> some View {
  VStack(alignment: .leading, spacing: 0) {
    ForEach(rows) { row in
      Text("003 row \(row.id)")
        .opacity(row.opacity)
        .animation(.linear(duration: .seconds(4)), value: row.value)
    }
  }
}

// MARK: - Attempt 004: duplicate occurrence value-animation isolation

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 004 duplicate occurrences isolate value animation baselines")
  func animationTemporal004DuplicateOccurrencesIsolateValueBaselines() throws {
    // Hypothesis: duplicate entity routes can collapse their silent modifier
    // slots and make one occurrence consume the other's watched-value baseline.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal004", "Root")
    let proposal = ProposedSize(width: 40, height: 6)

    _ = renderer.render(
      animationTemporal004View(firstValue: 1, firstOpacity: 0.2),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal004View(firstValue: 3, firstOpacity: 0.9),
      context: .init(identity: identity),
      proposal: proposal
    )

    withKnownIssue("Duplicate ForEach occurrences lose independent value-animation baselines") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

@MainActor
private func animationTemporal004View(firstValue: Int, firstOpacity: Double) -> some View {
  let rows = [
    AnimationTemporal004Row(
      id: "duplicate", label: "first", value: firstValue, opacity: firstOpacity),
    AnimationTemporal004Row(id: "duplicate", label: "second", value: 2, opacity: 0.6),
  ]
  return VStack(alignment: .leading, spacing: 0) {
    ForEach(rows) { row in
      Text("004 \(row.label)")
        .opacity(row.opacity)
        .animation(.linear(duration: .seconds(4)), value: row.value)
    }
  }
}

private struct AnimationTemporal004Row: Identifiable, Sendable {
  let id: String
  let label: String
  let value: Int
  let opacity: Double
}

// MARK: - Attempt 005: explicit identity value-animation lifetime

extension FrameworkStressAnimationTemporalTests {
  @Test("stress animation temporal 005 explicit identity replacement starts a fresh baseline")
  func animationTemporal005ExplicitIdentityReplacementStartsFreshBaseline() throws {
    // Hypothesis: the modifier's reserved state slot can survive explicit ID
    // replacement and animate the new owner from its predecessor's value.
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let identity = testIdentity("AnimationTemporal005", "Root")
    let proposal = ProposedSize(width: 40, height: 4)

    _ = renderer.render(
      animationTemporal005View(owner: "a", value: 1, opacity: 0.2),
      context: .init(identity: identity),
      proposal: proposal
    )
    _ = renderer.render(
      animationTemporal005View(owner: "b", value: 2, opacity: 0.8),
      context: .init(identity: identity),
      proposal: proposal
    )
    #expect(controller.activeAnimationCount == 0)

    _ = renderer.render(
      animationTemporal005View(owner: "b", value: 3, opacity: 0.4),
      context: .init(identity: identity),
      proposal: proposal
    )
    withKnownIssue("A replacement owner does not establish a live value-animation baseline") {
      #expect(controller.activeAnimationCount == 1)
    }
  }
}

@MainActor
private func animationTemporal005View(owner: String, value: Int, opacity: Double) -> some View {
  Text("animation temporal 005")
    .opacity(opacity)
    .animation(.linear(duration: .seconds(4)), value: value)
    .id(owner)
}
