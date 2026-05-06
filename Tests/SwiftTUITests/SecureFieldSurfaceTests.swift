import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct SecureFieldSurfaceTests {
  @Test(
    "SecureField shows its prompt when idle, masks entered text, and mutates through local key input"
  )
  func secureFieldHandlesPromptMaskingAndKeyInput() {
    final class SecretBox {
      var value = ""
    }

    let box = SecretBox()
    let registry = LocalKeyHandlerRegistry()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("SecretField")

    let focusedArtifacts = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(testIdentity("SecretField"))
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let promptArtifacts = DefaultRenderer().render(
      SecureField("Password", text: .constant(""))
        .textFieldStyle(.plain),
      context: .init(identity: testIdentity("PromptField"))
    )

    #expect(
      promptArtifacts.rasterSurface.lines.joined(separator: "\n").contains("Password")
    )
    #expect(focusedArtifacts.rasterSurface.lines.joined(separator: "\n").contains("_"))

    #expect(registry.dispatch(identity: testIdentity("SecretField"), event: .character("h")))
    #expect(box.value == "h")
    #expect(registry.dispatch(identity: testIdentity("SecretField"), event: .character("u")))
    #expect(box.value == "hu")
    #expect(registry.dispatch(identity: testIdentity("SecretField"), event: .backspace))
    #expect(box.value == "h")

    let updatedArtifacts = DefaultRenderer().render(
      SecureField(
        "Password",
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(testIdentity("SecretField"))
      .textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let updatedSurface = updatedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(updatedSurface.contains("•"))
    #expect(!updatedSurface.contains("h"))
    #expect(!updatedSurface.contains("Password"))
  }

  @Test("SecureField edits at the moved caret while keeping rendered text masked")
  func secureFieldEditsAtMovedCaretWhileMasked() {
    final class SecretBox {
      var value = "ac"
    }

    let box = SecretBox()
    let identity = testIdentity("MovedCaretSecretField")
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

    #expect(registry.dispatch(identity: identity, event: .arrowLeft))
    #expect(registry.dispatch(identity: identity, event: .character("b")))
    #expect(box.value == "abc")

    let updatedArtifacts = DefaultRenderer().render(
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
    let surface = updatedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("•"))
    #expect(!surface.contains("abc"))
    #expect(!surface.contains("Password"))
  }

  @Test("SecureField builder labels remain visible while the secret stays masked")
  func secureFieldBuilderLabelsStayVisible() {
    let artifacts = DefaultRenderer().render(
      SecureField(
        text: .constant("swordfish"),
        prompt: Text("Password")
      ) {
        Text("Account password")
      }
      .textFieldStyle(.plain),
      context: .init(identity: testIdentity("BuilderField"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Account password"))
    #expect(surface.contains("•"))
    #expect(!surface.contains("swordfish"))
  }
}
