import SwiftTUI
import Testing
import TransitionConsumer

@MainActor
struct OrderedShaderTests {
  @Test(arguments: [false, true])
  func lowerColumns(inline: Bool) {
    let view = ZStack(alignment: .topLeading) {
      Text("abc").foregroundStyle(Color.green)
      Text("TOP").lowerColumn(inline: inline)
    }
    let row = DefaultRenderer().render(view, proposal: .init(width: 3, height: 1)).rasterSurface
      .cells[0]
    #expect(row.map(\.character) == ["a", " ", "c"])
    #expect(row[0].style?.foregroundColor == .green && row[1].style == nil)
  }

  @Test(arguments: [false, true])
  func swapsBehindSubject(inline: Bool) {
    func render(_ enabled: Bool) -> [RasterCell] {
      let view = ZStack(alignment: .topLeading) {
        Text("abc")
        Text("T").offset(x: 2).swapColumnsBehind(inline: inline, isEnabled: enabled)
      }
      return DefaultRenderer().render(view, proposal: .init(width: 3, height: 1)).rasterSurface
        .cells[0]
    }
    #expect(render(true).map(\.character) == ["b", "a", "T"])
    #expect(render(false).map(\.character) == ["a", "b", "T"])
  }

  @Test func authorCreatesAndCopiesABuffer() {
    var buffer = CellEffectBuffer(bounds: .init(origin: .zero, size: .init(width: 2, height: 1)))
    buffer.set(CellGlyph("界"), at: .zero)
    let snapshot = buffer.snapshot()
    let tail = CellPoint(x: 1, y: 0)
    #expect(buffer.sample(at: tail) == .continuation(columnsBack: 1))
    var copy = buffer
    copy.clear(at: tail)
    #expect(copy.sample(at: .zero) == .empty)
    #expect(snapshot.glyph(occupying: tail)?.character == "界")
  }
}
