import SwiftTUICore

// Fast blend-composite pixel pipeline.
//
// `ImageBlendCompositor.blendedPixels` composites up to ~384K pixels per frame
// over an animating backdrop. The reference path builds a `Color` per pixel and
// calls `Color.composited(over:mode:)`, which runs two-to-three full colour-space
// `converted(...)` passes (each an XYZ matrix round-trip through the profile
// primaries) plus a gamut map — ~1M conversions per frame on the MainActor
// present path.
//
// For the overwhelmingly common all-sRGB case this collapses to pure transfer
// functions: sRGB and linear-sRGB share primaries, so every inter-conversion is
// matrix-identity and only the sRGB EOTF/OETF matters. This path decodes source
// bytes through a 256-entry LUT, keeps everything in linear `Double` space, and
// re-encodes once. It is therefore *more* numerically correct than the reference
// (it omits the reference's own matrix round-trip float error), and matches it
// exactly on primaries and within ≤1 byte on midtones — see
// `ImageBlendFastPixelsTests`. Any non-sRGB colour disqualifies the fast path and
// the compositor falls back to the exact `Color` route.

/// Linear-light RGBA with straight (non-premultiplied) alpha, matching the
/// working space `Color.composited` uses (`.linearSRGB`).
struct ImageBlendLinearRGBA: Sendable {
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double
}

enum ImageBlendFastPixels {
  /// `sRGB.decode(b / 255)` for every source byte value. The reference derives
  /// the same linear value per channel (via a matrix round-trip that adds
  /// ~1e-15 cross-channel error); the LUT is the exact identity round-trip.
  static let sRGBDecodeLUT: [Double] = {
    let transfer = RGBColorProfile.sRGB.transferFunction
    return (0...255).map { transfer.decode(Double($0) / 255.0) }
  }()

  /// Linear RGBA for an sRGB source pixel via the decode LUT.
  static func linear(
    fromPixel pixel: RGBAImagePixel
  ) -> ImageBlendLinearRGBA {
    ImageBlendLinearRGBA(
      red: sRGBDecodeLUT[pixel.red],
      green: sRGBDecodeLUT[pixel.green],
      blue: sRGBDecodeLUT[pixel.blue],
      alpha: Double(pixel.alpha) / 255.0
    )
  }

  /// Linear RGBA for an sRGB `Color`, or nil if the colour is not sRGB (which
  /// disqualifies the whole fast path).
  static func linear(
    from color: Color
  ) -> ImageBlendLinearRGBA? {
    guard color.profile == .sRGB else {
      return nil
    }
    let transfer = RGBColorProfile.sRGB.transferFunction
    return ImageBlendLinearRGBA(
      red: transfer.decode(color.red),
      green: transfer.decode(color.green),
      blue: transfer.decode(color.blue),
      alpha: color.alpha
    )
  }

  /// Separable blend function — a verbatim copy of `Color._blend` (which is
  /// `internal` to SwiftTUICore and so unavailable across the module boundary).
  static func blend(
    _ source: Double,
    _ backdrop: Double,
    mode: BlendMode
  ) -> Double {
    switch mode {
    case .normal:
      return source
    case .multiply:
      return source * backdrop
    case .screen:
      return source + backdrop - source * backdrop
    case .overlay:
      if backdrop <= 0.5 {
        return 2.0 * source * backdrop
      }
      return 1.0 - 2.0 * (1.0 - source) * (1.0 - backdrop)
    case .darken:
      return min(source, backdrop)
    case .lighten:
      return max(source, backdrop)
    }
  }

  /// Composites `source` over `backdrop` in linear space, mirroring the
  /// premultiplied Porter-Duff + separable-blend math in `Color.composited`.
  static func composited(
    _ source: ImageBlendLinearRGBA,
    over backdrop: ImageBlendLinearRGBA,
    mode: BlendMode
  ) -> ImageBlendLinearRGBA {
    let outAlpha = source.alpha + backdrop.alpha * (1.0 - source.alpha)

    func channel(_ sourceValue: Double, _ backdropValue: Double) -> Double {
      let blended = blend(sourceValue, backdropValue, mode: mode)
      let premultiplied =
        (1.0 - backdrop.alpha) * source.alpha * sourceValue
        + (1.0 - source.alpha) * backdrop.alpha * backdropValue
        + source.alpha * backdrop.alpha * blended
      return outAlpha > 0 ? premultiplied / outAlpha : 0
    }

    return ImageBlendLinearRGBA(
      red: channel(source.red, backdrop.red),
      green: channel(source.green, backdrop.green),
      blue: channel(source.blue, backdrop.blue),
      alpha: outAlpha
    )
  }

  /// Encodes a linear RGBA back to an 8-bit sRGB pixel, matching the reference's
  /// final `converted(to: .sRGB, .clip)` + `round(value * 255)` step.
  static func pixel(
    from linear: ImageBlendLinearRGBA
  ) -> RGBAImagePixel {
    let transfer = RGBColorProfile.sRGB.transferFunction
    func byte(_ value: Double) -> Int {
      Int((max(0.0, min(1.0, value)) * 255.0).rounded())
    }
    return RGBAImagePixel(
      red: byte(transfer.encode(linear.red)),
      green: byte(transfer.encode(linear.green)),
      blue: byte(transfer.encode(linear.blue)),
      alpha: byte(linear.alpha)
    )
  }
}

