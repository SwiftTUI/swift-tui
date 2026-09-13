import SwiftTUIRuntime
import SwiftTUIViews
import Testing

private struct ArcSector: InsettableShape {
  func path(in rect: Rect) -> Path {
    let center = Point(
      x: rect.origin.x + rect.size.width / 2, y: rect.origin.y + rect.size.height / 2)
    var path = Path()
    path.move(to: center)
    path.addArc(
      center: center, radius: min(rect.size.width, rect.size.height) / 2,
      startAngle: .zero, endAngle: .degrees(90), clockwise: false)
    path.closeSubpath()
    return path
  }
}

@MainActor
struct DrawingPublicContractTests {
  @Test("STUI-354: a public consumer combines layout, an inset mask and a translated view")
  func insetClipAndOffset() {
    let text = "abcdefgh\nabcdefgh\nabcdefgh\nabcdefgh\nabcdefgh\nabcdefgh"
    let plain = DefaultRenderer().render(Text(text).frame(width: 8, height: 6).offset(x: 2, y: 1))
    let clipped = DefaultRenderer().render(
      Text(text).frame(width: 8, height: 6)
        .clipShape(Rectangle().inset(by: 1)).offset(x: 2, y: 1))
    #expect(clipped.rasterSurface.size == plain.rasterSurface.size)
    var retained = 0
    for (y, row) in clipped.rasterSurface.cells.enumerated() {
      for (x, cell) in row.enumerated() {
        if (3..<9).contains(x), (2..<6).contains(y) {
          #expect(cell.character == plain.rasterSurface.cells[y][x].character)
          retained += 1
        } else {
          #expect(cell.character == " ")
        }
      }
    }
    #expect(retained == 24)
  }

  @Test("STUI-110: Text is a value-semantic Hashable key including styled and rich values")
  func hashableText() async {
    let plain = Text("same")
    let bold = Text("same").bold()
    let clear = Text("same").underline(false)
    let rich = Text("a \(bold) b")
    let values = [plain, bold, clear, rich]
    let set = Set(values)
    #expect(set.count == 4)
    for value in values { #expect(set.contains(value)) }
    #expect(plain == Text(verbatim: "same"))
    #expect(plain.hashValue == Text(verbatim: "same").hashValue)
    #expect(rich == Text("a \(Text("same").bold()) b"))
    #expect(rich.hashValue == Text("a \(Text("same").bold()) b").hashValue)
    #expect(await Task.detached { rich.hashValue }.value == rich.hashValue)
  }

  @Test("STUI-114: public angle and arc APIs render in the documented downward-y quadrant")
  func renderedArcSector() {
    let snapshot = DefaultRenderer().render(
      ArcSector().fill(Color.white).frame(width: 16, height: 8))
    var lit = 0
    for (y, row) in snapshot.rasterSurface.cells.enumerated() {
      for (x, cell) in row.enumerated() where cell.character != " " && cell.character != "⠀" {
        lit += 1
        #expect(x >= 8)
        #expect(y >= 4)
      }
    }
    #expect(lit > 8)
    #expect(abs(Angle.degrees(180).radians - .pi) < 1e-12)
    #expect(abs(Angle.radians(.pi / 2).degrees - 90) < 1e-12)
  }
}
