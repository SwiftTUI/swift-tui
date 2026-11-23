import SwiftTUI
import Testing
import TransitionConsumer

@MainActor
@Suite("Source shaders from a view library")
struct SourceShaderTests {
  @Test("Both color spellings recolor glyphs and painted spaces and preserve links and spans")
  func indexedColor() throws {
    let label = HStack(spacing: 0) {
      Text("\(Link(Text("7").underline(), destination: "https://example.org/id"))")
      Text(" ").background(Color.green)
      Text("界").bold()
    }
    func row<V: View>(_ view: V) -> [RasterCell] {
      DefaultRenderer().render(view, proposal: ProposedSize(width: 4, height: 1)).rasterSurface
        .cells[0]
    }
    let plain = row(label)
    let ink = row(label.paletteInk(196))
    let inline = row(label.paletteInkInline(196))
    #expect(ink == inline)
    #expect(ink[0].hyperlink == plain[0].hyperlink)
    #expect(ink[0].style?.underlineStyle == plain[0].style?.underlineStyle)
    #expect(ink[1].style?.backgroundColor == plain[1].style?.backgroundColor)
    #expect(ink[2].spanWidth == 2)
    #expect(ink[3].continuationLeadX == 2)
    #expect(ink[2].style?.emphasis == plain[2].style?.emphasis)
    for x in [0, 1, 2] {
      let style = try #require(ink[x].style)
      #expect(style.foregroundPaletteIndex == 196)
      #expect(style.backgroundPaletteIndex == nil)
      #expect(style.foregroundColor == Color(red: 1, green: 0, blue: 0))
    }
    #expect(row(label.paletteInk(196, isEnabled: false)) == plain)
    #expect(row(label.paletteInkInline(196, isEnabled: false)) == plain)
  }

  @Test("Both distortion spellings move intact spans and expose a hole at the first column")
  func inverseMapping() {
    let label = Text("界ab").foregroundStyle(Color.yellow)
    func row<V: View>(_ view: V) -> [RasterCell] {
      DefaultRenderer().render(view, proposal: ProposedSize(width: 4, height: 1)).rasterSurface
        .cells[0]
    }
    let moved = row(label.shiftRight())
    #expect(moved == row(label.shiftRightInline()))
    #expect(moved[0].character == " ")
    #expect(moved[0].style == nil)
    #expect(moved[1].character == "界")
    #expect(moved[1].spanWidth == 2)
    #expect(moved[2].continuationLeadX == 1)
    #expect(moved[3].character == "a")
    #expect(moved[3].style?.foregroundColor == .yellow)
    #expect(row(label.shiftRight(isEnabled: false)) == row(label))
    #expect(row(label.shiftRightInline(isEnabled: false)) == row(label))
  }

  @Test("Color and distortion functions have identity and kernel values have structural equality")
  func shaderEquality() {
    #expect(CellColorShader(PaletteInk(index: 1)) == CellColorShader(PaletteInk(index: 1)))
    #expect(CellColorShader(PaletteInk(index: 1)) != CellColorShader(PaletteInk(index: 2)))
    #expect(CellDistortionShader(ShiftRight()) == CellDistortionShader(ShiftRight()))
    let ink: CellColorShader.Function = { _, paint, _ in paint }
    let firstInk = CellColorShader(ink)
    let copiedInk = firstInk
    #expect(firstInk == copiedInk)
    #expect(firstInk != CellColorShader(ink))
    let map: CellDistortionShader.Function = { point, _ in point }
    let firstMap = CellDistortionShader(map)
    let copiedMap = firstMap
    #expect(firstMap == copiedMap)
    #expect(firstMap != CellDistortionShader(map))
    #expect(firstMap != firstMap.drawing(in: .outset(x: 1, y: 0)))
  }
}