/// A backdrop cell precomputed into linear space for the fast path: the resolved
/// background colour, the foreground-over-background colour (nil when the cell
/// has no foreground), and the coverage geometry used to pick between them per
/// sub-cell pixel.
struct ImageBlendFastBackdropCell: Sendable {
  var background: ImageBlendLinearRGBA
  var foregroundOverBackground: ImageBlendLinearRGBA?
  var coverage: RasterBackdropCoverage
  var spanWidth: Int
  var spanOffset: Int
}

extension ImageBlendFastPixels {
  /// Precomputes a backdrop into per-cell linear colours, or returns nil if any
  /// cell colour (or the fallback background) is not sRGB — which sends the whole
  /// composite back to the exact `Color` path.
  static func fastBackdropCells(
    from backdrop: RasterImageBackdrop,
    fallbackBackground: Color
  ) -> [ImageBlendFastBackdropCell]? {
    guard let fallbackLinear = linear(from: fallbackBackground) else {
      return nil
    }

    var cells: [ImageBlendFastBackdropCell] = []
    cells.reserveCapacity(backdrop.cells.count)
    for cell in backdrop.cells {
      let backgroundLinear: ImageBlendLinearRGBA
      if let background = cell.backgroundColor {
        guard let linearBackground = linear(from: background) else {
          return nil
        }
        backgroundLinear = linearBackground
      } else {
        backgroundLinear = fallbackLinear
      }

      var foregroundOverBackground: ImageBlendLinearRGBA?
      if let foreground = cell.foregroundColor {
        guard let foregroundLinear = linear(from: foreground) else {
          return nil
        }
        // Matches `foreground.composited(over: background)` (default `.normal`
        // mode). The reference round-trips this through sRGB before re-decoding
        // it as the outer composite's backdrop; keeping it linear differs only
        // by float epsilon.
        foregroundOverBackground = composited(
          foregroundLinear,
          over: backgroundLinear,
          mode: .normal
        )
      }

      cells.append(
        ImageBlendFastBackdropCell(
          background: backgroundLinear,
          foregroundOverBackground: foregroundOverBackground,
          coverage: rasterBackdropCoverage(for: cell.glyph, spanWidth: cell.spanWidth),
          spanWidth: cell.spanWidth,
          spanOffset: cell.spanOffset
        )
      )
    }
    return cells
  }

  /// Linear backdrop colour for a sub-cell pixel — the fast counterpart of
  /// `ImageBlendCompositor.backdropPixelColor`.
  static func backdropLinear(
    cells: [ImageBlendFastBackdropCell],
    backdropSize: CellSize,
    relativeX: Int,
    relativeY: Int,
    pixelX: Int,
    pixelY: Int,
    cellPixelSize: PixelSize,
    fallbackBackground: ImageBlendLinearRGBA
  ) -> ImageBlendLinearRGBA {
    guard backdropSize.width > 0, backdropSize.height > 0 else {
      return fallbackBackground
    }
    let x = max(0, min(backdropSize.width - 1, relativeX))
    let y = max(0, min(backdropSize.height - 1, relativeY))
    let index = y * backdropSize.width + x
    guard index >= 0, index < cells.count else {
      return fallbackBackground
    }
    let cell = cells[index]
    guard
      let foregroundOverBackground = cell.foregroundOverBackground,
      imageBlendCoverageContains(
        cell.coverage,
        pixelX: pixelX,
        pixelY: pixelY,
        spanWidth: cell.spanWidth,
        spanOffset: cell.spanOffset,
        cellPixelSize: cellPixelSize
      )
    else {
      return cell.background
    }
    return foregroundOverBackground
  }
}

/// Whether the sub-cell pixel at (`pixelX`, `pixelY`) is covered by `coverage`.
/// Shared by the fast path and `ImageBlendCompositor.backdropPixelColor` so the
/// two agree on cell coverage by construction.
func imageBlendCoverageContains(
  _ coverage: RasterBackdropCoverage,
  pixelX: Int,
  pixelY: Int,
  spanWidth: Int,
  spanOffset: Int,
  cellPixelSize: PixelSize
) -> Bool {
  let width = max(1, cellPixelSize.width)
  let height = max(1, cellPixelSize.height)
  let x = max(0, min(width - 1, pixelX))
  let y = max(0, min(height - 1, pixelY))

  switch coverage {
  case .none:
    return false
  case .full:
    return true
  case .quadrant(let mask):
    let column = min(1, (x * 2) / width)
    let row = min(1, (y * 2) / height)
    let bit: UInt8 =
      switch (row, column) {
      case (0, 0): 0b0001
      case (0, 1): 0b0010
      case (1, 0): 0b0100
      default: 0b1000
      }
    return (mask & bit) != 0
  case .braille(let mask):
    let column = min(1, (x * 2) / width)
    let row = min(3, (y * 4) / height)
    let bitIndex: UInt8 =
      switch (column, row) {
      case (0, 0): 0
      case (0, 1): 1
      case (0, 2): 2
      case (1, 0): 3
      case (1, 1): 4
      case (1, 2): 5
      case (0, 3): 6
      default: 7
      }
    return (mask & (UInt8(1) << bitIndex)) != 0
  case .textApproximation:
    let textSpanWidth = max(1, spanWidth)
    let clampedOffset = max(0, min(textSpanWidth - 1, spanOffset))
    let expandedWidth = width * textSpanWidth
    let expandedX = (clampedOffset * width) + x
    let horizontalInset = expandedWidth > 2 ? max(1, expandedWidth / 4) : 0
    let verticalInset = height > 2 ? max(1, height / 5) : 0
    return expandedX >= horizontalInset
      && expandedX <= expandedWidth - 1 - horizontalInset
      && y >= verticalInset
      && y <= height - 1 - verticalInset
  }
}
