import Testing

@testable import SwiftTUIGraph

/// Pins the key-press-stack omission from frame-drop eligibility in
/// executable form (F107): key-press handler stacks are deliberately absent
/// from `LocalKeyHandlerRegistry.activeFrameDropEligibilityBlocker` — parity
/// with the pre-unification fan-out — and until this suite only a comment
/// enforced it, so a future "helpful" fix could silently change frame-drop
/// behavior in either direction.
@MainActor
@Suite("Frame-drop eligibility blockers")
struct FrameDropEligibilityBlockerTests {
  @Test("a key-press-only registration does not block frame drops (pinned omission)")
  func keyPressOnlyRegistrationDoesNotBlock() {
    let registry = LocalKeyHandlerRegistry()
    #expect(registry.activeFrameDropEligibilityBlocker == nil)

    registry.register(identity: testIdentity("Root", "Field"), keyPressHandler: { _ in false })
    #expect(
      registry.activeFrameDropEligibilityBlocker == nil,
      "key-press stacks are deliberately absent from the blocker check"
    )
  }

  @Test("a bare key handler blocks frame drops")
  func bareKeyHandlerBlocks() {
    let registry = LocalKeyHandlerRegistry()
    registry.register(identity: testIdentity("Root", "Field"), handler: { _ in false })
    #expect(registry.activeFrameDropEligibilityBlocker == .handlerInstallations)
  }

  @Test("a paste handler blocks frame drops")
  func pasteHandlerBlocks() {
    let registry = LocalKeyHandlerRegistry()
    registry.register(identity: testIdentity("Root", "Field"), pasteHandler: { _ in false })
    #expect(registry.activeFrameDropEligibilityBlocker == .handlerInstallations)
  }
}
