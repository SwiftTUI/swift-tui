import GIFEditorCore
import TerminalUI

/// Focused-key and key-command chains for the editor.
///
/// `keyCommand` is only callable on a view that conforms to
/// `ActionScope` (e.g. one that has been wrapped with `.panel(id:)`),
/// so we can't compose these as `ViewModifier`s — `Content` in a
/// `ViewModifier.body` is a plain `View` without the action-scope
/// conformance. Instead we expose generic functions that take an
/// `ActionScope`-conforming view and return one. The editor view
/// chains them onto its panel: `panel.applyToolBindings(...)
/// .applyCursorBindings(...)`.
extension View where Self: ActionScope & Sendable {
  func applyToolBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .onKeyPress(.character("p")) { _ in
        model.selectTool(.pen)
        refresh()
        return .handled
      }
      .onKeyPress(.character("e")) { _ in
        model.selectTool(.eraser)
        refresh()
        return .handled
      }
      .onKeyPress(.character("b")) { _ in
        model.selectTool(.fill)
        refresh()
        return .handled
      }
      .onKeyPress(.character("g")) { _ in
        model.selectTool(.gradient)
        refresh()
        return .handled
      }
      .onKeyPress(.character("m")) { _ in
        model.selectTool(.marquee)
        refresh()
        return .handled
      }
      .onKeyPress(.character("i")) { _ in
        model.selectTool(.eyedropper)
        refresh()
        return .handled
      }
      .onKeyPress(.character("x")) { _ in
        model.swapPrimaryAndSecondary()
        refresh()
        return .handled
      }
      .onKeyPress(.space) { _ in
        model.applyToolAtCursor()
        refresh()
        return .handled
      }
      .onKeyPress(.return) { _ in
        model.applyToolAtCursor()
        refresh()
        return .handled
      }
      .onKeyPress(.escape) { _ in
        model.clearSelection()
        refresh()
        return .handled
      }
  }

  func applyCursorBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Cursor left", key: .arrowLeft, modifiers: .shift) {
        model.moveCursor(dx: -1, dy: 0)
        refresh()
      }
      .keyCommand("Cursor right", key: .arrowRight, modifiers: .shift) {
        model.moveCursor(dx: 1, dy: 0)
        refresh()
      }
      .keyCommand("Cursor up", key: .arrowUp, modifiers: .shift) {
        model.moveCursor(dx: 0, dy: -1)
        refresh()
      }
      .keyCommand("Cursor down", key: .arrowDown, modifiers: .shift) {
        model.moveCursor(dx: 0, dy: 1)
        refresh()
      }
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
      .keyCommand("Cursor h", key: .character("h"), modifiers: .shift) {
        model.moveCursor(dx: -1, dy: 0)
        refresh()
      }
      .keyCommand("Cursor j", key: .character("j"), modifiers: .shift) {
        model.moveCursor(dx: 0, dy: 1)
        refresh()
      }
      .keyCommand("Cursor k", key: .character("k"), modifiers: .shift) {
        model.moveCursor(dx: 0, dy: -1)
        refresh()
      }
      .keyCommand("Cursor l", key: .character("l"), modifiers: .shift) {
        model.moveCursor(dx: 1, dy: 0)
        refresh()
      }
  }

  func applyFrameBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Previous frame", key: .character(","), modifiers: .ctrl) {
        model.previousFrame()
        refresh()
      }
      .keyCommand("Next frame", key: .character("."), modifiers: .ctrl) {
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
      .keyCommand(
        "Delete frame", key: .character("d"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.deleteCurrentFrame()
        refresh()
      }
      .keyCommand("Decrease delay", key: .character("["), modifiers: .ctrl) {
        model.adjustCurrentFrameDelay(by: -10)
        refresh()
      }
      .keyCommand("Increase delay", key: .character("]"), modifiers: .ctrl) {
        model.adjustCurrentFrameDelay(by: 10)
        refresh()
      }
      .keyCommand("Equalize delays", key: .character("0"), modifiers: .ctrl) {
        model.setAllFrameDelaysToCurrent()
        refresh()
      }
  }

  func applyLayerBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand(
        "New layer", key: .character("n"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.addLayer()
        refresh()
      }
      .keyCommand(
        "Layer below", key: .character("j"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.selectLayerBelow()
        refresh()
      }
      .keyCommand(
        "Layer above", key: .character("k"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.selectLayerAbove()
        refresh()
      }
      .keyCommand(
        "Toggle layer", key: .character("h"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.toggleCurrentLayerVisibility()
        refresh()
      }
      .keyCommand(
        "Delete layer", key: .character("x"),
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
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

  func applyPaletteBindings(
    model: EditorViewModel,
    refresh: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    self
      .keyCommand("Slot 1", key: .character("1"), modifiers: .ctrl) {
        model.setPrimaryColor(1)
        refresh()
      }
      .keyCommand("Slot 2", key: .character("2"), modifiers: .ctrl) {
        model.setPrimaryColor(2)
        refresh()
      }
      .keyCommand("Slot 3", key: .character("3"), modifiers: .ctrl) {
        model.setPrimaryColor(3)
        refresh()
      }
      .keyCommand("Slot 4", key: .character("4"), modifiers: .ctrl) {
        model.setPrimaryColor(4)
        refresh()
      }
      .keyCommand("Slot 5", key: .character("5"), modifiers: .ctrl) {
        model.setPrimaryColor(5)
        refresh()
      }
      .keyCommand("Slot 6", key: .character("6"), modifiers: .ctrl) {
        model.setPrimaryColor(6)
        refresh()
      }
      .keyCommand("Slot 7", key: .character("7"), modifiers: .ctrl) {
        model.setPrimaryColor(7)
        refresh()
      }
      .keyCommand("Slot 8", key: .character("8"), modifiers: .ctrl) {
        model.setPrimaryColor(8)
        refresh()
      }
      .keyCommand("Slot 9", key: .character("9"), modifiers: .ctrl) {
        model.setPrimaryColor(9)
        refresh()
      }
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
        modifiers: EventModifiers([.ctrl, .shift])
      ) {
        model.saveAs()
        refresh()
      }
      .keyCommand("Resize canvas", key: .character("r"), modifiers: .ctrl) {
        let progression = [16, 24, 32, 48, 64]
        let current = model.document.size.width
        let next = progression.first { $0 > current } ?? progression[0]
        model.resizeCanvas(to: PixelSize(width: next, height: next))
        refresh()
      }
  }
}
