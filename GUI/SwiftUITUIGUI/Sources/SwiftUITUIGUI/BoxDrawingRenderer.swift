import CoreGraphics
import Foundation

/// Procedural renderer for Unicode box-drawing characters (U+2500–U+257F),
/// block elements (U+2580–U+259F), and braille patterns (U+2800–U+28FF).
///
/// Glyphs from these blocks are designed to fill the em-square exactly and
/// tile seamlessly between adjacent cells. Most fonts ship them at the em
/// size, but terminal cells include extra height for descenders + leading,
/// which produces a visible vertical gap when rendering box-drawing columns
/// from the font. Painting them procedurally to the cell rect guarantees
/// pixel-perfect tiling regardless of font metrics or cell dimensions.
///
/// Braille glyphs are treated as a 2×4 sub-pixel mosaic (matching
/// `BrailleCanvas`): each set bit fills its sub-cell rectangle solid rather
/// than drawing a font-style dot, so partial fills connect to their
/// neighbours and `⣿` becomes pixel-identical to `█`.
enum BoxDrawingRenderer {
  static func canRender(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first
    else {
      return false
    }
    let value = scalar.value
    return (0x2500...0x259F).contains(value) || (0x2800...0x28FF).contains(value)
  }

  /// Paints `character` into `rect` using `color`. Returns `true` if the
  /// glyph was drawn; `false` if the renderer doesn't handle this codepoint
  /// and the caller should fall back to font rendering.
  @discardableResult
  static func draw(
    character: Character,
    in rect: CGRect,
    color: CGColor,
    context: CGContext
  ) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first
    else {
      return false
    }
    let codePoint = scalar.value

    context.saveGState()
    defer { context.restoreGState() }
    context.setFillColor(color)
    context.setStrokeColor(color)

