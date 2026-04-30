import GIFEditorCore
import TerminalUI

extension View {
  func applyFocusedEditorBindings(
    model: EditorViewModel,
    isHelpPresented: Binding<Bool>,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> ModifiedContent<Self, KeyPressModifier> {
    onKeyPress(.any) { keyPress in
      guard keyPress.modifiers.isEmpty else {
        return .ignored
      }

      guard
        handleFocusedEditorKey(
          keyPress.key,
          model: model,
          isHelpPresented: isHelpPresented
        )
      else {
        return .ignored
      }

      refresh()
      return .handled
    }
  }
}

/// Focused-key and key-command chains for the editor.
///
/// `keyCommand` is only callable on a view that conforms to
/// `ActionScope` (e.g. one that has been wrapped with `.panel(id:)`),
/// so we can't compose these as `ViewModifier`s — `Content` in a
/// `ViewModifier.body` is a plain `View` without the action-scope
/// conformance. Instead we expose generic functions that take an
/// `ActionScope`-conforming view and return one. The editor view
/// chains modifier-bearing commands onto its panel, while bare focused
/// keys are also applied to the focusable canvas.
extension View where Self: ActionScope & Sendable {
  func applyCursorBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Jump left", key: .arrowLeft, modifiers: .ctrl) {
        model.moveCursor(dx: -8, dy: 0)
        refresh()
      }
      .keyCommand("Jump right", key: .arrowRight, modifiers: .ctrl) {
        model.moveCursor(dx: 8, dy: 0)
        refresh()
      }
      .keyCommand("Jump up", key: .arrowUp, modifiers: .ctrl) {
        model.moveCursor(dx: 0, dy: -8)
        refresh()
      }
      .keyCommand("Jump down", key: .arrowDown, modifiers: .ctrl) {
        model.moveCursor(dx: 0, dy: 8)
        refresh()
      }
  }

  func applyFrameBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Previous frame", key: .character(","), modifiers: .alt) {
        model.previousFrame()
        refresh()
      }
      .keyCommand("Next frame", key: .character("."), modifiers: .alt) {
        model.nextFrame()
        refresh()
      }
      .keyCommand("New frame", key: .character("n"), modifiers: .ctrl) {
        model.insertBlankFrameAfterCurrent()
        refresh()
      }
      .keyCommand("Duplicate frame", key: .character("d"), modifiers: .ctrl) {
        model.duplicateCurrentFrame()
        refresh()
      }
      .keyCommand("Delete frame", key: .character("d"), modifiers: .alt) {
        model.deleteCurrentFrame()
        refresh()
      }
      .keyCommand("Decrease delay", key: .character("-"), modifiers: .alt) {
        model.adjustCurrentFrameDelay(by: -10)
        refresh()
      }
      .keyCommand("Increase delay", key: .character("="), modifiers: .alt) {
        model.adjustCurrentFrameDelay(by: 10)
        refresh()
      }
      .keyCommand("Equalize delays", key: .character("0"), modifiers: .alt) {
        model.setAllFrameDelaysToCurrent()
        refresh()
      }
  }

  func applyLayerBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("New layer", key: .character("n"), modifiers: .alt) {
        model.addLayer()
        refresh()
      }
      .keyCommand("Layer below", key: .character("j"), modifiers: .alt) {
        model.selectLayerBelow()
        refresh()
      }
      .keyCommand("Layer above", key: .character("k"), modifiers: .alt) {
        model.selectLayerAbove()
        refresh()
      }
      .keyCommand("Toggle layer", key: .character("h"), modifiers: .alt) {
        model.toggleCurrentLayerVisibility()
        refresh()
      }
      .keyCommand("Delete layer", key: .character("x"), modifiers: .alt) {
        model.deleteCurrentLayer()
        refresh()
      }
  }

  func applyClipboardBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Copy", key: .character("c"), modifiers: .ctrl) {
        model.copySelection()
        refresh()
      }
      .keyCommand("Paste", key: .character("v"), modifiers: .ctrl) {
        model.paste()
        refresh()
      }
  }

  func applyHistoryBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Undo", key: .character("z"), modifiers: .ctrl) {
        model.undo()
        refresh()
      }
      .keyCommand("Redo", key: .character("y"), modifiers: .ctrl) {
        model.redo()
        refresh()
      }
  }

  func applyPaletteBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Secondary 1", key: .character("1"), modifiers: .alt) {
        model.setSecondaryColor(1)
        refresh()
      }
      .keyCommand("Secondary 2", key: .character("2"), modifiers: .alt) {
        model.setSecondaryColor(2)
        refresh()
      }
      .keyCommand("Secondary 3", key: .character("3"), modifiers: .alt) {
        model.setSecondaryColor(3)
        refresh()
      }
      .keyCommand("Secondary 4", key: .character("4"), modifiers: .alt) {
        model.setSecondaryColor(4)
        refresh()
      }
      .keyCommand("Secondary 5", key: .character("5"), modifiers: .alt) {
        model.setSecondaryColor(5)
        refresh()
      }
      .keyCommand("Secondary 6", key: .character("6"), modifiers: .alt) {
        model.setSecondaryColor(6)
        refresh()
      }
      .keyCommand("Secondary 7", key: .character("7"), modifiers: .alt) {
        model.setSecondaryColor(7)
        refresh()
      }
      .keyCommand("Secondary 8", key: .character("8"), modifiers: .alt) {
        model.setSecondaryColor(8)
        refresh()
      }
      .keyCommand("Secondary 9", key: .character("9"), modifiers: .alt) {
        model.setSecondaryColor(9)
        refresh()
      }
  }

  func applyFileBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {
        model.save()
        refresh()
      }
      .keyCommand(
        "Save As", key: .character("s"),
        modifiers: .alt
      ) {
        model.saveAs()
        refresh()
      }
      .keyCommand("Resize canvas", key: .character("r"), modifiers: .ctrl) {
        let progression = [16, 24, 32, 48, 64]
        let current = model.document.size.width
        let next = progression.first { $0 > current } ?? progression[0]
        model.resizeCanvas(to: GIFEditorCore.PixelSize(width: next, height: next))
        refresh()
      }
  }

  func applyTerminationHandling(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    onTerminationRequest { _ in
      if model.isDirty {
        model.save()
        refresh()
      }
      return .allow
    }
  }
}

