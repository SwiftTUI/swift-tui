import Testing

@_spi(Testing) @testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite("Key press modifier")
struct KeyPressModifierTests {
  @Test("onKeyPress handles exact modifier-less keys")
  func onKeyPressHandlesModifierLessKeys() {
    final class Recorder {
      var events: [KeyPress] = []
    }

    let recorder = Recorder()
    let registry = LocalKeyHandlerRegistry()

    _ = DefaultRenderer().render(
      Text("Canvas")
        .id(testIdentity("Canvas"))
        .onKeyPress(.character("p")) { keyPress in
          recorder.events.append(keyPress)
          return .handled
        },
      context: .init(
        identity: testIdentity("Root"),
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      registry.dispatch(
        identity: testIdentity("Canvas"),
        keyPress: KeyPress(.character("p"))
      )
    )
    #expect(
      !registry.dispatch(
        identity: testIdentity("Canvas"),
        keyPress: KeyPress(.character("p"), modifiers: .shift)
      )
    )
    #expect(recorder.events == [KeyPress(.character("p"))])
  }

  @Test("onKeyPress chains handlers and propagates ignored matches")
  func onKeyPressChainsHandlers() {
    final class Recorder {
      var events: [String] = []
    }

    let recorder = Recorder()
    let registry = LocalKeyHandlerRegistry()

    _ = DefaultRenderer().render(
      Text("Canvas")
        .id(testIdentity("Canvas"))
        .onKeyPress(.character("x")) { _ in
          recorder.events.append("inner")
          return .handled
        }
        .onKeyPress(.character("x")) { _ in
          recorder.events.append("outer")
          return .ignored
        },
      context: .init(
        identity: testIdentity("Root"),
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      registry.dispatch(
        identity: testIdentity("Canvas"),
        keyPress: KeyPress(.character("x"))
      )
    )
    #expect(recorder.events == ["outer", "inner"])
  }
}
