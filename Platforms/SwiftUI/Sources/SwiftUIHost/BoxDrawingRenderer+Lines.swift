import CoreGraphics
import Foundation

// Box-drawing line primitives (U+2500–U+257F).
//
// `drawBoxDrawing` is the dispatch entry point for the box-drawing block: it
// looks up a code point in the `lineSpecs` table (full lines, corners,
// T-junctions, crosses, doubles, half-lines — each described by a 4-edge
// `Spec`) and renders it via `drawCellLines`, or falls through to the
// procedural dashed / diagonal / arc renderers.
//
// Split out of `BoxDrawingRenderer.swift`. `drawBoxDrawing` is widened from
// `private` to file-internal so the `draw` dispatcher can still reach it; the
// `lineSpecs` table and the line-primitive helpers stay file-scoped here
// because their only callers travel with them. The shared geometry types
// (`Spec`, `LineWeight`, `StrokeMetrics`, `Direction`, `Corner`,
// `strokeMetrics`) stay in `BoxDrawingRenderer.swift`, widened to file-internal.

extension BoxDrawingRenderer {
  static func drawBoxDrawing(
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

  // MARK: - Line drawing primitives

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
