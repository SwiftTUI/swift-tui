import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Composition matrix for GitHub issue SwiftTUI/swift-tui#5. The reporter's
// crash logs came from their full app, not the minimal repro, so the segmented
// row is exercised inside a spread of host compositions — siblings whose width
// changes with the selection, ScrollView, a selectable List row, outset
// borders, translucent backgrounds, two rows sharing focus, TabView,
// NavigationStack — each driven through arrows, Tab, computed mouse clicks and
// a drag, on the Unicode and ASCII glyph levels, while the F13 oracle counts.

enum SegmentedRowComposition: String, CaseIterable, Sendable {
  case siblingLabel
  case scrollView
  case listRow
  case outsetBorderNeighbors
  case translucentBackground
  case twoPickersSideBySide
  case tabView
  case navigationStack
  case verticalStackOfPickers
  case widthChangingSibling
}

enum SegmentedRowGlyphProfile: String, CaseIterable, Sendable {
  case unicode
  case ascii

  var capabilityProfile: TerminalCapabilityProfile {
    switch self {
    case .unicode: .trueColor
    case .ascii: .previewASCII
    }
  }
}

private struct CompositionRoot: View {
  let composition: SegmentedRowComposition
  @State private var selection: SegmentedRowOption = .red
  @State private var second: SegmentedRowOption = .green
  @State private var listSelection: Int? = 0
  @State private var tab: Int = 0

  var body: some View {
    switch composition {
    case .siblingLabel:
      VStack(alignment: .leading) {
        Text("Accent")
        SegmentedRowPicker(selection: $selection)
        Text("Selected: \(selection.rawValue)")
      }
      .padding(1)
    case .scrollView:
      ScrollView {
        VStack(alignment: .leading) {
          ForEach(0..<6, id: \.self) { row in
            Text("row \(row)")
          }
          SegmentedRowPicker(selection: $selection)
          ForEach(6..<14, id: \.self) { row in
            Text("row \(row)")
          }
        }
      }
      .padding(1)
    case .listRow:
      List(selection: $listSelection) {
        Text("first").tag(0)
        HStack {
          Text("Accent")
          SegmentedRowPicker(selection: $selection)
        }
        .tag(1)
        Text("third").tag(2)
      }
    case .outsetBorderNeighbors:
      VStack {
        Text("above").border(.separator, placement: .outset)
        SegmentedRowPicker(selection: $selection)
          .border(.tint, placement: .outset)
        Text("below").border(.separator, placement: .outset)
      }
      .padding(2)
    case .translucentBackground:
      VStack {
        SegmentedRowPicker(selection: $selection)
          .background(Color.blue.opacity(0.3))
          .opacity(0.8)
        Text("under")
      }
      .padding(1)
      .background(Color.gray.opacity(0.2))
    case .twoPickersSideBySide:
      HStack(spacing: 2) {
        SegmentedRowPicker(selection: $selection)
        SegmentedRowPicker(selection: $second)
      }
      .padding(1)
    case .tabView:
      TabView(selection: $tab) {
        Tab("One", value: 0) {
          VStack {
            SegmentedRowPicker(selection: $selection)
            Text("tab one \(selection.rawValue)")
          }
        }
        Tab("Two", value: 1) {
          Text("two")
        }
      }
    case .navigationStack:
      NavigationStack {
        VStack {
          SegmentedRowPicker(selection: $selection)
          Text("Selected \(selection.rawValue)")
        }
        .navigationTitle("Settings")
      }
    case .verticalStackOfPickers:
      VStack(spacing: 0) {
        SegmentedRowPicker(selection: $selection)
        SegmentedRowPicker(selection: $second)
      }
      .padding(1)
    case .widthChangingSibling:
      HStack {
        SegmentedRowPicker(selection: $selection)
        Text(selection == .green ? "green selected now" : selection.rawValue)
          .bold(selection == .blue)
      }
      .padding(1)
    }
  }
}

@MainActor
@Suite("Segmented bordered-button row composition matrix", .serialized)
struct SegmentedButtonRowCompositionStressTests {
  @Test(
    "segmented row journeys keep incremental raster sound across host compositions",
    arguments: SegmentedRowComposition.allCases, SegmentedRowGlyphProfile.allCases
  )
  func journeysKeepIncrementalRasterSound(
    composition: SegmentedRowComposition,
    glyphProfile: SegmentedRowGlyphProfile
  ) async throws {
    let result = try await runSegmentedRowJourney(
      rootIdentity: testIdentity("SegmentedRowComposition", composition.rawValue),
      terminalSize: CellSize(width: 60, height: 16),
      capabilityProfile: glyphProfile.capabilityProfile,
      steps: [
        // Keyboard journey on whatever is focused first.
        .keys([.arrowRight, .arrowRight, .arrowLeft]),
        // Move focus and keep arrowing.
        .keys([.tab, .arrowRight, .arrowLeft, .arrowLeft, .tab, .arrowRight]),
        // Mouse clicks on every segment glyph, forwards then backwards, then a
        // press/move/release across the row.
        .clickEverySegmentGlyph(),
        .clickEverySegmentGlyph(reversed: true),
        .dragAcrossSegmentGlyphs(),
        .keys([.arrowRight, .arrowRight]),
      ]
    ) {
      CompositionRoot(composition: composition)
    }

    #expect(
      result.reachedIncrementalRaster,
      "[\(composition.rawValue)/\(glyphProfile.rawValue)] never reached the incremental rasterizer: \(result.summary)"
    )
    #expect(
      result.mismatchGrowth == 0,
      "[\(composition.rawValue)/\(glyphProfile.rawValue)] incremental raster mismatch: \(result.summary)\n\(result.renderedFrames)"
    )
  }
}