    if (0x2500...0x257F).contains(codePoint) {
      return drawBoxDrawing(codePoint: codePoint, rect: rect, context: context)
    }
    if (0x2580...0x259F).contains(codePoint) {
      return drawBlockElement(codePoint: codePoint, rect: rect, context: context)
    }
    if (0x2800...0x28FF).contains(codePoint) {
      return drawBraille(codePoint: codePoint, rect: rect, context: context)
    }
    return false
  }

  // MARK: - Internal types

  fileprivate enum LineWeight: UInt8 {
    case none = 0
    case light
    case heavy
    case double
  }

  fileprivate typealias Spec = (n: LineWeight, e: LineWeight, s: LineWeight, w: LineWeight)

  fileprivate struct StrokeMetrics {
    let light: CGFloat
    let heavy: CGFloat
    let doubleGap: CGFloat
  }

  fileprivate static func strokeMetrics(for rect: CGRect) -> StrokeMetrics {
    let unit = max(1, (min(rect.width, rect.height) / 16).rounded())
    return StrokeMetrics(light: unit, heavy: unit * 2, doubleGap: unit)
  }

  fileprivate enum Direction {
    case north, east, south, west
  }

  fileprivate enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight
  }

  // MARK: - Box drawing (U+2500–U+257F)

  private static func drawBoxDrawing(
    codePoint: UInt32,
    rect: CGRect,
    context: CGContext
  ) -> Bool {
    if let spec = lineSpecs[codePoint] {
      drawCellLines(spec: spec, in: rect, context: context)
      return true
    }

    switch codePoint {
    // Triple/quadruple/double dashed horizontals & verticals.
    case 0x2504: drawDashedHorizontal(rect: rect, weight: .light, segments: 3, context: context)
    case 0x2505: drawDashedHorizontal(rect: rect, weight: .heavy, segments: 3, context: context)
    case 0x2506: drawDashedVertical(rect: rect, weight: .light, segments: 3, context: context)
    case 0x2507: drawDashedVertical(rect: rect, weight: .heavy, segments: 3, context: context)
    case 0x2508: drawDashedHorizontal(rect: rect, weight: .light, segments: 4, context: context)
    case 0x2509: drawDashedHorizontal(rect: rect, weight: .heavy, segments: 4, context: context)
    case 0x250A: drawDashedVertical(rect: rect, weight: .light, segments: 4, context: context)
    case 0x250B: drawDashedVertical(rect: rect, weight: .heavy, segments: 4, context: context)
    case 0x254C: drawDashedHorizontal(rect: rect, weight: .light, segments: 2, context: context)
    case 0x254D: drawDashedHorizontal(rect: rect, weight: .heavy, segments: 2, context: context)
    case 0x254E: drawDashedVertical(rect: rect, weight: .light, segments: 2, context: context)
    case 0x254F: drawDashedVertical(rect: rect, weight: .heavy, segments: 2, context: context)

    // Diagonals.
    case 0x2571: drawDiagonal(rect: rect, descending: false, context: context)
    case 0x2572: drawDiagonal(rect: rect, descending: true, context: context)
    case 0x2573:
      drawDiagonal(rect: rect, descending: false, context: context)
      drawDiagonal(rect: rect, descending: true, context: context)

    // Light arc corners.
    case 0x256D: drawArc(rect: rect, corner: .topLeft, context: context)
    case 0x256E: drawArc(rect: rect, corner: .topRight, context: context)
    case 0x256F: drawArc(rect: rect, corner: .bottomRight, context: context)
    case 0x2570: drawArc(rect: rect, corner: .bottomLeft, context: context)

    default:
      return false
    }
    return true
  }

  // MARK: - Line spec table

  private static let lineSpecs: [UInt32: Spec] = [
    // Horizontal & vertical full lines.
    0x2500: (.none, .light, .none, .light),  // ─
    0x2501: (.none, .heavy, .none, .heavy),  // ━
    0x2502: (.light, .none, .light, .none),  // │
    0x2503: (.heavy, .none, .heavy, .none),  // ┃

    // Sharp corners (16 permutations of light/heavy).
    0x250C: (.none, .light, .light, .none),  // ┌
    0x250D: (.none, .heavy, .light, .none),  // ┍
    0x250E: (.none, .light, .heavy, .none),  // ┎
    0x250F: (.none, .heavy, .heavy, .none),  // ┏
    0x2510: (.none, .none, .light, .light),  // ┐
    0x2511: (.none, .none, .light, .heavy),  // ┑
    0x2512: (.none, .none, .heavy, .light),  // ┒
    0x2513: (.none, .none, .heavy, .heavy),  // ┓
    0x2514: (.light, .light, .none, .none),  // └
    0x2515: (.light, .heavy, .none, .none),  // ┕
    0x2516: (.heavy, .light, .none, .none),  // ┖
    0x2517: (.heavy, .heavy, .none, .none),  // ┗
    0x2518: (.light, .none, .none, .light),  // ┘
    0x2519: (.light, .none, .none, .heavy),  // ┙
    0x251A: (.heavy, .none, .none, .light),  // ┚
    0x251B: (.heavy, .none, .none, .heavy),  // ┛

    // T-junctions: vertical + right.
    0x251C: (.light, .light, .light, .none),  // ├
    0x251D: (.light, .heavy, .light, .none),  // ┝
    0x251E: (.heavy, .light, .light, .none),  // ┞
    0x251F: (.light, .light, .heavy, .none),  // ┟
    0x2520: (.heavy, .light, .heavy, .none),  // ┠
    0x2521: (.heavy, .heavy, .light, .none),  // ┡
    0x2522: (.light, .heavy, .heavy, .none),  // ┢
    0x2523: (.heavy, .heavy, .heavy, .none),  // ┣

    // T-junctions: vertical + left.
    0x2524: (.light, .none, .light, .light),  // ┤
    0x2525: (.light, .none, .light, .heavy),  // ┥
    0x2526: (.heavy, .none, .light, .light),  // ┦
    0x2527: (.light, .none, .heavy, .light),  // ┧
    0x2528: (.heavy, .none, .heavy, .light),  // ┨
    0x2529: (.heavy, .none, .light, .heavy),  // ┩
    0x252A: (.light, .none, .heavy, .heavy),  // ┪
    0x252B: (.heavy, .none, .heavy, .heavy),  // ┫

    // T-junctions: down + horizontal.
    0x252C: (.none, .light, .light, .light),  // ┬
    0x252D: (.none, .light, .light, .heavy),  // ┭
    0x252E: (.none, .heavy, .light, .light),  // ┮
    0x252F: (.none, .heavy, .light, .heavy),  // ┯
    0x2530: (.none, .light, .heavy, .light),  // ┰
    0x2531: (.none, .light, .heavy, .heavy),  // ┱
    0x2532: (.none, .heavy, .heavy, .light),  // ┲
    0x2533: (.none, .heavy, .heavy, .heavy),  // ┳

    // T-junctions: up + horizontal.
    0x2534: (.light, .light, .none, .light),  // ┴
    0x2535: (.light, .light, .none, .heavy),  // ┵
    0x2536: (.light, .heavy, .none, .light),  // ┶
    0x2537: (.light, .heavy, .none, .heavy),  // ┷
    0x2538: (.heavy, .light, .none, .light),  // ┸
    0x2539: (.heavy, .light, .none, .heavy),  // ┹
    0x253A: (.heavy, .heavy, .none, .light),  // ┺
    0x253B: (.heavy, .heavy, .none, .heavy),  // ┻

    // Crosses.
    0x253C: (.light, .light, .light, .light),  // ┼
    0x253D: (.light, .light, .light, .heavy),  // ┽
    0x253E: (.light, .heavy, .light, .light),  // ┾
    0x253F: (.light, .heavy, .light, .heavy),  // ┿
    0x2540: (.heavy, .light, .light, .light),  // ╀
    0x2541: (.light, .light, .heavy, .light),  // ╁
    0x2542: (.heavy, .light, .heavy, .light),  // ╂
    0x2543: (.heavy, .light, .light, .heavy),  // ╃
    0x2544: (.heavy, .heavy, .light, .light),  // ╄
    0x2545: (.light, .light, .heavy, .heavy),  // ╅
    0x2546: (.light, .heavy, .heavy, .light),  // ╆
    0x2547: (.heavy, .heavy, .light, .heavy),  // ╇
    0x2548: (.light, .heavy, .heavy, .heavy),  // ╈
    0x2549: (.heavy, .light, .heavy, .heavy),  // ╉
    0x254A: (.heavy, .heavy, .heavy, .light),  // ╊
    0x254B: (.heavy, .heavy, .heavy, .heavy),  // ╋

    // Doubles.
    0x2550: (.none, .double, .none, .double),  // ═
    0x2551: (.double, .none, .double, .none),  // ║
    0x2552: (.none, .double, .light, .none),  // ╒
    0x2553: (.none, .light, .double, .none),  // ╓
    0x2554: (.none, .double, .double, .none),  // ╔
    0x2555: (.none, .none, .light, .double),  // ╕
    0x2556: (.none, .none, .double, .light),  // ╖
    0x2557: (.none, .none, .double, .double),  // ╗
    0x2558: (.light, .double, .none, .none),  // ╘
    0x2559: (.double, .light, .none, .none),  // ╙
    0x255A: (.double, .double, .none, .none),  // ╚
    0x255B: (.light, .none, .none, .double),  // ╛
    0x255C: (.double, .none, .none, .light),  // ╜
    0x255D: (.double, .none, .none, .double),  // ╝
    0x255E: (.light, .double, .light, .none),  // ╞
    0x255F: (.double, .light, .double, .none),  // ╟
    0x2560: (.double, .double, .double, .none),  // ╠
    0x2561: (.light, .none, .light, .double),  // ╡
    0x2562: (.double, .none, .double, .light),  // ╢
    0x2563: (.double, .none, .double, .double),  // ╣
    0x2564: (.none, .double, .light, .double),  // ╤
    0x2565: (.none, .light, .double, .light),  // ╥
    0x2566: (.none, .double, .double, .double),  // ╦
    0x2567: (.light, .double, .none, .double),  // ╧
    0x2568: (.double, .light, .none, .light),  // ╨
    0x2569: (.double, .double, .none, .double),  // ╩
    0x256A: (.light, .double, .light, .double),  // ╪
    0x256B: (.double, .light, .double, .light),  // ╫
    0x256C: (.double, .double, .double, .double),  // ╬

    // Half-lines.
    0x2574: (.none, .none, .none, .light),  // ╴
    0x2575: (.light, .none, .none, .none),  // ╵
    0x2576: (.none, .light, .none, .none),  // ╶
    0x2577: (.none, .none, .light, .none),  // ╷
    0x2578: (.none, .none, .none, .heavy),  // ╸
    0x2579: (.heavy, .none, .none, .none),  // ╹
    0x257A: (.none, .heavy, .none, .none),  // ╺
    0x257B: (.none, .none, .heavy, .none),  // ╻
    0x257C: (.none, .heavy, .none, .light),  // ╼
    0x257D: (.light, .none, .heavy, .none),  // ╽
    0x257E: (.none, .light, .none, .heavy),  // ╾
    0x257F: (.heavy, .none, .light, .none),  // ╿
  ]
}

