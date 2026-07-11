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
