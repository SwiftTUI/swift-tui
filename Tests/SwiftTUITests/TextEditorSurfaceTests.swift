import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite
struct TextEditorSurfaceTests {
  @Test("TextEditor accepts multiline input within a scroll-safe chrome")
  func textEditorHandlesMultilineInputAndScrolling() {
    final class Box {
      var value = "Line 1\nLine 2\nLine 3\nLine 4"
    }

    let box = Box()
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("TextEditor")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    let focusedArtifacts = DefaultRenderer().render(
      TextEditor(
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .frame(width: 16, height: 5),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let focusedSurface = focusedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(focusedSurface.contains("Line 1"))
    #expect(focusedSurface.contains("Line 2"))
    #expect(focusedSurface.contains("Line 3"))

    #expect(registry.dispatch(identity: identity, event: .return))
    #expect(registry.dispatch(identity: identity, event: .character("A")))
    #expect(registry.dispatch(identity: identity, event: .backspace))
    #expect(box.value == "Line 1\nLine 2\nLine 3\nLine 4\n")

    let updatedArtifacts = DefaultRenderer().render(
      TextEditor(
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .frame(width: 16, height: 5),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    let updatedSurface = updatedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(updatedSurface.contains("Line 1"))
    #expect(updatedSurface.contains("Line 2"))
    #expect(updatedSurface.contains("Line 3"))
  }

  @Test("TextEditor keeps focused and unfocused chrome distinct")
  func textEditorFocusStateAffectsRendering() {
    let identity = testIdentity("FocusedTextEditor")
    var focusedEnvironment = EnvironmentValues()
    focusedEnvironment.focusedIdentity = identity

    let focusedSurface = DefaultRenderer().render(
      TextEditor(text: .constant(""))
        .id(identity)
        .frame(width: 10, height: 4),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: focusedEnvironment,
        applyEnvironmentValues: true
      )
    ).rasterSurface.lines.joined(separator: "\n")

    let unfocusedSurface = DefaultRenderer().render(
      TextEditor(text: .constant(""))
        .id(identity)
        .frame(width: 10, height: 4),
      context: .init(
        identity: testIdentity("Root")
      )
    ).rasterSurface.lines.joined(separator: "\n")

    #expect(focusedSurface.contains("_"))
    #expect(!unfocusedSurface.contains("_"))
    #expect(focusedSurface != unfocusedSurface)
  }
}