// MARK: - Line drawing primitives

extension BoxDrawingRenderer {
  fileprivate static func drawCellLines(
    spec: Spec,
    in rect: CGRect,
    context: CGContext
  ) {
    let metrics = strokeMetrics(for: rect)
    // Draw heavier weights last so they visually dominate at the centre.
    let edges: [(LineWeight, Direction)] = [
      (spec.n, .north),
      (spec.e, .east),
      (spec.s, .south),
      (spec.w, .west),
    ]
    let edgePairs = edges.sorted(by: { $0.0.rawValue < $1.0.rawValue })
    for (weight, direction) in edgePairs {
      drawHalfStroke(
        weight: weight,
        direction: direction,
        in: rect,
        metrics: metrics,
        context: context
      )
    }
  }

  /// Fills a half-stroke from the cell's centre to the named edge. The
  /// stroke extends slightly past the centre by `thickness/2` so adjacent
  /// directions form a clean butt join through the centre point.
  fileprivate static func drawHalfStroke(
    weight: LineWeight,
    direction: Direction,
    in rect: CGRect,
    metrics: StrokeMetrics,
    context: CGContext
  ) {
    guard weight != .none else { return }
    let cx = rect.midX
    let cy = rect.midY

    func segment(thickness t: CGFloat, perpendicularOffset offset: CGFloat) {
      switch direction {
      case .north:
        context.fill(
          CGRect(
            x: cx - t / 2 + offset,
            y: rect.minY,
            width: t,
            height: cy - rect.minY + t / 2
          ))
      case .south:
        context.fill(
          CGRect(
            x: cx - t / 2 + offset,
            y: cy - t / 2,
            width: t,
            height: rect.maxY - cy + t / 2
          ))
      case .west:
        context.fill(
          CGRect(
            x: rect.minX,
            y: cy - t / 2 + offset,
            width: cx - rect.minX + t / 2,
            height: t
          ))
      case .east:
        context.fill(
          CGRect(
            x: cx - t / 2,
            y: cy - t / 2 + offset,
            width: rect.maxX - cx + t / 2,
            height: t
          ))
      }
    }

    switch weight {
    case .none:
      break
    case .light:
      segment(thickness: metrics.light, perpendicularOffset: 0)
    case .heavy:
      segment(thickness: metrics.heavy, perpendicularOffset: 0)
    case .double:
      let t = metrics.light
      let off = (t + metrics.doubleGap) / 2
      segment(thickness: t, perpendicularOffset: -off)
      segment(thickness: t, perpendicularOffset: off)
    }
  }

