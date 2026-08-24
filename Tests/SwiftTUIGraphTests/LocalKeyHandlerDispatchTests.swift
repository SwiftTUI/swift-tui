import Testing

@testable import SwiftTUIGraph

/// Pins the dispatch contract between the two handler generations: the
/// legacy `KeyEvent` fallback carries no modifier state, so a modified
/// press must never reach it. Before this guard, a `Ctrl+C` declined by a
/// text input's `KeyPress` handler (collapsed selection — nothing to copy)
/// fell through to the fallback as a bare `.character("c")`, which inserted
/// a literal "c" and claimed the key the handler had just declined —
/// swallowing the default exit chord under edit focus.
@MainActor
@Suite("LocalKeyHandlerRegistry dispatch")
struct LocalKeyHandlerDispatchTests {
  @Test("a modified press declined by the KeyPress handler never reaches the KeyEvent fallback")
  func modifiedPressSkipsKeyEventFallback() {
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("Editor")
    var fallbackKeys: [KeyEvent] = []
    registry.register(identity: identity) { event in
      fallbackKeys.append(event)
      return true
    }
    registry.register(identity: identity) { (keyPress: KeyPress) in
      keyPress.modifiers.isEmpty
    }

    let declined = registry.dispatch(
      identity: identity,
      keyPress: KeyPress(.character("c"), modifiers: .ctrl)
    )
    #expect(!declined)
    #expect(fallbackKeys.isEmpty)

    let bare = registry.dispatch(
      identity: identity,
      keyPress: KeyPress(.character("x"))
    )
    #expect(bare)
  }

  @Test("an unmodified press still falls back to the KeyEvent handler when declined")
  func unmodifiedPressReachesKeyEventFallback() {
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("Fallback")
    var fallbackKeys: [KeyEvent] = []
    registry.register(identity: identity) { event in
      fallbackKeys.append(event)
      return true
    }
    registry.register(identity: identity) { (_: KeyPress) in
      false
    }

    let handled = registry.dispatch(
      identity: identity,
      keyPress: KeyPress(.character("q"))
    )
    #expect(handled)
    #expect(fallbackKeys == [.character("q")])
  }
}
