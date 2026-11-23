import SwiftTUI
import Testing
import TransitionConsumer

@MainActor
@Suite("Layer effects from a view library")
struct DigitMaskTests {
  @Test("Both spellings preserve the live link, decoration, styled blank and wide glyph")
  func masksDigitsInPlace() throws {
    let label = HStack(spacing: 0) {
      Text("\(Link(Text("7").bold().underline(), destination: "https://example.org/id"))")
      Text(" ").background(Color.blue)
      Text("界2").foregroundStyle(Color.yellow)
    }
    let proposal = ProposedSize(width: 5, height: 1)
    func cells<V: View>(_ view: V) -> [[RasterCell]] {
      DefaultRenderer().render(view, proposal: proposal).rasterSurface.cells
    }

    let plain = cells(label)
    try #require(plain.count == 1 && plain[0].count == 5)
    #expect(plain[0][0].hyperlink == "https://example.org/id")
    #expect(plain[0][2].spanWidth == 2)
    #expect(plain[0][3].continuationLeadX == 2)
    var expected = plain
    expected[0][0].character = "#"
    expected[0][4].character = "#"
    #expect(cells(label.maskingDigits()) == expected)
    #expect(cells(label.maskingDigitsInline()) == expected)
    #expect(cells(label.maskingDigits(isEnabled: false)) == plain)
    #expect(cells(label.maskingDigitsInline(isEnabled: false)) == plain)
  }

  @Test("Kernels compare by value and copied function shaders retain identity")
  func shaderEquality() {
    #expect(CellLayerShader(DigitMask()) == CellLayerShader(DigitMask(marker: "#")))
    #expect(CellLayerShader(DigitMask()) != CellLayerShader(DigitMask(marker: "*")))
    let identity: CellLayerShader.Function = { point, layer, _ in layer.sample(at: point) }
    let first = CellLayerShader(identity)
    let copy = first
    #expect(copy == first)
    #expect(CellLayerShader(identity) != first)
  }
}
