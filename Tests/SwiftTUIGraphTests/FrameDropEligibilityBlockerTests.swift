import Testing

@testable import SwiftTUIGraph

/// Pins frame-drop eligibility blocking for the key-handler registry in
/// executable form. History: F107 pinned key-press stacks as deliberately
/// ABSENT from `activeFrameDropEligibilityBlocker` — parity with the
/// pre-unification fan-out, whose blocking population was the legacy bare
/// `KeyEvent` generation (every interactive control registered there). That
/// generation is deleted and its population now registers key-press
/// handlers, so the blocker follows it: without this flip the controls
/// would have silently LOST their drop protection — the exact silent
/// behavior change F107 existed to prevent, in the dangerous direction.
@MainActor
@Suite("Frame-drop eligibility blockers")
struct FrameDropEligibilityBlockerTests {
  @Test("a key-press registration blocks frame drops (F107 superseded with the legacy strand)")
  func keyPressRegistrationBlocks() {
    let registry = LocalKeyHandlerRegistry()
    #expect(registry.activeFrameDropEligibilityBlocker == nil)

    registry.register(identity: testIdentity("Root", "Field"), keyPressHandler: { _ in false })
    #expect(registry.activeFrameDropEligibilityBlocker == .handlerInstallations)
  }

  @Test("a paste handler blocks frame drops")
  func pasteHandlerBlocks() {
    let registry = LocalKeyHandlerRegistry()
    registry.register(identity: testIdentity("Root", "Field"), pasteHandler: { _ in false })
    #expect(registry.activeFrameDropEligibilityBlocker == .handlerInstallations)
  }
}
