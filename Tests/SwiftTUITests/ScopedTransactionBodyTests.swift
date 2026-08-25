import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage T0/T2 pins for the scoped `body:` forms (plan 2026-08-25-002 §6):
/// only the modifiers applied inside `body` see the scoped transaction, and
/// the placeholder's restore survives nested `resolveView` hops (F137).
@MainActor
@Suite("Scoped transaction bodies")
struct ScopedTransactionBodyTests {
  @Test(".animation(_:body:) animates the body's offset while the wrapped color snaps")
  func scopedAnimationAnimatesBodyOnly() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScopedAnimationRoot"),
      size: .init(width: 40, height: 6)
    ) {
      ScopedAnimationFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      try harness.clickText("go")
      _ = try harness.renderAfterExternalMutation()
    }

    let scopes = Set(controller.debugStateSnapshot().activeAnimationKeys.map(\.scope))
    #expect(scopes.contains(.property(.offset)), "the offset applied in body animates")
    #expect(
      !scopes.contains(.property(.foregroundShapeStyle)),
      "the color on the wrapped content snaps"
    )
  }

  @Test(
    ".transaction(_:body:) with disablesAnimations snaps the body while the wrapped offset animates"
  )
  func scopedTransactionSnapsBodyOnly() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScopedTransactionRoot"),
      size: .init(width: 40, height: 6)
    ) {
      ScopedDisableFixture()
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      try harness.clickText("go")
      _ = try harness.renderAfterExternalMutation()
    }

    let scopes = Set(controller.debugStateSnapshot().activeAnimationKeys.map(\.scope))
    #expect(scopes.contains(.property(.offset)), "the wrapped offset animates with the outer scope")
    #expect(
      !scopes.contains(.property(.opacity)),
      "the opacity applied in body snaps under the scoped disablesAnimations"
    )
  }

  @Test("the placeholder restore and the scoped edit both survive nested resolveView hops")
  func placeholderRestoreSurvivesDescent() throws {
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .milliseconds(300))
    let rootIdentity = testIdentity("ScopedDescentRoot")

    func probe(shifted: Bool) -> some View {
      VStack {
        VStack {
          Text("Inner")
        }
      }
      .animation(animation) { placeholder in
        VStack {
          VStack {
            placeholder
            Text("Body")
          }
        }
        .offset(x: shifted ? 4 : 0, y: 0)
      }
    }

    _ = renderer.render(probe(shifted: false), context: ResolveContext(identity: rootIdentity))
    let second = renderer.render(
      probe(shifted: true),
      context: ResolveContext(identity: rootIdentity)
    )

    let inner = try #require(second.resolvedTree.descendant(withText: "Inner"))
    #expect(
      inner.transactionSnapshot.animationRequest == .inherit,
      "the wrapped grandchild keeps the outer (inherited) transaction"
    )
    let body = try #require(second.resolvedTree.descendant(withText: "Body"))
    guard case .animate = body.transactionSnapshot.animationRequest else {
      Issue.record(
        "body grandchild carries \(String(describing: body.transactionSnapshot.animationRequest)) instead of the scoped .animate request"
      )
      return
    }
  }
}

// MARK: - Fixtures

@MainActor
private struct ScopedAnimationFixture: View {
  @State private var offsetX = 0
  @State private var accent = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        offsetX += 5
        accent.toggle()
      }
      Text("subject")
        .foregroundStyle(accent ? Color.red : Color.blue)
        .animation(.linear(duration: .seconds(2))) { text in
          text.offset(x: offsetX, y: 0)
        }
    }
  }
}

@MainActor
private struct ScopedDisableFixture: View {
  @State private var offsetX = 0
  @State private var faded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("go") {
        withAnimation(.linear(duration: .seconds(2))) {
          offsetX += 5
          faded.toggle()
        }
      }
      Text("subject")
        .offset(x: offsetX, y: 0)
        .transaction({ $0.disablesAnimations = true }) { text in
          text.opacity(faded ? 0.2 : 1.0)
        }
    }
  }
}

extension ResolvedNode {
  fileprivate func descendant(withText text: String) -> ResolvedNode? {
    if drawPayload == .text(text) {
      return self
    }
    for child in children {
      if let match = child.descendant(withText: text) {
        return match
      }
    }
    return nil
  }
}
