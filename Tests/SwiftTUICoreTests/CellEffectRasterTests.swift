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
      let shader = CellLayerShader.compositing({ point, source, backdrop, _ in
        guard let front = source.glyph(occupying: point),
          let back = backdrop.glyph(occupying: point),
          case .color(let backInk) = back.paint.foreground,
          case .color(let backPaper) = back.paint.background,
          case .color(let frontInk) = front.paint.foreground,
          case .color(let frontPaper) = front.paint.background
        else { return .keepDestination }
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
        return .replace(.glyph(result))
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
      let reader = CellLayerShader.compositing({ p, source, lower, _ in
        .replace(early ? lower.sample(at: p) : source.sample(at: p))
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

    let groupReader = CellLayerShader.compositing({ p, _, under, _ in
      .replace(.glyph(CellGlyph(under.glyph(occupying: p) == nil ? "E" : "L")))
    })
    var lower = subject("A")
    var top = subject("B")
    top.drawEffects = .init([pass(groupReader), .compositingGroup])
    lower.children = [top]
    #expect(rasterizer.rasterize(lower).cells[0][0].character == "E")
  }
}

extension CellEffectRasterTests {
  @Test("A viewport mapping gathers an offscreen glyph and invalidates the old output on bypass")
  func displacedSource() {
    let ink = CellRect(origin: .init(x: -3, y: -1), size: .init(width: 3, height: 1))
    var child = DrawNode(
      identity: testIdentity("offscreen"), bounds: ink,
      commands: [
        TextPaintFamily.rich.command(
          bounds: ink, lines: ["界x"], style: .init(foregroundStyle: .color(.red)))
      ])
    let mapping = CellDistortionShader { point, context in
      guard context.originInRoot == .init(x: -3, y: -1), point.y == 2 else { return nil }
      return .init(x: point.x - 6, y: 0)
    }.drawing(in: .viewport)
    child.drawEffects = .init([.cellLayer(.init(mapping.layer, offset: .layerBounds))])
    var root = DrawNode(
      identity: testIdentity("parent"), bounds: bounds, clipBounds: bounds, children: [child])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let first = rasterizer.rasterize(root)
    #expect(first.cells[1][3].character == "界")
    #expect(first.cells[1][4].continuationLeadX == 3)
    #expect(first.cells[1][5].character == "x")
    #expect(first.cells[1][3].style?.foregroundColor == .red)
    child.drawEffects = .init()
    root.children = [child]
    let next = rasterizer.rasterizeCollectingVisibleIdentities(
      root, minimumSize: bounds.size,
      previousSurface: first, damage: .init(dirtyRows: [0]))
    #expect(next.path == .incremental && next.incrementalMismatch == nil)
    #expect(next.surface == rasterizer.rasterize(root))
    #expect(next.surface.cells[1].allSatisfy { $0 == .empty })
  }

  @Test("Two fractional masks compound before final ink and paper resolution")
  func chainedCoverage() {
    let half = CellColorShader { _, paint, _ in
      var result = paint
      result.coverage *= 0.5
      return result
    }
    let quarter = CellColorShader { _, paint, _ in
      var result = paint
      result.coverage *= 0.25
      return result
    }
    var back = subject("lower", style: .init(backgroundStyle: .color(.blue)))
    var front = subject(
      "X ", style: .init(foregroundStyle: .color(.yellow), backgroundStyle: .color(.red)))
    let rasterizer = Rasterizer()
    front.drawEffects = .init([pass(half.layer), pass(half.layer)])
    back.children = [front]
    let chained = rasterizer.rasterize(back)
    front.drawEffects = .init([pass(quarter.layer)])
    back.children = [front]
    #expect(chained == rasterizer.rasterize(back))
    #expect(chained.cells[0][0].character == "X" && chained.cells[0][1].character == " ")
    #expect(chained.cells[0][0].style?.backgroundColor != .red)
  }

  @Test("Only enabled passes take a source snapshot")
  func captureCounts() {
    let probe = RasterWorkProbe()
    Rasterizer.$workProbe.withValue(probe) {
      var scene = subject("X")
      let shader = CellLayerShader { point, layer, _ in layer.sample(at: point) }
      let plain = Rasterizer().rasterize(scene)
      #expect(probe.snapshot().cellEffectCaptures == 0)
      scene.drawEffects = .init([pass(shader)])
      #expect(Rasterizer().rasterize(scene) == plain)
      #expect(probe.snapshot().cellEffectCaptures == 1)
      scene.drawEffects = .init()
      #expect(Rasterizer().rasterize(scene) == plain)
      #expect(probe.snapshot().cellEffectCaptures == 1)
    }
  }
}

extension CellEffectRasterTests {
  @Test("Nested source passes keep the viewport and the inner shader's displaced output")
  func nestedViewport() {
    let frame = CellRect(origin: .init(x: 2, y: 0), size: .init(width: 1, height: 1))
    var child = DrawNode(
      identity: testIdentity("shift"), bounds: frame,
      commands: [TextPaintFamily.plain.command(bounds: frame, lines: ["A"], style: .init())])
    let shift = CellDistortionShader { p, context in
      guard context.viewport.size.width == 12, context.originInRoot.x == 2 else { return nil }
      return CellPoint(x: p.x - 1, y: p.y)
    }.drawing(in: .viewport)
    let copy = CellLayerShader { p, source, _ in source.sample(at: p) }
    child.drawEffects = .init([
      .cellLayer(.init(shift.layer, offset: .cells(x: 1, y: 0))),
      pass(copy),
    ])
    let scene = DrawNode(identity: testIdentity("scene"), bounds: bounds, children: [child])
    let cells = Rasterizer().rasterize(scene).cells[0]
    #expect(cells[2].character == " " && cells[3].character == "A")
  }
}

extension CellEffectRasterTests {
  @Test("Full-layer reading reaches beyond the dense surface budget, including an occupying lead")
  func sparseLayerBounds() {
    let far = 65_567
    let extent = CellRect(origin: .zero, size: .init(width: far + 2, height: 1))
    let ink = CellRect(origin: .init(x: far, y: 0), size: .init(width: 2, height: 1))
    let copy = CellLayerShader { p, source, _ in
      guard p.x == 0, var glyph = source.glyph(occupying: .init(x: far + 1, y: 0)),
        glyph.character == "界"
      else { return .empty }
      glyph.character = "X"
      return .glyph(glyph)
    }.drawing(in: .rect(.init(origin: .zero, size: .init(width: 1, height: 1))))
    let node = DrawNode(
      identity: testIdentity("long"), bounds: extent,
      drawEffects: .init([.cellLayer(.init(copy, offset: .layerBounds))]),
      commands: [TextPaintFamily.rich.command(bounds: ink, lines: ["界"], style: .init())])
    let frame = Rasterizer().rasterizeCollectingVisibleIdentities(
      node,
      minimumSize: bounds.size, maximumSize: bounds.size, previousSurface: nil, damage: nil)
    #expect(frame.surface.cells[0][0].character == "X")
    #expect(frame.surface.cells[0][0].hyperlink != nil)
  }
}

extension CellEffectRasterTests {
  @Test("A transient output cannot republish a link sampled while the node was live")
  func outgoingCachedLink() {
    let retained = CellGlyph(
      RasterCell(character: "L", hyperlink: "https://example.org/live"), allowsLink: true)
    let shader = CellLayerShader { _, _, _ in .glyph(retained) }
    for transient in [false, true] {
      let node = DrawNode(
        identity: testIdentity("retained"), bounds: bounds,
        drawEffects: .init([pass(shader)]), isTransient: transient)
      let cell = Rasterizer().rasterize(node).cells[0][0]
      #expect(cell.character == "L")
      #expect(cell.hyperlink == (transient ? nil : "https://example.org/live"))
    }
  }

  @Test("An outset wider than an integer extent is intersected with the finite viewport")
  func veryLargeOutset() {
    let shader = CellLayerShader { _, _, _ in .glyph(CellGlyph("O")) }.drawing(
      in: .outset(x: .max, y: 0))
    var node = DrawNode(
      identity: testIdentity("outset"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      drawEffects: .init([pass(shader)]))
    let copy = CellLayerShader { p, source, _ in source.sample(at: p) }
    for outer in [false, true] {
      if outer { node.drawEffects = .init(node.drawEffects.ordered + [pass(copy)]) }
      let parent = DrawNode(
        identity: testIdentity("viewport"), bounds: bounds, clipBounds: bounds, children: [node])
      let surface = Rasterizer().rasterize(parent)
      #expect(surface.cells[0].allSatisfy { $0.character == "O" })
    }
  }
}

extension CellEffectRasterTests {
  @Test("A sparse source gives its inner viewport shader the same output extent as a dense source")
  func tiledContext() {
    let painter = CellLayerShader { _, _, context in
      .glyph(CellGlyph(context.outputBounds.size.width == 80 ? "A" : "B"))
    }.drawing(in: .viewport)
    let reader = CellLayerShader { _, layer, _ in layer.sample(at: .zero) }
      .drawing(in: .rect(.init(origin: .zero, size: .init(width: 1, height: 1))))
    let size = CellSize(width: 80, height: 1)
    for width in [80, 65_537] {
      let node = DrawNode(
        identity: testIdentity("tiled"),
        bounds: .init(origin: .zero, size: .init(width: width, height: 1)),
        drawEffects: .init([pass(painter), .cellLayer(.init(reader, offset: .layerBounds))]))
      let frame = Rasterizer().rasterizeCollectingVisibleIdentities(
        node, minimumSize: size, maximumSize: size, previousSurface: nil, damage: nil)
      #expect(frame.surface.cells[0][0].character == "A")
    }
  }

  @Test("Group isolation preserves the ancestor viewport of a source kernel")
  func groupedViewport() {
    let painter = CellLayerShader { _, _, context in
      .glyph(CellGlyph(context.viewport.size.width == 12 ? "A" : "B"))
    }
    for group in [false, true] {
      let node = DrawNode(
        identity: testIdentity("group"),
        bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
        drawEffects: .init(group ? [pass(painter), .compositingGroup] : [pass(painter)]))
      let parent = DrawNode(
        identity: testIdentity("root"), bounds: bounds, clipBounds: bounds, children: [node])
      #expect(Rasterizer().rasterize(parent).cells[0][0].character == "A")
    }
  }
}

extension CellEffectRasterTests {
  @Test("An empty subject requesting viewport drawing takes no snapshot")
  func emptySource() {
    let shader = CellLayerShader { _, _, _ in .glyph(CellGlyph("X")) }.drawing(in: .viewport)
    let node = DrawNode(
      identity: testIdentity("empty"), bounds: .zero,
      drawEffects: .init([.cellLayer(.init(shader, offset: .layerBounds))]))
    let probe = RasterWorkProbe()
    let frame = Rasterizer.$workProbe.withValue(probe) {
      Rasterizer().rasterize(node, minimumSize: bounds.size)
    }
    #expect(frame.cells.flatMap { $0 }.allSatisfy { $0 == .empty })
    #expect(probe.snapshot().cellEffectCaptures == 0)
  }
}

extension CellEffectRasterTests {
  @Test("Ordered scratch repairs both spans, copies holes, and can blit from itself")
  func bufferBlits() {
    let bounds = CellRect(origin: .init(x: -3, y: 2), size: .init(width: 7, height: 1))
    let point: (Int) -> CellPoint = { .init(x: $0, y: 2) }
    var buffer = CellEffectBuffer(bounds: bounds)
    buffer.set(CellGlyph("界", paint: .init(foreground: .indexed(196))), at: point(-3))
    buffer.set(CellGlyph("Q"), at: point(-1))
    buffer.set(CellGlyph("語"), at: point(1))
    let original = buffer.snapshot()
    buffer.blit(
      original, from: .init(origin: point(-3), size: .init(width: 5, height: 1)), to: point(-2))
    #expect(buffer.sample(at: point(-3)) == .empty)
    #expect(buffer.sample(at: point(-1)) == .continuation(columnsBack: 1))
    #expect(buffer.snapshot().glyph(occupying: point(-1))?.paint.foreground == .indexed(196))
    #expect(buffer.snapshot().glyph(occupying: point(0))?.character == "Q")
    #expect(buffer.sample(at: point(1)) == .empty && buffer.sample(at: point(2)) == .empty)
    #expect(original.glyph(occupying: point(2))?.character == "語")
    buffer.set(CellGlyph("界"), at: point(3))
    #expect(buffer.sample(at: point(3)) == .empty)
    buffer.clear(at: point(100))
    buffer.clear(at: point(-1))
    #expect(buffer.sample(at: point(-2)) == .empty)
  }

  @Test(
    "Two ordered writes collide and the next read forwards the first particle beyond the subject")
  func orderedCollision() {
    let rootBounds = CellRect(origin: .zero, size: .init(width: 6, height: 1))
    var root = DrawNode(
      identity: testIdentity("floor"), bounds: rootBounds,
      commands: [
        TextPaintFamily.plain.command(bounds: rootBounds, lines: ["......"], style: .init())
      ])
    let slot = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 3, height: 1))
    let shader = CellLayerShader.region { source, buffer, context in
      #expect(buffer.bounds == context.viewport && source.readableBounds == context.sourceBounds)
      let a = CellPoint.zero
      let b = CellPoint(x: 1, y: 0)
      let outside = CellPoint(x: 4, y: 0)
      guard case .glyph(var first) = buffer.sample(at: a) else { return }
      first.paint.foreground = .indexed(70)
      buffer.set(first, at: b)
      buffer.clear(at: a)
      guard case .glyph(let moved) = buffer.sample(at: b) else { return }
      buffer.set(moved, at: outside)
      buffer.clear(at: b)
      #expect(source.glyph(occupying: b)?.character == "B")
    }.drawing(in: .viewport)
    root.children = [
      DrawNode(
        identity: testIdentity("particles"), bounds: slot,
        drawEffects: .init([pass(shader)]),
        commands: [TextPaintFamily.plain.command(bounds: slot, lines: ["ABC"], style: .init())])
    ]
    let row = Rasterizer().rasterize(root).cells[0]
    #expect(row.map(\.character) == Array("...C.A"))
    #expect(row[5].style?.foregroundPaletteIndex == 70)
  }
}
