import CoreGraphics
import Foundation

// Block element rendering (U+2580–U+259F).
//
// `drawBlockElement` is the dispatch entry point for the block-element range:
// half blocks, the eighth-block ramps (▁▂▃▄▅▆▇█ and ▉▊▋▌▍▎▏), the shading
// glyphs (░▒▓), and the quadrant glyphs. `fillQuadrants` and `drawShade` are
// its private helpers; `ShadeDensity` names the three shading levels.
//
// Split out of `BoxDrawingRenderer.swift`. `drawBlockElement` is widened from
// `fileprivate` to file-internal so the `draw` dispatcher can reach it; its
// helpers stay file-scoped here. `Corner` (used by `fillQuadrants`) stays in
// `BoxDrawingRenderer.swift`.

extension BoxDrawingRenderer {
  static func drawBlockElement(
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
