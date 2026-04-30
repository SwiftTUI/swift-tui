import GIFEditorCore
import TerminalUI

/// Top-row menu bar — File / Edit / Layer / Select / Frame / View /
/// Help. Each dropdown opens from the editor-root overlay so opening or
/// closing a menu does not reflow the canvas, panels, or timeline.
/// Every menu item is a clickable `Button` that calls the same model
/// method as its keybinding.
///
/// Menu items without a backing model method or keybinding (e.g.
/// "New", "Open…", "About gifeditor") are intentionally absent —
/// skipping them keeps every visible item live (no grayed-out rows on
/// day one) and avoids advertising features that don't exist yet.
struct MenuBarView: View {
  @Binding var openMenu: MenuBarMenu?
  let model: EditorViewModel
  @Binding var isHelpPresented: Bool
  @Binding var showsToolDock: Bool
  @Binding var showsRightPanel: Bool
  @Binding var showsTimeline: Bool
  @Binding var pixelGridMode: CanvasPixelGridMode
  @Binding var isResizeSheetPresented: Bool
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      menuTrigger(.file)
      menuTrigger(.edit)
      menuTrigger(.layer)
      menuTrigger(.select)
      menuTrigger(.frame)
      menuTrigger(.view)
      menuTrigger(.help)
      Spacer(minLength: 1)
      Text(documentLabel).foregroundStyle(.muted)
      Text(model.isDirty ? "●" : "✓")
        .foregroundStyle(model.isDirty ? .warning : .success)
    }
    .frame(height: 1, alignment: .topLeading)
    .padding(.horizontal, 1)
  }

  // MARK: - Menus

  private func menuTrigger(_ menu: MenuBarMenu) -> some View {
    Button(menu.triggerTitle(isOpen: openMenu == menu)) {
      openMenu = openMenu == menu ? nil : menu
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private var documentLabel: String {
    if let path = model.document.path {
      return path.lastPathComponent
    }
    return "untitled"
  }
}

struct MenuBarDropdownView: View {
  let menu: MenuBarMenu
  @Binding var openMenu: MenuBarMenu?
  let model: EditorViewModel
  @Binding var isHelpPresented: Bool
  @Binding var showsToolDock: Bool
  @Binding var showsRightPanel: Bool
  @Binding var showsTimeline: Bool
  @Binding var pixelGridMode: CanvasPixelGridMode
  @Binding var isResizeSheetPresented: Bool
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      switch menu {
      case .file:
        menuItem("Save", action: refreshAfter(model.save))
        menuItem("Save As…", action: refreshAfter(model.saveAs))
        menuGap
        menuItem("Resize Canvas…") {
          isResizeSheetPresented = true
          refresh()
        }
      case .edit:
        menuItem("Undo", action: refreshAfter(model.undo))
          .disabled(!model.canUndo)
        menuItem("Redo", action: refreshAfter(model.redo))
          .disabled(!model.canRedo)
        menuGap
        menuItem("Copy", action: refreshAfter(model.copySelection))
        menuItem("Paste", action: refreshAfter(model.paste))
        menuGap
        menuItem("Clear Selection", action: refreshAfter(model.clearSelection))
      case .layer:
        menuItem("New Layer", action: refreshAfter(model.addLayer))
        menuItem("Delete Layer", action: refreshAfter(model.deleteCurrentLayer))
        menuGap
        menuItem("Toggle Visibility", action: refreshAfter(model.toggleCurrentLayerVisibility))
        menuItem("Layer Below", action: refreshAfter(model.selectLayerBelow))
        menuItem("Layer Above", action: refreshAfter(model.selectLayerAbove))
      case .select:
        menuItem("Clear Selection", action: refreshAfter(model.clearSelection))
        menuItem("Confirm Marquee", action: refreshAfter(model.applyToolAtCursor))
      case .frame:
        menuItem("New Frame", action: refreshAfter(model.insertBlankFrameAfterCurrent))
        menuItem("Duplicate Frame", action: refreshAfter(model.duplicateCurrentFrame))
        menuItem("Delete Frame", action: refreshAfter(model.deleteCurrentFrame))
        menuGap
        menuItem("Previous Frame", action: refreshAfter(model.previousFrame))
        menuItem("Next Frame", action: refreshAfter(model.nextFrame))
        menuGap
        menuItem("Increase Delay") {
          model.adjustCurrentFrameDelay(by: 10)
          refresh()
        }
        menuItem("Decrease Delay") {
          model.adjustCurrentFrameDelay(by: -10)
          refresh()
        }
        menuItem("Equalize Delays", action: refreshAfter(model.setAllFrameDelaysToCurrent))
      case .view:
        // Visibility toggles — narrow terminals can claim canvas space
        // back by hiding non-essential chrome.
        menuItem(checkmark(showsToolDock) + " Show Tool Dock") {
          showsToolDock.toggle()
          refresh()
        }
        menuItem(checkmark(showsRightPanel) + " Show Right Panel") {
          showsRightPanel.toggle()
          refresh()
        }
        menuItem(checkmark(showsTimeline) + " Show Timeline") {
          showsTimeline.toggle()
          refresh()
        }
        menuGap
        // Pixel grid mode — half-block doubles vertical resolution; full
        // cell makes each pixel a square of one terminal cell.
        menuItem(checkmark(pixelGridMode == .verticalHalfBlock) + " Half-block grid") {
          pixelGridMode = .verticalHalfBlock
          refresh()
        }
        menuItem(checkmark(pixelGridMode == .fullCell) + " Full-cell grid") {
          pixelGridMode = .fullCell
          refresh()
        }
        menuGap
        menuItem("Increase Brush Size", action: refreshAfter(model.increaseBrushSize))
        menuItem("Decrease Brush Size", action: refreshAfter(model.decreaseBrushSize))
        menuItem("Swap Primary/Secondary", action: refreshAfter(model.swapPrimaryAndSecondary))
      case .help:
        menuItem("Keyboard Shortcuts…") {
          isHelpPresented = true
          refresh()
        }
      }
    }
    .background {
      Rectangle().fill(.terminalSurfaceBackground)
    }
    .fixedSize(horizontal: true, vertical: true)
  }

  private func menuItem(
    _ title: String,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    Button(title) {
      action()
      openMenu = nil
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: true)
  }

  private var menuGap: some View {
    Text(" ")
      .foregroundStyle(.separator)
      .fixedSize(horizontal: true, vertical: true)
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

  /// Renders `✓` when `flag` is true, blank space otherwise. Aligns
  /// menu rows whether checked or not so toggling doesn't shift the
  /// label horizontally.
  private func checkmark(_ flag: Bool) -> String {
    flag ? "✓" : " "
  }
}

enum MenuBarMenu: CaseIterable, Equatable, Sendable {
  case file
  case edit
  case layer
  case select
  case frame
  case view
  case help

  var title: String {
    switch self {
    case .file: "File"
    case .edit: "Edit"
    case .layer: "Layer"
    case .select: "Select"
    case .frame: "Frame"
    case .view: "View"
    case .help: "Help"
    }
  }

  var triggerWidth: Int {
    title.count + 2
  }

  var dropdownOffset: Int {
    var offset = 0
    for candidate in Self.allCases {
      if candidate == self {
        return offset
      }
      offset += candidate.triggerWidth + 2
    }
    return offset
  }

  func triggerTitle(isOpen: Bool) -> String {
    title + " " + (isOpen ? "▴" : "▾")
  }
}