  // MARK: Dashed

  fileprivate static func drawDashedHorizontal(
    rect: CGRect,
    weight: LineWeight,
    segments: Int,
    context: CGContext
  ) {
    let metrics = strokeMetrics(for: rect)
    let thickness = (weight == .heavy) ? metrics.heavy : metrics.light
    let segmentWidth = rect.width / CGFloat(segments)
    let dashWidth = segmentWidth * 0.55
    let gapWidth = segmentWidth - dashWidth
    let cy = rect.midY
    for i in 0..<segments {
      let x = rect.minX + CGFloat(i) * segmentWidth + gapWidth / 2
      context.fill(
        CGRect(x: x, y: cy - thickness / 2, width: dashWidth, height: thickness)
      )
    }
  }

  fileprivate static func drawDashedVertical(
    rect: CGRect,
    weight: LineWeight,
    segments: Int,
    context: CGContext
  ) {
    let metrics = strokeMetrics(for: rect)
    let thickness = (weight == .heavy) ? metrics.heavy : metrics.light
    let segmentHeight = rect.height / CGFloat(segments)
    let dashHeight = segmentHeight * 0.55
    let gapHeight = segmentHeight - dashHeight
    let cx = rect.midX
    for i in 0..<segments {
      let y = rect.minY + CGFloat(i) * segmentHeight + gapHeight / 2
      context.fill(
        CGRect(x: cx - thickness / 2, y: y, width: thickness, height: dashHeight)
      )
    }
  }

