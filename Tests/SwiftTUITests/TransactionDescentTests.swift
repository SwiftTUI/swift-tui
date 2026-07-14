import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F137 — authored transactions must survive descent. The frame-input
/// refresh (`applyingCurrentFrameResolveInputs`) stamped the frame-root
/// transaction over every nested `resolveView`, so a `.animation(_:value:)`
/// request reached only the subtree ROOTS (via a post-hoc re-stamp) and
/// grandchildren carried the inherited frame transaction.
@MainActor
@Suite
struct TransactionDescentTests {
  @Test("value animation request reaches grandchild snapshots")
  func valueAnimationRequestReachesGrandchildren() throws {
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .milliseconds(300))
    let rootIdentity = testIdentity("TransactionDescentRoot")

    func probe(shifted: Bool) -> some View {
      VStack {
        VStack {
          Text("Leaf")
        }
      }
      .animation(animation, value: shifted)
    }

    _ = renderer.render(
      probe(shifted: false),
      context: ResolveContext(identity: rootIdentity)
    )
    let second = renderer.render(
      probe(shifted: true),
      context: ResolveContext(identity: rootIdentity)
    )

    let leaf = try #require(second.resolvedTree.descendant(withText: "Leaf"))
    let request = leaf.transactionSnapshot.animationRequest
    guard case .animate = request else {
      Issue.record(
        "grandchild snapshot carries \(String(describing: request)) instead of the authored .animate request"
      )
      return
    }
  }

  @Test("an inner transaction edit wins below its own modifier")
  func innerTransactionEditWins() throws {
    let renderer = DefaultRenderer()
    let animation = Animation.linear(duration: .milliseconds(300))
    let rootIdentity = testIdentity("TransactionDescentInnerRoot")

    func probe(shifted: Bool) -> some View {
      VStack {
        VStack {
          Text("Still")
            .transaction { $0.disablesAnimations = true }
        }
      }
      .animation(animation, value: shifted)
    }

    _ = renderer.render(
      probe(shifted: false),
      context: ResolveContext(identity: rootIdentity)
    )
    let second = renderer.render(
      probe(shifted: true),
      context: ResolveContext(identity: rootIdentity)
    )

    let leaf = try #require(second.resolvedTree.descendant(withText: "Still"))
    #expect(leaf.transactionSnapshot.animationRequest == .disabled)
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
