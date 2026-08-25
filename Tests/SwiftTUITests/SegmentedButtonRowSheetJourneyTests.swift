import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// GitHub issue SwiftTUI/swift-tui#5, narrowed by the reporter: the segmented
// bordered-button row (a focusable container carrying a `strokeBorder`
// overlay) traps the F13 incremental-vs-fresh raster oracle only when it is
// presented inside a `.sheet` *and* two focusable siblings follow it in the
// same stack. Removing the overlay, the sheet, or one of the two trailing
// buttons stops the trap. This journey drives the reporter's app verbatim:
// press the "Add" button, arrow the picker inside the sheet, Tab through the
// trailing buttons, click the segments.

enum SegmentedRowSheetVariant: String, CaseIterable, Sendable {
  /// The reporter's narrowed app, verbatim.
  case reported
  /// Ablation: a single trailing button (reported not to trap).
  case oneTrailingButton
  /// Ablation: no focus-ring overlay (reported not to trap).
  case noOverlay
}

/// The reporter's `SegmentedPicker` with the overlay made optional so the
/// ablation can drop it without changing anything else.
private struct SheetSegmentedPicker: View {
  @Binding var selection: SegmentedRowOption
  let showsOverlay: Bool
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 0) {
      ForEach(SegmentedRowOption.allCases) { option in
        let isSelected = option == selection
        Button {
          selection = option
        } label: {
          Text(isSelected ? "[●]" : " ● ")
            .foregroundStyle(option.color)
            .bold(isSelected)
        }
        .buttonStyle(.bordered)
        .focusable(false)
      }
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .overlay {
      if showsOverlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
          style: isFocused ? .heavy : .init()
        )
      }
    }
    .focusable()
    .focused($isFocused)
    .onKeyPress(.key(.arrowLeft)) { _ in
      move(-1)
      return .handled
    }
    .onKeyPress(.key(.arrowRight)) { _ in
      move(1)
      return .handled
    }
  }

  private func move(_ delta: Int) {
    let all = SegmentedRowOption.allCases
    guard let index = all.firstIndex(of: selection) else { return }
    selection = all[(index + delta + all.count) % all.count]
  }
}

private struct ReproSheet: View {
  let variant: SegmentedRowSheetVariant
  @Binding var isPresented: Bool
  @State private var color: SegmentedRowOption = .red

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Add Item").bold()
      Divider()

      HStack {
        Text("Color:")
        SheetSegmentedPicker(selection: $color, showsOverlay: variant != .noOverlay)
      }

      Button("Cancel") { isPresented = false }
      if variant != .oneTrailingButton {
        Button("Add") { isPresented = false }
      }
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }
}

private struct ReproRoot: View {
  let variant: SegmentedRowSheetVariant
  @State private var isAddPresented = false

  var body: some View {
    Button("Add") { isAddPresented = true }
      .padding(.init(horizontal: 1, vertical: 0))
      .sheet(isPresented: $isAddPresented) {
        ReproSheet(variant: variant, isPresented: $isAddPresented)
      }
  }
}

@MainActor
@Suite("Segmented bordered-button row inside a sheet", .serialized)
struct SegmentedButtonRowSheetJourneyTests {
  @Test(
    "arrowing a segmented row presented in a sheet keeps incremental raster sound",
    arguments: SegmentedRowSheetVariant.allCases
  )
  func sheetJourneyKeepsIncrementalRasterSound(variant: SegmentedRowSheetVariant) async throws {
    let result = try await runSegmentedRowJourney(
      rootIdentity: testIdentity("SegmentedRowSheet", variant.rawValue),
      terminalSize: CellSize(width: 80, height: 24),
      steps: [
        // Press the root "Add" button: the sheet opens.
        .keys([.return]),
        // Arrow whatever the sheet focused first, then Tab through the
        // sheet's focusables and arrow the picker from each stop.
        .keys([.arrowRight, .arrowRight, .arrowLeft]),
        .keys([.tab, .arrowRight, .arrowLeft, .tab, .arrowRight, .tab, .arrowRight, .arrowLeft]),
        // Mouse clicks on every segment glyph, forwards then backwards.
        .clickEverySegmentGlyph(),
        .clickEverySegmentGlyph(reversed: true),
        .keys([.arrowRight, .arrowRight]),
      ]
    ) {
      ReproRoot(variant: variant)
    }

    #expect(
      result.frames.contains(where: { $0.lines.contains(where: { $0.contains("Add Item") }) }),
      "[\(variant.rawValue)] the sheet never opened:\n\(result.renderedFrames)"
    )
    #expect(
      result.reachedIncrementalRaster,
      "[\(variant.rawValue)] never reached the incremental rasterizer: \(result.summary)"
    )
    #expect(
      result.mismatchGrowth == 0,
      """
      [\(variant.rawValue)] incremental raster mismatch: \(result.summary)
      \(result.renderedFrames)
      """
    )
  }
}
