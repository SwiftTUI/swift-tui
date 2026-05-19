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
  //
  // Shared geometry types for the renderer. Widened from `fileprivate` to
  // file-internal so the Lines / Blocks / Braille extensions in their own
  // files can reach them. They stay namespaced under `BoxDrawingRenderer`.

  enum LineWeight: UInt8 {
    case none = 0
    case light
    case heavy
    case double
  }

  typealias Spec = (n: LineWeight, e: LineWeight, s: LineWeight, w: LineWeight)

  struct StrokeMetrics {
    let light: CGFloat
    let heavy: CGFloat
    let doubleGap: CGFloat
  }

  static func strokeMetrics(for rect: CGRect) -> StrokeMetrics {
    let unit = max(1, (min(rect.width, rect.height) / 16).rounded())
    return StrokeMetrics(light: unit, heavy: unit * 2, doubleGap: unit)
  }

  enum Direction {
    case north, east, south, west
  }

  enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight
  }
}

// The three glyph-block renderers each live in their own file:
// - box-drawing lines (U+2500–U+257F) → `BoxDrawingRenderer+Lines.swift`
// - block elements (U+2580–U+259F) → `BoxDrawingRenderer+Blocks.swift`
// - braille patterns (U+2800–U+28FF) → `BoxDrawingRenderer+Braille.swift`
