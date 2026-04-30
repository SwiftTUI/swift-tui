import GIFEditorCore
import TerminalUI

/// Public root view of the editor. Owns one `EditorViewModel` for the
/// document's lifetime; everything below it renders from that model
/// and forwards user input back through it.
///
/// Phase 1 of the Photoshop redesign (see `REDESIGN.md`) lays out the
/// editor in a 3-region body sandwiched between a timeline strip and
/// a status strip:
///
/// ```
/// ┌──┬───────────────────────┬────────┐
/// │T │                       │ Color  │
/// │o │       canvas          │ Palette│
/// │o │                       │ Layers │
/// │l │                       │        │
/// ├──┴───────────────────────┴────────┤
/// │ timeline                          │
/// ├───────────────────────────────────┤
/// │ status                            │
/// └───────────────────────────────────┘
/// ```
///
/// The menu bar (Phase 2) and contextual options bar (Phase 4) land
/// above the body in subsequent phases.
public struct EditorView: View {
  // The view-model is a reference type, so we just hold it as an
  // @State (the Reference Box pattern). Mutating @MainActor methods on
  // it advance state in-place; we still mark the @State so the
  // framework treats this view as having local-owned state.
  @State private var model: EditorViewModel
  @State private var revision: Int = 0
  @State private var isHelpPresented = false
  @State private var showsToolDock = true
  @State private var showsRightPanel = true
  @State private var showsTimeline = true
  @State private var pixelGridMode: CanvasPixelGridMode = .verticalHalfBlock
  @State private var isResizeSheetPresented = false
  @State private var openMenu: MenuBarMenu?

  public init(document: GIFDocument) {
    _model = State(initialValue: EditorViewModel(document: document))
  }

  public var body: some View {
    // `revision` is read here so the framework's @State subscription
    // tracks it; bumping it via the bindings' `refresh` callback
    // forces a body re-evaluation against the (already-mutated)
    // model. A future @Observable adoption can drop this seam.
    _ = revision
    let model = self.model
    let refresh: @MainActor @Sendable () -> Void = { revision &+= 1 }
    let frameColors = model.document.flattenedColors(frameIndex: model.currentFrameIndex)
    let timelineFrames = (0..<model.document.frames.count).map { index in
      TimelineFrame(
        thumbnail: thumbnail(for: index),
        delayCentiseconds: model.document.frames[index].delayCentiseconds
      )
    }
    let primaryColor = model.document.palette[model.primaryColorIndex]
    let secondaryColor = model.document.palette[model.secondaryColorIndex]

    return ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        MenuBarView(
          openMenu: $openMenu,
          model: model,
          isHelpPresented: $isHelpPresented,
          showsToolDock: $showsToolDock,
          showsRightPanel: $showsRightPanel,
          showsTimeline: $showsTimeline,
          pixelGridMode: $pixelGridMode,
          isResizeSheetPresented: $isResizeSheetPresented,
          refresh: refresh
        )
        ToolOptionsBar(
          model: model,
          isHelpPresented: $isHelpPresented,
          refresh: refresh
        )
        HStack(alignment: .top, spacing: 1) {
          if showsToolDock {
            ToolboxView(
              tool: model.tool,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              model: model,
              refresh: refresh
            )
          }
          InteractiveCanvasView(
            size: model.document.size,
            cells: frameColors,
            model: model,
            refresh: refresh,
            mode: pixelGridMode
          )
          .applyFocusedEditorBindings(
            model: model,
            isHelpPresented: $isHelpPresented,
            refresh: refresh
          )
          if showsRightPanel {
            VStack(alignment: .leading, spacing: 0) {
              ColorPanelView(
                primaryColor: primaryColor,
                secondaryColor: secondaryColor
              )
              PaletteView(
                palette: model.document.palette,
                primaryIndex: model.primaryColorIndex,
                secondaryIndex: model.secondaryColorIndex,
                model: model,
                refresh: refresh
              )
              LayerListView(
                layers: model.currentFrame.layers,
                selectedIndex: model.currentLayerIndex,
                model: model,
                refresh: refresh
              )
            }
          }
        }
        if showsTimeline {
          Divider()
          TimelineView(
            frames: timelineFrames,
            currentFrameIndex: model.currentFrameIndex,
            model: model,
            refresh: refresh
          )
        }
        Divider()
        footer
      }

      if let openMenu {
        MenuBarDropdownView(
          menu: openMenu,
          openMenu: $openMenu,
          model: model,
          isHelpPresented: $isHelpPresented,
          showsToolDock: $showsToolDock,
          showsRightPanel: $showsRightPanel,
          showsTimeline: $showsTimeline,
          pixelGridMode: $pixelGridMode,
          isResizeSheetPresented: $isResizeSheetPresented,
          refresh: refresh
        )
        .offset(x: openMenu.dropdownOffset + 1, y: 1)
      }
    }
    .panel(id: "gifeditor")
    .applyFocusedEditorBindings(
      model: model,
      isHelpPresented: $isHelpPresented,
      refresh: refresh
    )
    .applyCursorBindings(model: model, refresh: refresh)
    .applyFrameBindings(model: model, refresh: refresh)
    .applyLayerBindings(model: model, refresh: refresh)
    .applyClipboardBindings(model: model, refresh: refresh)
    .applyHistoryBindings(model: model, refresh: refresh)
    .applyPaletteBindings(model: model, refresh: refresh)
    .applyFileBindings(
      model: model,
      isResizeSheetPresented: $isResizeSheetPresented,
      refresh: refresh
    )
    .applyTerminationHandling(model: model, refresh: refresh)
    .sheet("Keyboard help", isPresented: $isHelpPresented) {
      EditorHelpView()
    }
    .sheet("Resize canvas", isPresented: $isResizeSheetPresented) {
      ResizeCanvasSheetView(
        currentSize: model.document.size,
        onSelect: { size in
          model.resizeCanvas(to: size)
          isResizeSheetPresented = false
          refresh()
        },
        onCancel: {
          isResizeSheetPresented = false
        }
      )
    }
  }

  /// Single-row status strip at the bottom of the editor. Holds the
  /// transient `statusMessage` from the model on the left and the
  /// cursor / layer / brush-size / render-mode readout on the right.
  /// Document identity and dirty state live in the menu bar's
  /// trailing slot instead.
  private var footer: some View {
    HStack(spacing: 2) {
      Text(model.statusMessage.isEmpty ? "Press ? for help" : model.statusMessage)
        .foregroundStyle(.muted)
      Spacer(minLength: 1)
      Text(
        "[\(model.cursor.x),\(model.cursor.y)]  "
          + "L\(model.currentLayerIndex + 1)/\(model.currentFrame.layers.count)  "
          + "B\(model.brushSize)  half-cell"
      )
      .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
  }

  /// 8-cell-wide thumbnail per frame, sampled with nearest-neighbor.
  private func thumbnail(for frameIndex: Int) -> TimelineFrame.Thumbnail {
    let composited = model.document.flattenedColors(frameIndex: frameIndex)
    let srcSize = model.document.size
    let thumbWidth = 6
    let thumbHeight = 4
    var out: [EditorColor?] = []
    out.reserveCapacity(thumbWidth * thumbHeight)
    for ty in 0..<thumbHeight {
      for tx in 0..<thumbWidth {
        let sx = (tx * srcSize.width) / thumbWidth
        let sy = (ty * srcSize.height) / thumbHeight
        out.append(composited[sy * srcSize.width + sx])
      }
    }
    return TimelineFrame.Thumbnail(width: thumbWidth, height: thumbHeight, pixels: out)
  }
}
