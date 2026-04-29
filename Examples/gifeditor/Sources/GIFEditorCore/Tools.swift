import Foundation

/// The five core editing tools, plus eyedropper as a read-only sixth.
public enum EditorTool: String, Hashable, Sendable, CaseIterable, Codable {
  case pen
  case eraser
  case fill
  case gradient
  case marquee
  case eyedropper

  public var label: String {
    switch self {
    case .pen: return "Pen"
    case .eraser: return "Eraser"
    case .fill: return "Fill"
    case .gradient: return "Gradient"
    case .marquee: return "Marquee"
    case .eyedropper: return "Eyedropper"
    }
  }

  /// 1-character glyph used by the toolbox for compact display.
  public var glyph: String {
    switch self {
    case .pen: return "P"
    case .eraser: return "E"
    case .fill: return "B"
    case .gradient: return "G"
    case .marquee: return "M"
    case .eyedropper: return "I"
    }
  }
}

/// A rectangular selection. Tools that respect selection (fill,
/// gradient) are clipped to it; tools that don't (pen, eraser) ignore
/// it.
public struct Selection: Hashable, Sendable, Codable {
  public var rect: PixelRect

  public init(rect: PixelRect) {
    self.rect = rect
  }
}

/// Implementations of the editor tools. Every function takes a buffer
/// and returns the edited buffer — that lets the view model wrap each
/// edit in an undoable command without the tool itself knowing about
/// undo. Tools never throw; out-of-range arguments are clamped/ignored.
public enum ToolOps {

  /// Pen: write `color` at `point`.
  public static func pen(
    on buffer: PixelBuffer,
    at point: PixelPoint,
    color: PaletteIndex
  ) -> PixelBuffer {
    var copy = buffer
    copy[point] = color
    return copy
  }

  /// Eraser: clear the pixel at `point` to transparent (`nil`).
  public static func erase(
    on buffer: PixelBuffer,
    at point: PixelPoint
  ) -> PixelBuffer {
    var copy = buffer
    copy[point] = nil
    return copy
  }

  /// 4-connected flood fill starting at `point`. Replaces every cell
  /// matching the seed value with `color`. Confined to `selection` when
  /// non-nil.
  public static func fill(
    on buffer: PixelBuffer,
    at point: PixelPoint,
    color: PaletteIndex,
    selection: Selection? = nil
  ) -> PixelBuffer {
    guard buffer.size.contains(point) else { return buffer }
    let seed = buffer[point]
    if seed == color { return buffer }
    var copy = buffer
    var stack: [PixelPoint] = [point]
    let bounds =
      selection?.rect
      ?? PixelRect(
        x: 0, y: 0, width: buffer.size.width, height: buffer.size.height
      )
    while let p = stack.popLast() {
      if !bounds.contains(p) { continue }
      if copy[p] != seed { continue }
      copy.setUnchecked(p, to: color)
      stack.append(PixelPoint(x: p.x - 1, y: p.y))
      stack.append(PixelPoint(x: p.x + 1, y: p.y))
      stack.append(PixelPoint(x: p.x, y: p.y - 1))
      stack.append(PixelPoint(x: p.x, y: p.y + 1))
    }
    return copy
  }

  /// Linear gradient between `startColor` and `endColor` along the line
  /// from `start` to `end`, written into the layer (or selection if
  /// non-nil) by nearest-color matching against `palette`. The encoder
  /// is index-based, so we project each cell's parametric `t` onto the
  /// nearest palette entry of the interpolated RGB color.
  public static func gradient(
    on buffer: PixelBuffer,
    from start: PixelPoint,
    to end: PixelPoint,
    startColor: EditorColor,
    endColor: EditorColor,
    palette: ColorPalette,
    selection: Selection? = nil
  ) -> PixelBuffer {
    var copy = buffer
    let dx = Double(end.x - start.x)
    let dy = Double(end.y - start.y)
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return copy }

    let bounds =
      selection?.rect
      ?? PixelRect(
        x: 0, y: 0, width: buffer.size.width, height: buffer.size.height
      )

    for y in bounds.minY..<bounds.maxY {
      for x in bounds.minX..<bounds.maxX {
        let px = Double(x - start.x)
        let py = Double(y - start.y)
        let raw = (px * dx + py * dy) / lengthSquared
        let t = max(0.0, min(1.0, raw))
        let blended = EditorColor(
          red: lerp(startColor.red, endColor.red, t),
          green: lerp(startColor.green, endColor.green, t),
          blue: lerp(startColor.blue, endColor.blue, t),
          alpha: lerp(startColor.alpha, endColor.alpha, t)
        )
        let idx = palette.nearestIndex(to: blended)
        copy.setUnchecked(PixelPoint(x: x, y: y), to: idx)
      }
    }
    return copy
  }

  /// Bresenham line — used by pen/eraser strokes when consecutive
  /// pointer samples would otherwise leave gaps. Pass `nil` to clear.
  public static func line(
    on buffer: PixelBuffer,
    from a: PixelPoint,
    to b: PixelPoint,
    color: PaletteIndex?
  ) -> PixelBuffer {
    var copy = buffer
    var x0 = a.x
    var y0 = a.y
    let x1 = b.x
    let y1 = b.y
    let dx = abs(x1 - x0)
    let sx = x0 < x1 ? 1 : -1
    let dy = -abs(y1 - y0)
    let sy = y0 < y1 ? 1 : -1
    var error = dx + dy
    while true {
      copy[PixelPoint(x: x0, y: y0)] = color
      if x0 == x1 && y0 == y1 { break }
      let e2 = 2 * error
      if e2 >= dy {
        if x0 == x1 { break }
        error += dy
        x0 += sx
      }
      if e2 <= dx {
        if y0 == y1 { break }
        error += dx
        y0 += sy
      }
    }
    return copy
  }

  /// Copies the rectangular region of `buffer` selected by `rect` into
  /// a new buffer the size of the rect. Returns `nil` if the rect is
  /// fully outside the buffer.
  public static func copy(from buffer: PixelBuffer, rect: PixelRect) -> PixelBuffer? {
    buffer.cropped(to: rect)
  }

  /// Pastes `clipboard` onto `buffer` with the clipboard's top-left at
  /// `origin`. Transparent (nil) clipboard pixels do not overwrite.
  public static func paste(
    onto buffer: PixelBuffer,
    clipboard: PixelBuffer,
    at origin: PixelPoint
  ) -> PixelBuffer {
    var copy = buffer
    copy.stamp(clipboard, at: origin, respectingTransparency: true)
    return copy
  }

  // MARK: - Helpers

  private static func lerp(_ a: UInt8, _ b: UInt8, _ t: Double) -> UInt8 {
    let v = Double(a) + (Double(b) - Double(a)) * t
    return UInt8(max(0.0, min(255.0, v.rounded())))
  }
}
