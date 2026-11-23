import Testing

@testable import SwiftTUICore

@Suite("Cell effect paint and sampling")
struct CellEffectRasterTests {
  private let bounds = CellRect(origin: .zero, size: .init(width: 12, height: 2))

  private func subject(_ text: String, at x: Int = 0, style: TextStyle = .init()) -> DrawNode {
    let ink = CellRect(origin: .init(x: x, y: 0), size: .init(width: 12 - x, height: 1))
    return DrawNode(
      identity: testIdentity("subject"), bounds: bounds,
      commands: [TextPaintFamily.rich.command(bounds: ink, lines: [text], style: style)])
  }

  private func pass(_ shader: CellLayerShader) -> DrawEffect {
    .cellLayer(.init(shader, offset: .zero))
  }

  @Test("A zero-distance query sees the owner across a column boundary")
  func occupying() {
    let shader = CellLayerShader { point, layer, _ in
      if point.x == 7 { return .empty }
      guard point.x == 8,
        layer.sample(at: point) == .continuation(columnsBack: 1),
        layer.sample(at: .init(x: 7, y: point.y)) == .empty,
        layer.glyph(occupying: .init(x: 7, y: point.y)) == nil,
        var glyph = layer.glyph(occupying: point)
      else { return .empty }
      glyph.character = glyph.character == "界" ? "!" : "?"
      return .glyph(glyph)
    }
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    var previous: RasterSurface?
    for (text, style, marker) in [
      ("界", Color.blue, "!"), ("語", Color.blue, "?"), ("語", Color.red, "?"),
      ("x", Color.red, " "),
    ] {
      var node = subject(text, at: 7, style: .init(foregroundStyle: .color(style)))
      node.drawEffects = .init([pass(shader)])
      let result = rasterizer.rasterizeCollectingVisibleIdentities(
        node, minimumSize: bounds.size, previousSurface: previous,
        damage: previous == nil ? nil : .init(textRows: [.init(row: 0, columnRanges: [7..<8])]))
      #expect(result.surface == rasterizer.rasterize(node, minimumSize: bounds.size))
      #expect(result.incrementalMismatch == nil)
      if previous != nil { #expect(result.path == .incremental) }
      let cells = result.surface.cells[0]
      #expect(cells[7] == .empty)
      #expect(String(cells[8].character) == marker)
      #expect(!cells[8].isContinuation)
      if marker != " " {
        #expect(cells[8].style?.foregroundColor == style)
        #expect(cells[8].hyperlink == "https://example.com/text")
      }
      previous = result.surface
    }
    var clipped = subject("界", at: 7)
    clipped.clipBounds = .init(origin: .init(x: 8, y: 0), size: .init(width: 3, height: 1))
    clipped.drawEffects = .init([pass(shader)])
    #expect(rasterizer.rasterize(clipped).cells[0][8] == .empty)
  }

  @Test("An explicit space covers the lower text while a hole preserves it")
  func spaceAndHole() {
    let identity = CellLayerShader { p, layer, _ in layer.sample(at: p) }
    var top = DrawNode(
      identity: testIdentity("space"), bounds: bounds,
      commands: [TextPaintFamily.plain.command(bounds: bounds, lines: [" "], style: .init())])
    top.drawEffects = .init([pass(identity)])
    var lower = subject("AB")
    lower.children = [top]
    let cells = Rasterizer().rasterize(lower).cells[0]
    top.drawEffects = .init()
    lower.children = [top]
    #expect(cells == Rasterizer().rasterize(lower).cells[0])
    #expect(cells[0].character == " " && cells[0].hyperlink == nil)
    #expect(cells[1].character == "B")
  }

  /// One-cell probe from the reference compositor. Quantize at each channel mix.
  @Test("B over changing A and C selects the glyph and mixed colors at both quarters")
  func changingLowerCell() {
    func text(_ glyph: String, foreground: UInt32, background: UInt32, lower: Bool) -> DrawNode {
      let style = TextStyle(
        foregroundStyle: .color(Color(hexRGB: foreground)),
        backgroundStyle: .color(Color(hexRGB: background)),
        emphasis: lower ? .bold : .italic, underlineStyle: lower ? .init() : nil)
      return DrawNode(
        identity: testIdentity(glyph), bounds: bounds,
        commands: [
          .richText(
            bounds: bounds,
            payload: .init(runs: [
              .init(text: glyph, style: style, destination: .init("https://example.org/" + glyph))
            ]), lineLimit: nil, truncationMode: .tail, wrappingStrategy: .wordBoundary)
        ])
    }
    for progress in [0.25, 0.75] {
      let shader = CellLayerShader(readingBackdrop: { point, source, backdrop, _ in
        guard let front = source.glyph(occupying: point),
          let back = backdrop.glyph(occupying: point),
          case .color(let backInk) = back.paint.foreground,
          case .color(let backPaper) = back.paint.background,
          case .color(let frontInk) = front.paint.foreground,
          case .color(let frontPaper) = front.paint.background
        else { return .empty }
        func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
          func channel(_ x: Double, _ y: Double) -> Double {
            let start = (x * 255).rounded()
            return (start + ((y * 255).rounded() - start) * t).rounded() / 255
          }
          return Color(
            red: channel(a.red, b.red), green: channel(a.green, b.green),
            blue: channel(a.blue, b.blue))
        }
        let bg = mix(backPaper, frontPaper, progress)
        var result = progress < 0.5 ? back : front
        result.paint.background = .color(bg)
        result.paint.foreground = .color(
          progress < 0.5
            ? mix(backInk, bg, progress * 2) : mix(bg, frontInk, progress * 2 - 1))
        return .glyph(result)
      })
      var top = text("B", foreground: 0x1048C0, background: 0xC41838, lower: false)
      top.drawEffects = .init([pass(shader)])
      var previous: RasterSurface?
      let early = progress < 0.5
      for name in ["A", "C"] {
        var scene = text(name, foreground: 0xE0B024, background: 0x166C58, lower: true)
        scene.children = [top]
        let result = Rasterizer().rasterizeCollectingVisibleIdentities(
          scene,
          minimumSize: bounds.size, previousSurface: previous, damage: .init(dirtyRows: [0]))
        let expected = early ? name : "B"
        let style = ResolvedTextStyle(
          foregroundColor: Color(hexRGB: early ? 0x91843A : 0x553B80),
          backgroundColor: Color(hexRGB: early ? 0x425750 : 0x992D40),
          emphasis: early ? .bold : .italic, underlineStyle: early ? .init() : nil)
        #expect(
          result.surface.cells[0][0]
            == RasterCell(
              character: Character(expected),
              style: style, hyperlink: "https://example.org/" + expected))
        #expect(result.incrementalMismatch == nil)
        previous = result.surface
      }
    }
  }

  @Test("Nested capture reads current lower paint and respects explicit groups")
  func lowerPaint() {
    let identity = CellLayerShader { p, source, _ in source.sample(at: p) }
    let rasterizer = Rasterizer()
    for early in [true, false] {
      let reader = CellLayerShader(readingBackdrop: { p, source, lower, _ in
        early ? lower.sample(at: p) : source.sample(at: p)
      })
      var previous: RasterSurface?
      for lowerGlyph in ["A", "C"] {
        var lower = subject(lowerGlyph, style: .init(foregroundStyle: .color(.red)))
        var top = subject("B", style: .init(foregroundStyle: .color(.blue)))
        top.drawEffects = .init([pass(reader), pass(identity)])
        lower.children = [top]
        let frame = rasterizer.rasterizeCollectingVisibleIdentities(
          lower, minimumSize: bounds.size, previousSurface: previous, damage: .init(dirtyRows: [0]))
        #expect(frame.incrementalMismatch == nil)
        let cell = frame.surface.cells[0][0]
        #expect(String(cell.character) == (early ? lowerGlyph : "B"))
        #expect(cell.style?.foregroundColor == (early ? .red : .blue))
        previous = frame.surface
      }
    }

    let groupReader = CellLayerShader(readingBackdrop: { p, _, under, _ in
      .glyph(CellGlyph(under.glyph(occupying: p) == nil ? "E" : "L"))
    })
    var lower = subject("A")
    var top = subject("B")
    top.drawEffects = .init([pass(groupReader), .compositingGroup])
    lower.children = [top]
    #expect(rasterizer.rasterize(lower).cells[0][0].character == "E")
  }
}
