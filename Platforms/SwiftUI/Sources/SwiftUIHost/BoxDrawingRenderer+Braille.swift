import CoreGraphics
import Foundation

// Braille pattern rendering (U+2800–U+28FF).
//
// `drawBraille` treats a braille code point as a 2×4 sub-pixel mosaic: each
// set bit fills its sub-cell rectangle solid (rather than drawing a font-style
// dot), so partial fills connect to their neighbours and `⣿` becomes
// pixel-identical to `█`. `brailleSubpixels` is the bit → (column, row)
// layout, listed in raster order.
//
// Split out of `BoxDrawingRenderer.swift`. `drawBraille` is widened from
// `fileprivate` to file-internal so the `draw` dispatcher can reach it;
// `brailleSubpixels` stays file-scoped here with its only caller.

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

  static func drawBraille(
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
