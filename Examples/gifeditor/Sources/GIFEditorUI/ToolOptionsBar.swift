import GIFEditorCore
import SwiftTUI

/// Single-row contextual options bar that sits between the menu bar
/// and the main canvas. The leading half mirrors the active tool's
/// state (brush size for pen/eraser, primary chip + selection toggle
/// for bucket, gradient endpoints + selection toggle for gradient,
/// selection rect + Confirm/Clear for marquee, picked color readout
/// for eyedropper). The trailing half holds the global affordances
/// (`⇄` swap and `[?]` help) so they're always one click away
/// regardless of which tool is active.
///
/// Every clickable target inside the bar mirrors a keyboard shortcut
/// — see `REDESIGN.md` § "Mouse-parity matrix".
struct ToolOptionsBar: View {
  let model: EditorViewModel
  @Binding var isHelpPresented: Bool
  let refresh: @MainActor @Sendable () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      Text(model.tool.iconGlyph + " " + model.tool.label)
        .foregroundStyle(.tint)
      contextualOptions
      Spacer(minLength: 1)
      swapButton
      helpButton
    }
    .padding(.horizontal, 1)
    .border(.separator, set: .single)
  }

  // MARK: - Tool-specific options

  @ViewBuilder
  private var contextualOptions: some View {
    switch model.tool {
    case .pen, .eraser:
      brushSizeStepper
    case .fill:
      ColorChip(role: "P", color: primary)
      Text(hex(primary)).foregroundStyle(.separator)
      respectSelectionToggle(
        isOn: model.fillRespectsSelection
      ) {
        model.fillRespectsSelection.toggle()
        refresh()
      }
    case .gradient:
      ColorChip(role: "P", color: primary)
      Text("→").foregroundStyle(.muted)
      ColorChip(role: "S", color: secondary)
      respectSelectionToggle(
        isOn: model.gradientRespectsSelection
      ) {
        model.gradientRespectsSelection.toggle()
        refresh()
      }
    case .marquee:
      marqueeStatus
      confirmButton
      clearButton
    case .eyedropper:
      ColorChip(role: "P", color: primary)
      Text("#\(hex(primary))").foregroundStyle(.separator)
    }
  }

  // MARK: - Brush size stepper

  private var brushSizeStepper: some View {
    HStack(spacing: 1) {
      Text("size").foregroundStyle(.muted)
      Text("\(model.brushSize)").foregroundStyle(.foreground)
      stepperButton("⊖") {
        model.decreaseBrushSize()
        refresh()
      }
      stepperButton("⊕") {
        model.increaseBrushSize()
        refresh()
      }
    }
  }

  private func stepperButton(
    _ glyph: String,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button(action: action) {
      Text(glyph).foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Respect-selection toggle

  private func respectSelectionToggle(
    isOn: Bool,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 1) {
        Text(isOn ? "[✓]" : "[ ]").foregroundStyle(isOn ? .tint : .muted)
        Text("respect selection").foregroundStyle(.muted)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Marquee status + Confirm/Clear

  @ViewBuilder
  private var marqueeStatus: some View {
    if let selection = model.selection {
      let w = selection.rect.size.width
      let h = selection.rect.size.height
      let x = selection.rect.minX
      let y = selection.rect.minY
      let summary = "\(w)×\(h) @ (\(x),\(y))"
      Text(summary).foregroundStyle(.foreground)
    } else if model.pendingMarqueeAnchor != nil {
      Text("anchor set — drag or click to commit").foregroundStyle(.muted)
    } else {
      Text("drag or click to anchor").foregroundStyle(.muted)
    }
  }

  private var confirmButton: some View {
    Button {
      model.applyToolAtCursor()
      refresh()
    } label: {
      Text("[Confirm]").foregroundStyle(.tint)
    }
    .buttonStyle(.plain)
    .disabled(model.pendingMarqueeAnchor == nil && model.selection == nil)
  }

  private var clearButton: some View {
    Button {
      model.clearSelection()
      refresh()
    } label: {
      Text("[Clear]").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
    .disabled(model.selection == nil && model.pendingMarqueeAnchor == nil)
  }

  // MARK: - Trailing global buttons

  private var swapButton: some View {
    Button {
      model.swapPrimaryAndSecondary()
      refresh()
    } label: {
      Text("⇄ swap").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  private var helpButton: some View {
    Button {
      isHelpPresented = true
      refresh()
    } label: {
      Text("[?]").foregroundStyle(.muted)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Helpers

  private var primary: EditorColor {
    model.document.palette[model.primaryColorIndex]
  }

  private var secondary: EditorColor {
    model.document.palette[model.secondaryColorIndex]
  }

  private func hex(_ c: EditorColor) -> String {
    String(format: "%02X%02X%02X", c.red, c.green, c.blue)
  }
}

/// Compact, inline color swatch with a 1-character role marker (P/S)
/// overlaid on a 2-cell color block. Used by the options bar to show
/// the active primary/secondary color for tools that consume them.
private struct ColorChip: View {
  let role: String
  let color: EditorColor

  var body: some View {
    ZStack(alignment: .leading) {
      Rectangle()
        .fill(color.toTerminalColor())
        .frame(width: 4, height: 1)
      Text(role).foregroundStyle(.foreground)
    }
  }
}