  // MARK: Diagonals

  fileprivate static func drawDiagonal(
    rect: CGRect,
    descending: Bool,
    context: CGContext
  ) {
    let metrics = strokeMetrics(for: rect)
    context.saveGState()
    context.setLineWidth(metrics.light)
    context.setLineCap(.square)
    if descending {
      context.move(to: CGPoint(x: rect.minX, y: rect.minY))
      context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    } else {
      context.move(to: CGPoint(x: rect.maxX, y: rect.minY))
      context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }
    context.strokePath()
    context.restoreGState()
  }

  // MARK: Arcs

  fileprivate static func drawArc(
    rect: CGRect,
    corner: Corner,
    context: CGContext
  ) {
    let metrics = strokeMetrics(for: rect)
    let cx = rect.midX
    let cy = rect.midY
    let radius = min(rect.width, rect.height) * 0.4
    let kappa = radius * 0.5523

    context.saveGState()
    context.setLineWidth(metrics.light)
    context.setLineCap(.butt)

    switch corner {
    case .topLeft:  // ╭ — straight strokes go right and down; arc rounds the corner.
      context.move(to: CGPoint(x: cx, y: cy + radius))
      context.addLine(to: CGPoint(x: cx, y: rect.maxY))
      context.move(to: CGPoint(x: cx + radius, y: cy))
      context.addLine(to: CGPoint(x: rect.maxX, y: cy))
      context.move(to: CGPoint(x: cx, y: cy + radius))
      context.addCurve(
        to: CGPoint(x: cx + radius, y: cy),
        control1: CGPoint(x: cx, y: cy + radius - kappa),
        control2: CGPoint(x: cx + radius - kappa, y: cy)
      )
    case .topRight:  // ╮ — straight strokes go left and down.
      context.move(to: CGPoint(x: cx, y: cy + radius))
      context.addLine(to: CGPoint(x: cx, y: rect.maxY))
      context.move(to: CGPoint(x: cx - radius, y: cy))
      context.addLine(to: CGPoint(x: rect.minX, y: cy))
      context.move(to: CGPoint(x: cx - radius, y: cy))
      context.addCurve(
        to: CGPoint(x: cx, y: cy + radius),
        control1: CGPoint(x: cx - radius + kappa, y: cy),
        control2: CGPoint(x: cx, y: cy + radius - kappa)
      )
    case .bottomRight:  // ╯ — straight strokes go left and up.
      context.move(to: CGPoint(x: cx, y: cy - radius))
      context.addLine(to: CGPoint(x: cx, y: rect.minY))
      context.move(to: CGPoint(x: cx - radius, y: cy))
      context.addLine(to: CGPoint(x: rect.minX, y: cy))
      context.move(to: CGPoint(x: cx, y: cy - radius))
      context.addCurve(
        to: CGPoint(x: cx - radius, y: cy),
        control1: CGPoint(x: cx, y: cy - radius + kappa),
        control2: CGPoint(x: cx - radius + kappa, y: cy)
      )
    case .bottomLeft:  // ╰ — straight strokes go right and up.
      context.move(to: CGPoint(x: cx, y: cy - radius))
      context.addLine(to: CGPoint(x: cx, y: rect.minY))
      context.move(to: CGPoint(x: cx + radius, y: cy))
      context.addLine(to: CGPoint(x: rect.maxX, y: cy))
      context.move(to: CGPoint(x: cx + radius, y: cy))
      context.addCurve(
        to: CGPoint(x: cx, y: cy - radius),
        control1: CGPoint(x: cx + radius - kappa, y: cy),
        control2: CGPoint(x: cx, y: cy - radius + kappa)
      )
    }

    context.strokePath()
    context.restoreGState()
  }
}

