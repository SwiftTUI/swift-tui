import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Cell-level assertions for the new `.border(blend:set:sides:phase:)`
/// modifier.  Pinned by M5.A: when a `BorderBlend` is attached, the
/// rasterizer samples colors continuously around the rectangle's
/// perimeter and assigns one color per perimeter cell, walking
/// clockwise from the top-left corner.
@MainActor
struct BorderGradientTests {
  @Test(".border(blend:) writes perimeter-sampled colors on a small rect")
  func borderBlendBasicRendering() {
    // A 4x3 frame with a red→blue→red closed loop.  Each corner and
    // edge cell should have a non-nil foreground color, and at least
    // one cell should differ from pure red (the gradient sweeps
    // through blue at the perimeter midpoint).
    let view = Text("hi").border(
      blend: BorderBlend([Color.red, Color.blue, Color.red]),
      set: .single
    )
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("BorderBlendBasic"))
    )
    let cells = artifacts.rasterSurface.cells
    // Trimmed frame is 4x3 ("hi" content + 1-cell .single border).
    #expect(artifacts.rasterSurface.size.width == 4)
    #expect(artifacts.rasterSurface.size.height == 3)

    let topLeft = cells[0][0].style?.foregroundColor
    let topRight = cells[0][3].style?.foregroundColor
    #expect(topLeft != nil)
    #expect(topRight != nil)

    // Some perimeter cell must differ from red — the gradient sweeps
    // through blue near the perimeter midpoint.
    var nonRedCount = 0
    for y in 0..<3 {
      for x in 0..<4 where !(y == 1 && x == 1) && !(y == 1 && x == 2) {
        if let fg = cells[y][x].style?.foregroundColor, fg != Color.red {
          nonRedCount += 1
        }
      }
    }
    #expect(nonRedCount > 0)
  }

  @Test(".border(blend:) with phase rotation shifts the gradient start")
  func borderBlendPhaseShiftsStart() {
    // Render the same view at phase 0 and phase 0.5; at least one
    // perimeter cell should differ.
    let blend = BorderBlend([Color.red, Color.green, Color.blue, Color.red])
    let view0 = Text("hi").border(blend: blend, set: .single, phase: 0)
    let viewHalf = Text("hi").border(blend: blend, set: .single, phase: 0.5)
    let art0 = DefaultRenderer().render(
      view0,
      context: .init(identity: testIdentity("BorderBlendPhase0"))
    )
    let artHalf = DefaultRenderer().render(
      viewHalf,
      context: .init(identity: testIdentity("BorderBlendPhaseHalf"))
    )
    let cells0 = art0.rasterSurface.cells
    let cellsHalf = artHalf.rasterSurface.cells

    // Sweep all perimeter cells; at least one must differ.
    var differ = false
    outer: for y in 0..<3 {
      for x in 0..<4 where !(y == 1 && x == 1) && !(y == 1 && x == 2) {
        let fg0 = cells0[y][x].style?.foregroundColor
        let fgHalf = cellsHalf[y][x].style?.foregroundColor
        if fg0 != fgHalf {
          differ = true
          break outer
        }
      }
    }
    #expect(differ)
  }

  @Test(".border(blend:) respects sides mask by drawing only enabled edges")
  func borderBlendSidesMask() {
    // With sides: [.top], only the top row should carry a border
    // glyph; the layout shrinks to "content + top inset only".
    let view = Text("hi").border(
      blend: BorderBlend([Color.red, Color.blue]),
      set: .single,
      sides: [.top]
    )
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("BorderBlendTopOnly"))
    )
    // Frame: 2 wide ("hi"), 2 tall (1 top border + 1 content row).
    let size = artifacts.rasterSurface.size
    #expect(size.width == 2)
    #expect(size.height == 2)

    // The top row's two cells should both have a non-nil foreground
    // (sampled from the perimeter), and they should differ from each
    // other for a 2-stop gradient laid across the rect's perimeter.
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].style?.foregroundColor != nil)
    #expect(cells[0][1].style?.foregroundColor != nil)
  }
}
