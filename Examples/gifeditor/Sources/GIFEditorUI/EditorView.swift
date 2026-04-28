import GIFEditorCore
import TerminalUI

/// Public root view of the editor. Owns one `EditorViewModel` for the
/// document's lifetime; everything below it renders from that model
/// and forwards user input back through it.
public struct EditorView: View {
  // The view-model is a reference type, so we just hold it as an
  // @State (the Reference Box pattern). Mutating @MainActor methods on
  // it advance state in-place; we still mark the @State so the
  // framework treats this view as having local-owned state.
  @State private var model: EditorViewModel
  @State private var revision: Int = 0

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

    return VStack(alignment: .leading, spacing: 0) {
      headerRow
      Divider()
      HStack(alignment: .top, spacing: 1) {
        ToolboxView(
          tool: model.tool,
          pendingMarqueeAnchor: model.pendingMarqueeAnchor,
          pendingGradientAnchor: model.pendingGradientAnchor
        )
        VStack(alignment: .leading, spacing: 0) {
          CanvasView(
            size: model.document.size,
            cells: frameColors,
            cursor: model.cursor,
            selection: model.selection,
            pendingMarqueeAnchor: model.pendingMarqueeAnchor,
            pendingGradientAnchor: model.pendingGradientAnchor
          )
          TimelineView(
            frames: timelineFrames,
            currentFrameIndex: model.currentFrameIndex
          )
        }
        VStack(alignment: .leading, spacing: 0) {
          PaletteView(
            palette: model.document.palette,
            primaryIndex: model.primaryColorIndex,
            secondaryIndex: model.secondaryColorIndex
          )
          LayerListView(
            layers: model.currentFrame.layers,
            selectedIndex: model.currentLayerIndex
          )
        }
      }
      Divider()
      footer
    }
    .panel(id: "gifeditor")
    .applyToolBindings(model: model, refresh: refresh)
    .applyCursorBindings(model: model, refresh: refresh)
    .applyFrameBindings(model: model, refresh: refresh)
    .applyLayerBindings(model: model, refresh: refresh)
    .applyClipboardBindings(model: model, refresh: refresh)
    .applyPaletteBindings(model: model, refresh: refresh)
    .applyFileBindings(model: model, refresh: refresh)
  }

  private var headerRow: some View {
    HStack(spacing: 2) {
      Text("gifeditor").foregroundStyle(.foreground)
      Text(documentLabel).foregroundStyle(.muted)
      Spacer(minLength: 1)
      Text(model.isDirty ? "● modified" : "saved")
        .foregroundStyle(model.isDirty ? .warning : .success)
    }
    .padding(.horizontal, 1)
  }

  private var footer: some View {
    HStack(spacing: 2) {
      Text(model.statusMessage.isEmpty ? "Ctrl+? for help" : model.statusMessage)
        .foregroundStyle(.muted)
      Spacer(minLength: 1)
      Text(
        "[\(model.cursor.x),\(model.cursor.y)]  "
          + "L\(model.currentLayerIndex + 1)/\(model.currentFrame.layers.count)"
      )
      .foregroundStyle(.separator)
    }
    .padding(.horizontal, 1)
  }

  private var documentLabel: String {
    if let path = model.document.path {
      return path.lastPathComponent
    }
    return "untitled"
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
