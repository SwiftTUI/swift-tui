import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextInputRuntimeIntegrationTests {
  @Test("TextField key press dispatch edits around a moved caret")
  func textFieldKeyPressDispatchEditsAroundMovedCaret() {
    final class TextBox {
      var value = "ac"
    }

    let box = TextBox()
    let identity = testIdentity("RuntimeTextField")
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
      TextField(
        "Name",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("b"))))
    #expect(box.value == "abc")
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowRight)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("d"))))
    #expect(box.value == "abcd")
  }

  @Test("SecureField key press dispatch edits text while rendering a masked value")
  func secureFieldKeyPressDispatchEditsWhileMasked() {
    final class SecretBox {
      var value = "ac"
    }

    let box = SecretBox()
    let identity = testIdentity("RuntimeSecureField")
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft)))
    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.character("b"))))
    #expect(box.value == "abc")

    let artifacts = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        applyEnvironmentValues: true
      )
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("•"))
    #expect(!surface.contains("abc"))
    #expect(!surface.contains("Password"))
  }
}