@MainActor
private func handleFocusedEditorKey(
  _ key: KeyEvent,
  model: EditorViewModel,
  isHelpPresented: Binding<Bool>
) -> Bool {
  switch key {
  case .character("?"):
    isHelpPresented.wrappedValue = true
  case .character("p"):
    model.selectTool(.pen)
  case .character("e"):
    model.selectTool(.eraser)
  case .character("b"):
    model.selectTool(.fill)
  case .character("g"):
    model.selectTool(.gradient)
  case .character("m"):
    model.selectTool(.marquee)
  case .character("i"):
    model.selectTool(.eyedropper)
  case .character("x"):
    model.swapPrimaryAndSecondary()
  case .character("["):
    model.decreaseBrushSize()
  case .character("]"):
    model.increaseBrushSize()
  case .space, .return:
    model.applyToolAtCursor()
  case .escape:
    model.clearSelection()
  case .arrowLeft, .character("h"):
    model.moveCursor(dx: -1, dy: 0)
  case .arrowRight, .character("l"):
    model.moveCursor(dx: 1, dy: 0)
  case .arrowUp, .character("k"):
    model.moveCursor(dx: 0, dy: -1)
  case .arrowDown, .character("j"):
    model.moveCursor(dx: 0, dy: 1)
  case .character("1"):
    model.setPrimaryColor(1)
  case .character("2"):
    model.setPrimaryColor(2)
  case .character("3"):
    model.setPrimaryColor(3)
  case .character("4"):
    model.setPrimaryColor(4)
  case .character("5"):
    model.setPrimaryColor(5)
  case .character("6"):
    model.setPrimaryColor(6)
  case .character("7"):
    model.setPrimaryColor(7)
  case .character("8"):
    model.setPrimaryColor(8)
  case .character("9"):
    model.setPrimaryColor(9)
  default:
    return false
  }
  return true
}
