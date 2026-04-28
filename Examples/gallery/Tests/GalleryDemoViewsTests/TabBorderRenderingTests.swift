import TerminalUI
import Testing

@testable import GalleryDemoViews

// Pins the visual intent of `.border(...)` call sites in the gallery
// tabs after the Milestone 2 rewrite of `.border` to a layout-aware
// outset default (`.outerHalfBlock`, decorative placement).
//
// These tests do NOT try to capture the full tab raster — both tabs
// include figlet art and button grids whose exact glyphs would make
// a full snapshot brittle. Instead they assert just enough to pin:
//
//   * CounterTab: a `.outerHalfBlock` card frame is drawn around the
//     entire tab, using `.separator` foreground. This was the intent
//     of the original `.border(.separator)` call under the new default.
//   * CalculatorTab: the display area is NOT framed by any extra
//     border. The old `.border(.black)` was a workaround to hide the
//     legacy inset border; the new layout-aware default would actually
//     draw a visible half-block frame, so the call was removed.
@MainActor
@Suite
struct TabBorderRenderingTests {
  @Test("CounterTab wraps its content in an outerHalfBlock card frame")
  func counterTabHasOuterHalfBlockCardFrame() throws {
    let surface = renderCounterTab()

    let topEdge = try #require(
      widestFrameEdge(in: surface, leftCorner: "▛", rightCorner: "▜", fill: "▀")
    )
    let bottomEdge = try #require(
      widestFrameEdge(in: surface, leftCorner: "▙", rightCorner: "▟", fill: "▄")
    )

    // Top and bottom card edges are the same width.
    #expect(topEdge.interiorWidth == bottomEdge.interiorWidth)
    #expect(topEdge.leftColumn == bottomEdge.leftColumn)
    #expect(topEdge.rightColumn == bottomEdge.rightColumn)

    // The card must have at least one interior row with the left /
    // right edge glyphs, confirming a closed frame.
    let hasInteriorEdge =
      topEdge.row < bottomEdge.row
      && ((topEdge.row + 1)..<bottomEdge.row).contains { rowIndex in
        let row = surface.cells[rowIndex]
        return row[topEdge.leftColumn].character == "▌"
          && row[topEdge.rightColumn].character == "▐"
      }
    #expect(hasInteriorEdge)
  }

  @Test("CounterTab card frame cells share a uniform foreground style")
  func counterTabCardFrameHasUniformForeground() throws {
    let surface = renderCounterTab()

    // All four corners should render with the same non-nil foreground
    // color — that pins the `.border(.separator, ...)` call-site without
    // tying the test to the exact appearance-derived color resolution.
    let topEdge = try #require(
      widestFrameEdge(in: surface, leftCorner: "▛", rightCorner: "▜", fill: "▀")
    )
    let bottomEdge = try #require(
      widestFrameEdge(in: surface, leftCorner: "▙", rightCorner: "▟", fill: "▄")
    )
    let topRow = surface.cells[topEdge.row]
    let bottomRow = surface.cells[bottomEdge.row]
    let topLeft = topRow[topEdge.leftColumn]
    let topRight = topRow[topEdge.rightColumn]
    let bottomLeft = bottomRow[bottomEdge.leftColumn]
    let bottomRight = bottomRow[bottomEdge.rightColumn]

    let topLeftFg = topLeft.style?.foregroundColor
    #expect(topLeftFg != nil)
    #expect(topRight.style?.foregroundColor == topLeftFg)
    #expect(bottomLeft.style?.foregroundColor == topLeftFg)
    #expect(bottomRight.style?.foregroundColor == topLeftFg)
  }

  @Test("CalculatorTab does not draw any half-block border around the display")
  func calculatorTabDisplayHasNoHalfBlockBorder() {
    let surface = renderCalculatorTab()
    // None of the outerHalfBlock corner glyphs should appear anywhere
    // in the calculator tab. The tab uses offset `Rectangle` shapes
    // for its drop shadow and a figlet digit for the display, so any
    // ▛ / ▜ / ▙ / ▟ on the surface would have to come from a border.
    let cornerGlyphs: Set<Character> = ["▛", "▜", "▙", "▟"]
    var foundCorner: Character?
    outer: for line in surface.lines {
      for ch in line where cornerGlyphs.contains(ch) {
        foundCorner = ch
        break outer
      }
    }
    #expect(
      foundCorner == nil,
      "CalculatorTab should have no outerHalfBlock corner glyphs, found: \(String(describing: foundCorner))"
    )
  }

  // MARK: - Helpers

  private func renderCounterTab() -> RasterSurface {
    let terminalSize = Size(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      CounterTab(),
      context: .init(
        identity: Identity(components: [.named("CounterTabBorderPin")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    return artifacts.rasterSurface
  }

  private func renderCalculatorTab() -> RasterSurface {
    let terminalSize = Size(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let artifacts = DefaultRenderer().render(
      CalculatorTab(),
      context: .init(
        identity: Identity(components: [.named("CalculatorTabBorderPin")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    return artifacts.rasterSurface
  }

  private struct FrameEdge {
    var row: Int
    var leftColumn: Int
    var rightColumn: Int

    var interiorWidth: Int {
      rightColumn - leftColumn - 1
    }
  }

  private func widestFrameEdge(
    in surface: RasterSurface,
    leftCorner: Character,
    rightCorner: Character,
    fill: Character
  ) -> FrameEdge? {
    var bestEdge: FrameEdge?

    for rowIndex in surface.cells.indices {
      let row = surface.cells[rowIndex]
      for leftColumn in row.indices where row[leftColumn].character == leftCorner {
        for rightColumn in row.indices where rightColumn > leftColumn {
          guard row[rightColumn].character == rightCorner else { continue }

          let interiorColumns = (leftColumn + 1)..<rightColumn
          guard
            !interiorColumns.isEmpty,
            interiorColumns.allSatisfy({ row[$0].character == fill })
          else {
            continue
          }

          let candidate = FrameEdge(
            row: rowIndex,
            leftColumn: leftColumn,
            rightColumn: rightColumn
          )
          if bestEdge.map({ candidate.interiorWidth > $0.interiorWidth }) ?? true {
            bestEdge = candidate
          }
        }
      }
    }

    return bestEdge
  }
}
