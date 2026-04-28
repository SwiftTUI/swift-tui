import Foundation

/// A pixel coordinate inside the canvas, with `(0, 0)` at the top-left.
public struct PixelPoint: Hashable, Sendable, Codable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public static let zero = PixelPoint(x: 0, y: 0)
}

/// Width × height of a pixel canvas. Always positive.
public struct PixelSize: Hashable, Sendable, Codable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    precondition(width > 0 && height > 0, "PixelSize must be positive")
    self.width = width
    self.height = height
  }

  public var area: Int { width * height }

  public func contains(_ point: PixelPoint) -> Bool {
    point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
  }

  public func indexOf(_ point: PixelPoint) -> Int {
    point.y * width + point.x
  }

  public func point(at index: Int) -> PixelPoint {
    PixelPoint(x: index % width, y: index / width)
  }
}

/// Inclusive-exclusive rectangular region in pixel space.
public struct PixelRect: Hashable, Sendable, Codable {
  public var origin: PixelPoint
  public var size: PixelSize

  public init(origin: PixelPoint, size: PixelSize) {
    self.origin = origin
    self.size = size
  }

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.init(origin: PixelPoint(x: x, y: y), size: PixelSize(width: width, height: height))
  }

  public var minX: Int { origin.x }
  public var minY: Int { origin.y }
  public var maxX: Int { origin.x + size.width }
  public var maxY: Int { origin.y + size.height }

  public func contains(_ point: PixelPoint) -> Bool {
    point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
  }

  /// Intersection of two rects, normalized into the smaller bounds.
  /// Returns `nil` when they don't overlap.
  public func intersected(with other: PixelRect) -> PixelRect? {
    let left = max(minX, other.minX)
    let top = max(minY, other.minY)
    let right = min(maxX, other.maxX)
    let bottom = min(maxY, other.maxY)
    guard right > left && bottom > top else { return nil }
    return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// The smallest rect that fully contains both points (inclusive).
  public static func bounding(_ a: PixelPoint, _ b: PixelPoint) -> PixelRect {
    let x0 = min(a.x, b.x)
    let y0 = min(a.y, b.y)
    let x1 = max(a.x, b.x)
    let y1 = max(a.y, b.y)
    return PixelRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
  }
}
