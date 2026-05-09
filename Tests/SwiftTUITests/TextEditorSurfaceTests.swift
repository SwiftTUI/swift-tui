import Testing

@testable import SwiftTUI
@testable import SwiftTUICore
@testable import SwiftTUIViews

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

  @Test("TextEditor inserts newlines at the moved caret")
  func textEditorInsertsNewlineAtMovedCaret() {
    final class Box {
      var value = "ac"
    }

    let box = Box()
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("MovedCaretTextEditor")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
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

    #expect(registry.dispatch(identity: identity, event: .arrowLeft))
    #expect(registry.dispatch(identity: identity, event: .return))
    #expect(registry.dispatch(identity: identity, event: .character("b")))
    #expect(box.value == "a\nbc")
  }

  @Test("TextEditor moves vertically through multiline text")
  func textEditorMovesVerticallyThroughMultilineText() {
    final class Box {
      var value = "ab\ncd"
    }

    let box = Box()
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("VerticalCaretTextEditor")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
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

    #expect(registry.dispatch(identity: identity, event: .arrowUp))
    #expect(registry.dispatch(identity: identity, event: .character("X")))
    #expect(box.value == "abX\ncd")
  }

  @Test("TextEditor handles word shortcuts and select all")
  func textEditorHandlesWordShortcutsAndSelectAll() {
    final class Box {
      var value = "hello world"
    }

    let box = Box()
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("ShortcutTextEditor")
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = DefaultRenderer().render(
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

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.arrowLeft, modifiers: .alt)))
    #expect(registry.dispatch(identity: identity, event: .character("X")))
    #expect(box.value == "hello Xworld")

    #expect(registry.dispatch(identity: identity, keyPress: KeyPress(.backspace, modifiers: .alt)))
    #expect(box.value == "hello world")

    #expect(
      registry.dispatch(identity: identity, keyPress: KeyPress(.character("a"), modifiers: .ctrl)))
    #expect(registry.dispatch(identity: identity, event: .character("Z")))
    #expect(box.value == "Z")
  }

  @Test("TextEditor renders focused range selection")
  func textEditorRendersFocusedRangeSelection() {
    final class Box {
      var value = "hello world"
    }

    let box = Box()
    let registry = LocalKeyHandlerRegistry()
    let identity = testIdentity("SelectedTextEditor")
    let renderer = DefaultRenderer()
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity

    _ = renderer.render(
      TextEditor(
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .frame(width: 16, height: 4),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(
      registry.dispatch(
        identity: identity,
        keyPress: KeyPress(.arrowLeft, modifiers: [.shift, .alt])
      )
    )

    let artifacts = renderer.render(
      TextEditor(
        text: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      )
      .id(identity)
      .frame(width: 16, height: 4),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(artifacts.rasterSurface.lines.joined(separator: "\n").contains("hello world"))
    #expect(!artifacts.rasterSurface.lines.joined(separator: "\n").contains("_"))
    #expect(reversedCharacters(in: artifacts.rasterSurface) == "world")
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

private func reversedCharacters(in surface: RasterSurface) -> String {
  surface.cells.flatMap { row in
    row.compactMap { cell -> Character? in
      guard !cell.isContinuation,
        cell.style?.emphasis.contains(.reverse) == true
      else {
        return nil
      }
      return cell.character
    }
  }.reduce(into: "") { partial, character in
    partial.append(character)
  }
}
