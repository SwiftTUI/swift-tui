import GIFEditorCore
import TerminalUI

/// Top-row menu bar — File / Edit / Layer / Select / Frame / View /
/// Help. Each `Menu` opens an overlay (Blocker 1) so opening or
/// closing a menu does not reflow the canvas, panels, or timeline.
/// Every menu item is a clickable `Button` that calls the same model
/// method as its keybinding, and carries a `.systemHint(...)` showing
/// the shortcut hint (Blocker 2).
///
/// Menu items without a backing model method or keybinding (e.g.
/// "New", "Open…", "About gifeditor", the View-menu visibility
/// toggles) are intentionally absent in Phase 2 — they land as Phase
/// 3/5 work alongside their backing implementations. Skipping them
/// keeps every visible item live (no grayed-out rows on day one) and
/// avoids advertising features that don't exist yet.
struct MenuBarView: View {
  let model: EditorViewModel
  @Binding var isHelpPresented: Bool
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      fileMenu
      editMenu
      layerMenu
      selectMenu
      frameMenu
      viewMenu
      helpMenu
      Spacer(minLength: 1)
      Text(documentLabel).foregroundStyle(.muted)
      Text(model.isDirty ? "●" : "✓")
        .foregroundStyle(model.isDirty ? .warning : .success)
    }
    .padding(.horizontal, 1)
  }

  // MARK: - Menus

  private var fileMenu: some View {
    Menu("File") {
      Button("Save", action: refreshAfter(model.save))
        .systemHint("Ctrl+S")
      Button("Save As…", action: refreshAfter(model.saveAs))
        .systemHint("Alt+S")
      Divider()
      Button("Resize Canvas", action: refreshAfter(model.cycleCanvasSize))
        .systemHint("Ctrl+R")
    }
  }

  private var editMenu: some View {
    Menu("Edit") {
      Button("Undo", action: refreshAfter(model.undo))
        .systemHint("Ctrl+Z")
        .disabled(!model.canUndo)
      Button("Redo", action: refreshAfter(model.redo))
        .systemHint("Ctrl+Y")
        .disabled(!model.canRedo)
      Divider()
      Button("Copy", action: refreshAfter(model.copySelection))
        .systemHint("Ctrl+C")
      Button("Paste", action: refreshAfter(model.paste))
        .systemHint("Ctrl+V")
      Divider()
      Button("Clear Selection", action: refreshAfter(model.clearSelection))
        .systemHint("Esc")
    }
  }

  private var layerMenu: some View {
    Menu("Layer") {
      Button("New Layer", action: refreshAfter(model.addLayer))
        .systemHint("Alt+N")
      Button("Delete Layer", action: refreshAfter(model.deleteCurrentLayer))
        .systemHint("Alt+X")
      Divider()
      Button("Toggle Visibility", action: refreshAfter(model.toggleCurrentLayerVisibility))
        .systemHint("Alt+H")
      Button("Layer Below", action: refreshAfter(model.selectLayerBelow))
        .systemHint("Alt+J")
      Button("Layer Above", action: refreshAfter(model.selectLayerAbove))
        .systemHint("Alt+K")
    }
  }

  private var selectMenu: some View {
    Menu("Select") {
      Button("Clear Selection", action: refreshAfter(model.clearSelection))
        .systemHint("Esc")
      Button("Confirm Marquee", action: refreshAfter(model.applyToolAtCursor))
        .systemHint("Enter")
    }
  }

  private var frameMenu: some View {
    Menu("Frame") {
      Button("New Frame", action: refreshAfter(model.insertBlankFrameAfterCurrent))
        .systemHint("Ctrl+N")
      Button("Duplicate Frame", action: refreshAfter(model.duplicateCurrentFrame))
        .systemHint("Ctrl+D")
      Button("Delete Frame", action: refreshAfter(model.deleteCurrentFrame))
        .systemHint("Alt+D")
      Divider()
      Button("Previous Frame", action: refreshAfter(model.previousFrame))
        .systemHint("Alt+,")
      Button("Next Frame", action: refreshAfter(model.nextFrame))
        .systemHint("Alt+.")
      Divider()
      Button(
        "Increase Delay",
        action: refreshAfter { model.adjustCurrentFrameDelay(by: 10) }
      )
      .systemHint("Alt+=")
      Button(
        "Decrease Delay",
        action: refreshAfter { model.adjustCurrentFrameDelay(by: -10) }
      )
      .systemHint("Alt+-")
      Button("Equalize Delays", action: refreshAfter(model.setAllFrameDelaysToCurrent))
        .systemHint("Alt+0")
    }
  }

  private var viewMenu: some View {
    Menu("View") {
      Button(
        "Increase Brush Size",
        action: refreshAfter(model.increaseBrushSize)
      )
      .systemHint("]")
      Button(
        "Decrease Brush Size",
        action: refreshAfter(model.decreaseBrushSize)
      )
      .systemHint("[")
      Divider()
      Button("Swap Primary/Secondary", action: refreshAfter(model.swapPrimaryAndSecondary))
        .systemHint("x")
    }
  }

  private var helpMenu: some View {
    Menu("Help") {
      Button("Keyboard Shortcuts…") {
        isHelpPresented = true
        refresh()
      }
      .systemHint("?")
    }
  }

  // MARK: - Helpers

  /// Wraps a `() -> Void` model action in a closure that also calls
  /// `refresh()` afterward, matching the shape every keybinding uses.
  private func refreshAfter(
    _ action: @escaping @MainActor () -> Void
  ) -> @MainActor @Sendable () -> Void {
    let refresh = self.refresh
    return {
      action()
      refresh()
    }
  }

  private var documentLabel: String {
    if let path = model.document.path {
      return path.lastPathComponent
    }
    return "untitled"
  }
}
