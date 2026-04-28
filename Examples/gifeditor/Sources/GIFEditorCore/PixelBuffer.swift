import Foundation

/// A row-major indexed-color buffer where `nil` represents transparent.
///
/// Pixel storage is `[PaletteIndex?]` rather than `[PaletteIndex]` so the
/// editor can preserve transparency on a per-pixel basis through layer
/// compositing — a layer's `nil` pixel reveals whatever painted below it
/// on the same frame, which is the natural mental model for raster
/// editors and matches the GIF graphics control extension semantics.
public struct PixelBuffer: Hashable, Sendable, Codable {
  public let size: PixelSize
  public var pixels: [PaletteIndex?]

  public init(size: PixelSize, fill: PaletteIndex? = nil) {
    self.size = size
    self.pixels = [PaletteIndex?](repeating: fill, count: size.area)
  }

  public init(size: PixelSize, pixels: [PaletteIndex?]) {
    precondition(pixels.count == size.area, "pixel array must match the buffer size")
    self.size = size
    self.pixels = pixels
  }

  public subscript(point: PixelPoint) -> PaletteIndex? {
    get {
      guard size.contains(point) else { return nil }
      return pixels[size.indexOf(point)]
    }
    set {
      guard size.contains(point) else { return }
      pixels[size.indexOf(point)] = newValue
    }
  }

  /// Sets a single pixel without bounds-checking. Caller must ensure the
  /// point is in range — useful inside tight scan/fill loops.
  public mutating func setUnchecked(_ point: PixelPoint, to value: PaletteIndex?) {
    pixels[size.indexOf(point)] = value
  }

  public func get(_ point: PixelPoint) -> PaletteIndex? {
    guard size.contains(point) else { return nil }
    return pixels[size.indexOf(point)]
  }

  public mutating func clear() {
    for i in pixels.indices {
      pixels[i] = nil
    }
  }

  /// Resize this buffer, copying the overlapping rectangle and filling
  /// new area with transparent pixels. Out-of-bounds content is dropped.
  public func resized(to newSize: PixelSize) -> PixelBuffer {
    var result = PixelBuffer(size: newSize)
    let copyW = min(size.width, newSize.width)
    let copyH = min(size.height, newSize.height)
    for y in 0..<copyH {
      for x in 0..<copyW {
        let src = size.indexOf(PixelPoint(x: x, y: y))
        let dst = newSize.indexOf(PixelPoint(x: x, y: y))
        result.pixels[dst] = pixels[src]
      }
    }
    return result
  }

  /// Crops to the given rect (clamped to bounds). Returns `nil` when the
  /// rect is fully outside the buffer.
  public func cropped(to rect: PixelRect) -> PixelBuffer? {
    let bounds = PixelRect(x: 0, y: 0, width: size.width, height: size.height)
    guard let clamped = rect.intersected(with: bounds) else { return nil }
    var out = PixelBuffer(size: clamped.size)
    for dy in 0..<clamped.size.height {
      for dx in 0..<clamped.size.width {
        let src = size.indexOf(
          PixelPoint(x: clamped.minX + dx, y: clamped.minY + dy)
        )
        let dst = clamped.size.indexOf(PixelPoint(x: dx, y: dy))
        out.pixels[dst] = pixels[src]
      }
    }
    return out
  }

  /// Stamps `other` into this buffer with its top-left at `origin`.
  /// `respectingTransparency` skips `nil` pixels in `other` — the natural
  /// "alpha" paste semantic. When `false`, `nil` pixels punch through.
  public mutating func stamp(
    _ other: PixelBuffer,
    at origin: PixelPoint,
    respectingTransparency: Bool = true
  ) {
    for sy in 0..<other.size.height {
      let dy = origin.y + sy
      if dy < 0 || dy >= size.height { continue }
      for sx in 0..<other.size.width {
        let dx = origin.x + sx
        if dx < 0 || dx >= size.width { continue }
        let src = other.pixels[other.size.indexOf(PixelPoint(x: sx, y: sy))]
        if respectingTransparency, src == nil { continue }
        pixels[size.indexOf(PixelPoint(x: dx, y: dy))] = src
      }
    }
  }
}
