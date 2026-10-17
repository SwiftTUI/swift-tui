import Testing

@testable import SwiftTUICore

struct ModalFocusLifetimeTests {
  private func region(_ name: String, modal: [Identity]? = nil) -> FocusRegion {
    FocusRegion(
      identity: Identity(components: [name]),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)), modalFocusScopePath: modal)
  }

  @Test func emptyModalReplacementRetainsTheOriginalInvoker() {
    let first = region("first")
    let opener = region("opener")
    let tracker = FocusTracker(focusRegions: [first, opener])
    tracker.setFocus(to: opener.identity)
    let a = [Identity(components: ["A"])]
    let b = [Identity(components: ["B"])]
    tracker.updateRegions([], activeModalScopePath: a)
    #expect(tracker.modalRestorationDepth == 1)
    tracker.updateRegions([], activeModalScopePath: b)
    #expect(tracker.modalRestorationDepth == 1)
    tracker.updateRegions([first, opener], activeModalScopePath: nil)
    #expect(tracker.currentFocusIdentity == opener.identity)
    #expect(tracker.modalRestorationDepth == 0)
  }

  @Test func replacingANestedModalRetainsBothInvokerLifetimes() {
    let first = region("first")
    let opener = region("opener")
    let tracker = FocusTracker(focusRegions: [first, opener])
    tracker.setFocus(to: opener.identity)
    let a = [Identity(components: ["A"])]
    let b = a + [Identity(components: ["B"])]
    let c = a + [Identity(components: ["C"])]
    let innerFirst = region("innerFirst", modal: a)
    let innerOpener = region("innerOpener", modal: a)
    tracker.updateRegions([innerFirst, innerOpener], activeModalScopePath: a)
    tracker.setFocus(to: innerOpener.identity)
    tracker.updateRegions([], activeModalScopePath: b)
    tracker.updateRegions([], activeModalScopePath: c)
    #expect(tracker.modalRestorationDepth == 2)
    tracker.updateRegions([innerFirst, innerOpener], activeModalScopePath: a)
    #expect(tracker.currentFocusIdentity == innerOpener.identity)
    tracker.updateRegions([first, opener], activeModalScopePath: nil)
    #expect(tracker.currentFocusIdentity == opener.identity)
    #expect(tracker.modalRestorationDepth == 0)
  }

  @Test func suspendedPortalSiblingKeepsItsOwnInvoker() {
    let outer = region("outer")
    let tracker = FocusTracker(focusRegions: [outer])
    let a = [Identity(components: ["A"])]
    let b = [Identity(components: ["B"])]
    let inner = region("inner", modal: a)
    tracker.updateRegions([inner], activeModalScopePath: a, mountedModalScopePaths: [a])
    tracker.updateRegions([], activeModalScopePath: b, mountedModalScopePaths: [a, b])
    #expect(tracker.modalRestorationDepth == 2)
    tracker.updateRegions([inner], activeModalScopePath: a, mountedModalScopePaths: [a])
    #expect(tracker.currentFocusIdentity == inner.identity)
    tracker.updateRegions([outer], activeModalScopePath: nil, mountedModalScopePaths: [])
    #expect(tracker.currentFocusIdentity == outer.identity)
    #expect(tracker.modalRestorationDepth == 0)
  }

  @Test func modalReplacementPreservesExplicitlyClearedFocus() {
    let first = region("first")
    let tracker = FocusTracker(focusRegions: [first])
    tracker.clearFocus()
    let a = [Identity(components: ["A"])]
    let b = [Identity(components: ["B"])]
    tracker.updateRegions([region("a", modal: a)], activeModalScopePath: a)
    tracker.updateRegions([region("b", modal: b)], activeModalScopePath: b)
    tracker.updateRegions([first], activeModalScopePath: nil)
    #expect(tracker.currentFocusIdentity == nil)
    #expect(tracker.modalRestorationDepth == 0)
  }
}