// MARK: - Block elements (U+2580–U+259F)

extension BoxDrawingRenderer {
  fileprivate static func drawBlockElement(
    codePoint: UInt32,
    rect: CGRect,
    context: CGContext
  ) -> Bool {
    let r = rect
    let w = r.width
    let h = r.height

    func eighthFromBottom(_ k: CGFloat) -> CGRect {
      // Lower k/8 of the cell. k = 1...8.
      let height = h * k / 8
      return CGRect(x: r.minX, y: r.maxY - height, width: w, height: height)
    }

    func leftFraction(_ k: CGFloat) -> CGRect {
      // Left k/8 of the cell. k = 1...8.
      let width = w * k / 8
      return CGRect(x: r.minX, y: r.minY, width: width, height: h)
    }

    switch codePoint {
    case 0x2580:  // ▀ Upper Half Block
      context.fill(CGRect(x: r.minX, y: r.minY, width: w, height: h / 2))

    // Lower N/8 blocks (▁▂▃▄▅▆▇█).
    case 0x2581: context.fill(eighthFromBottom(1))
    case 0x2582: context.fill(eighthFromBottom(2))
    case 0x2583: context.fill(eighthFromBottom(3))
    case 0x2584: context.fill(eighthFromBottom(4))
    case 0x2585: context.fill(eighthFromBottom(5))
    case 0x2586: context.fill(eighthFromBottom(6))
    case 0x2587: context.fill(eighthFromBottom(7))
    case 0x2588: context.fill(r)

    // Left N/8 blocks (▉▊▋▌▍▎▏).
    case 0x2589: context.fill(leftFraction(7))
    case 0x258A: context.fill(leftFraction(6))
    case 0x258B: context.fill(leftFraction(5))
    case 0x258C: context.fill(leftFraction(4))
    case 0x258D: context.fill(leftFraction(3))
    case 0x258E: context.fill(leftFraction(2))
    case 0x258F: context.fill(leftFraction(1))

    case 0x2590:  // ▐ Right Half Block
      context.fill(CGRect(x: r.minX + w / 2, y: r.minY, width: w / 2, height: h))

    // Shading.
    case 0x2591: drawShade(rect: r, density: .light, context: context)
    case 0x2592: drawShade(rect: r, density: .medium, context: context)
    case 0x2593: drawShade(rect: r, density: .dark, context: context)

    case 0x2594:  // ▔ Upper One Eighth
      context.fill(CGRect(x: r.minX, y: r.minY, width: w, height: h / 8))
    case 0x2595:  // ▕ Right One Eighth
      context.fill(CGRect(x: r.maxX - w / 8, y: r.minY, width: w / 8, height: h))

    // Quadrants.
    case 0x2596: fillQuadrants([.bottomLeft], in: r, context: context)  // ▖
    case 0x2597: fillQuadrants([.bottomRight], in: r, context: context)  // ▗
    case 0x2598: fillQuadrants([.topLeft], in: r, context: context)  // ▘
    case 0x2599:  // ▙
      fillQuadrants([.topLeft, .bottomLeft, .bottomRight], in: r, context: context)
    case 0x259A:  // ▚
      fillQuadrants([.topLeft, .bottomRight], in: r, context: context)
    case 0x259B:  // ▛
      fillQuadrants([.topLeft, .topRight, .bottomLeft], in: r, context: context)
    case 0x259C:  // ▜
      fillQuadrants([.topLeft, .topRight, .bottomRight], in: r, context: context)
    case 0x259D: fillQuadrants([.topRight], in: r, context: context)  // ▝
    case 0x259E:  // ▞
      fillQuadrants([.topRight, .bottomLeft], in: r, context: context)
    case 0x259F:  // ▟
      fillQuadrants([.topRight, .bottomLeft, .bottomRight], in: r, context: context)

    default:
      return false
    }
    return true
  }

