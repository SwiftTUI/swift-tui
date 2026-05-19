import CoreGraphics
import Foundation
import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// Terminal cell metrics for the native (AppKit / UIKit) host.
//
// `NativeTerminalMetrics` derives the pixel geometry of a terminal cell from
// the host's terminal font: the cell size, the text baseline offset, and the
// four font variants (regular / bold / italic / bold-italic). It also converts
// between view-local points and the framework's `CellSize` /
// `PointerLocation` / `CellPixelMetrics` vocabulary.
//
// Split out of `NativeTerminalSurfaceView.swift`. `font(for:)` is widened to
// file-internal because `NativeRasterSurfaceRenderer` (in its own file) selects
// a font through it; the four stored font variants stay `fileprivate` — only
// this type reads them. The platform font adapters live in
// `NativeTerminalPlatformAdapters.swift`.

struct NativeTerminalMetrics {
  fileprivate let font: NativePlatformFont
  fileprivate let boldFont: NativePlatformFont
  fileprivate let italicFont: NativePlatformFont
  fileprivate let boldItalicFont: NativePlatformFont
  let cellSize: CGSize
  let textOffset: CGPoint

  init(style: SwiftUIHostTerminalStyle) {
    let baseFont = NativePlatformFont.terminalFont(style: style, emphasis: [])
    font = baseFont
    boldFont = NativePlatformFont.terminalFont(style: style, emphasis: [.bold])
    italicFont = NativePlatformFont.terminalFont(style: style, emphasis: [.italic])
    boldItalicFont = NativePlatformFont.terminalFont(style: style, emphasis: [.bold, .italic])

    let characterSize = NativePlatformFont.measureTerminalCharacter(baseFont)
    // Natural line height: leaves room for descenders. Box-drawing glyphs
    // are rendered procedurally and tile regardless of the cell's height,
    // so we don't have to fight font metrics here.
    let lineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading)
    let cellWidth = max(1, ceil(characterSize.width))
    let cellHeight = max(1, ceil(max(characterSize.height, lineHeight)))
    cellSize = CGSize(width: cellWidth, height: cellHeight)
    textOffset = CGPoint(
      x: 0,
      y: max(0, (cellHeight - characterSize.height) / 2)
    )
  }

  func gridSize(
    for boundsSize: CGSize
  ) -> CellSize {
    CellSize(
      width: max(1, Int(boundsSize.width / cellSize.width)),
      height: max(1, Int(boundsSize.height / cellSize.height))
    )
  }

  func cellPixelSize(
    scale: CGFloat
  ) -> PixelSize {
    PixelSize(
      width: max(1, Int((cellSize.width * scale).rounded())),
      height: max(1, Int((cellSize.height * scale).rounded()))
    )
  }

  func cellPixelMetrics(
    scale: CGFloat
  ) -> CellPixelMetrics {
    let pixelSize = cellPixelSize(scale: scale)
    return CellPixelMetrics(
      width: pixelSize.width,
      height: pixelSize.height,
      source: .reported
    )
  }

  func pointerLocation(
    for local: CGPoint,
    in _: CGRect,
    scale: CGFloat
  ) -> PointerLocation {
    PointerLocation.subCell(
      location: Point(
        x: Double(local.x / cellSize.width),
        y: Double(local.y / cellSize.height)
      ),
      source: .nativePixels,
      metrics: cellPixelMetrics(scale: scale),
      // Native hosts store backing-pixel coordinates for diagnostics.
      rawPixel: PixelPoint(
        x: Double(local.x * scale),
        y: Double(local.y * scale)
      )
    )
  }

  func font(
    for emphasis: SwiftTUIRuntime.TextStyle.TextEmphasis
  ) -> NativePlatformFont {
    switch (emphasis.contains(.bold), emphasis.contains(.italic)) {
    case (true, true):
      boldItalicFont
    case (true, false):
      boldFont
    case (false, true):
      italicFont
    case (false, false):
      font
    }
  }
}