  fileprivate static func fillQuadrants(
    _ quadrants: [Corner],
    in rect: CGRect,
    context: CGContext
  ) {
    let halfW = rect.width / 2
    let halfH = rect.height / 2
    for quadrant in quadrants {
      let origin: CGPoint
      switch quadrant {
      case .topLeft:
        origin = CGPoint(x: rect.minX, y: rect.minY)
      case .topRight:
        origin = CGPoint(x: rect.minX + halfW, y: rect.minY)
      case .bottomLeft:
        origin = CGPoint(x: rect.minX, y: rect.minY + halfH)
      case .bottomRight:
        origin = CGPoint(x: rect.minX + halfW, y: rect.minY + halfH)
      }
      context.fill(CGRect(origin: origin, size: CGSize(width: halfW, height: halfH)))
    }
  }

  fileprivate enum ShadeDensity {
    case light, medium, dark
  }

  /// Fills `rect` with a 2×2 dot pattern that approximates the requested
  /// density. Implemented as direct fills rather than a `CGPattern` so the
  /// pattern aligns to the cell origin and tiles seamlessly between
  /// adjacent cells. One filled cell of the 2×2 unit corresponds to 25 %
  /// coverage; light = 1, medium = 2, dark = 3 of the four pixels.
  fileprivate static func drawShade(
    rect: CGRect,
    density: ShadeDensity,
    context: CGContext
  ) {
    let pixels: [(Int, Int)]
    switch density {
    case .light:
      pixels = [(0, 0)]
    case .medium:
      pixels = [(0, 0), (1, 1)]
    case .dark:
      pixels = [(0, 0), (1, 0), (0, 1)]
    }

    let block: CGFloat = 2
    var y = rect.minY
    while y < rect.maxY {
      var x = rect.minX
      while x < rect.maxX {
        for (px, py) in pixels {
          let dotX = x + CGFloat(px)
          let dotY = y + CGFloat(py)
          guard dotX < rect.maxX, dotY < rect.maxY else { continue }
          context.fill(CGRect(x: dotX, y: dotY, width: 1, height: 1))
        }
        x += block
      }
      y += block
    }
  }
}

// MARK: - Braille patterns (U+2800–U+28FF)

extension BoxDrawingRenderer {
  /// Bit → (column, row) layout for the 2×4 braille mosaic. Mirrors
  /// `BrailleCell.bit(x:y:)` in `Sources/Core/BrailleCanvas.swift`. Listed
  /// in raster order (left-to-right, top-to-bottom) so adjacent rectangles
  /// are drawn next to each other and a fully-set mask paints the cell in
  /// four contiguous horizontal strips.
  fileprivate static let brailleSubpixels: [(bit: UInt8, col: Int, row: Int)] = [
    (0x01, 0, 0), (0x08, 1, 0),
    (0x02, 0, 1), (0x10, 1, 1),
    (0x04, 0, 2), (0x20, 1, 2),
    (0x40, 0, 3), (0x80, 1, 3),
  ]

  fileprivate static func drawBraille(
    codePoint: UInt32,
    rect: CGRect,
    context: CGContext
  ) -> Bool {
    let mask = UInt8(codePoint - 0x2800)
    if mask == 0 {
      // U+2800 (BRAILLE PATTERN BLANK) is whitespace — render nothing,
      // matching the empty mask in BrailleCanvas.
      return true
    }

    let cellWidth = rect.width / 2
    let rowHeight = rect.height / 4

    for sub in brailleSubpixels where mask & sub.bit != 0 {
      let x = rect.minX + CGFloat(sub.col) * cellWidth
      let y = rect.minY + CGFloat(sub.row) * rowHeight
      context.fill(CGRect(x: x, y: y, width: cellWidth, height: rowHeight))
    }
    return true
  }
}
