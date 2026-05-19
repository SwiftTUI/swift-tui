import CoreGraphics
import Foundation
import SwiftTUIRuntime

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// Raster rendering for the native terminal surface.
//
// `NativeRasterSurfaceRenderer` paints a `RasterSurface` into a `CGContext`:
// it fills the background, draws each cell (procedural box-drawing glyphs via
// `BoxDrawingRenderer`, otherwise font text), applies underline/strikethrough
// decorations, and composites image attachments. `dirtyRects` translates a
// `PresentationDamage` into the `CGRect`s that need repainting.
//
// Split out of `NativeTerminalSurfaceView.swift`. The enum is widened from
// `private` to file-internal so the platform view classes can drive it; its
// helpers stay `private` (file-scoped here). The platform color/image
// adapters it uses live in `NativeTerminalPlatformAdapters.swift`.

enum NativeRasterSurfaceRenderer {
  static func draw(
    surface: RasterSurface?,
    style: SwiftUIHostTerminalStyle,
    metrics: NativeTerminalMetrics,
    bounds: CGRect,
    dirtyRect: CGRect,
    context: CGContext
  ) {
    let dirtyBounds = bounds.intersection(dirtyRect)
    guard !dirtyBounds.isNull, !dirtyBounds.isEmpty else {
      return
    }

    let defaultForeground = style.palette.foreground
    let defaultBackground = style.palette.background
    context.setFillColor(
      NativePlatformColor.terminalColor(
        defaultBackground,
        alphaMultiplier: Double(style.backgroundOpacity)
      ).cgColor
    )
    context.fill(dirtyBounds)

    guard let surface else {
      return
    }

    for (y, row) in surface.cells.enumerated() {
      for (x, cell) in row.enumerated() where !cell.isContinuation {
        let rect = cellRect(x: x, y: y, span: cell.spanWidth, metrics: metrics)
        guard rect.intersects(dirtyBounds) else {
          continue
        }
        drawCell(
          cell,
          x: x,
          y: y,
          style: cell.style ?? ResolvedTextStyle(),
          defaultForeground: defaultForeground,
          metrics: metrics,
          context: context
        )
      }
    }

    for attachment in surface.imageAttachments {
      drawImageAttachment(
        attachment,
        metrics: metrics,
        dirtyRect: dirtyBounds,
        context: context
      )
    }
  }

  static func dirtyRects(
    for damage: PresentationDamage,
    surface: RasterSurface,
    metrics: NativeTerminalMetrics,
    bounds: CGRect
  ) -> [CGRect] {
    guard !damage.requiresFullTextRepaint else {
      return [bounds]
    }

    var rects: [CGRect] = []
    for textRow in damage.textRows {
      guard textRow.row >= 0, textRow.row < surface.size.height else {
        continue
      }
      if textRow.columnRanges.isEmpty {
        appendDirtyRect(
          x: 0,
          y: textRow.row,
          width: surface.size.width,
          metrics: metrics,
          bounds: bounds,
          to: &rects
        )
        continue
      }

      for range in textRow.columnRanges {
        let lowerBound = max(0, min(surface.size.width, range.lowerBound))
        let upperBound = max(lowerBound, min(surface.size.width, range.upperBound))
        guard lowerBound < upperBound else {
          continue
        }
        appendDirtyRect(
          x: lowerBound,
          y: textRow.row,
          width: upperBound - lowerBound,
          metrics: metrics,
          bounds: bounds,
          to: &rects
        )
      }
    }
    return rects
  }

  private static func appendDirtyRect(
    x: Int,
    y: Int,
    width: Int,
    metrics: NativeTerminalMetrics,
    bounds: CGRect,
    to rects: inout [CGRect]
  ) {
    let rect = cellRect(
      x: x,
      y: y,
      span: width,
      metrics: metrics
    ).intersection(bounds)
    guard !rect.isNull, !rect.isEmpty else {
      return
    }
    rects.append(rect)
  }

  private static func cellRect(
    x: Int,
    y: Int,
    span: Int,
    metrics: NativeTerminalMetrics
  ) -> CGRect {
    CGRect(
      x: CGFloat(x) * metrics.cellSize.width,
      y: CGFloat(y) * metrics.cellSize.height,
      width: CGFloat(max(1, span)) * metrics.cellSize.width,
      height: metrics.cellSize.height
    )
  }

  private static func drawCell(
    _ cell: RasterCell,
    x: Int,
    y: Int,
    style: ResolvedTextStyle,
    defaultForeground: SwiftTUIRuntime.Color,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    let spanWidth = max(1, cell.spanWidth)
    let rect = cellRect(x: x, y: y, span: spanWidth, metrics: metrics)

    if let background = style.backgroundColor {
      context.setFillColor(
        NativePlatformColor.terminalColor(
          background,
          alphaMultiplier: style.opacity
        ).cgColor
      )
      context.fill(rect)
    }

    guard cell.character != " " else {
      return
    }

    let foreground = style.foregroundColor ?? defaultForeground
    let color = NativePlatformColor.terminalColor(
      foreground,
      alphaMultiplier: style.opacity
    )

    let drewBoxDrawing =
      BoxDrawingRenderer.canRender(cell.character)
      && BoxDrawingRenderer.draw(
        character: cell.character,
        in: rect,
        color: color.cgColor,
        context: context
      )

    if !drewBoxDrawing {
      let font = metrics.font(for: style.emphasis)
      let textPoint = CGPoint(
        x: rect.minX,
        y: rect.minY + metrics.textOffset.y
      )
      let text = String(cell.character) as NSString
      text.draw(
        at: textPoint,
        withAttributes: [
          .font: font,
          .foregroundColor: color,
        ]
      )
    }

    drawLineDecorations(
      style: style,
      fallbackColor: color,
      rect: rect,
      metrics: metrics,
      context: context
    )
  }

  private static func drawLineDecorations(
    style: ResolvedTextStyle,
    fallbackColor: NativePlatformColor,
    rect: CGRect,
    metrics: NativeTerminalMetrics,
    context: CGContext
  ) {
    if let underlineStyle = style.underlineStyle {
      let color =
        underlineStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.minY + metrics.cellSize.height - 2,
        color: color,
        rect: rect,
        context: context
      )
    }

    if let strikethroughStyle = style.strikethroughStyle {
      let color =
        strikethroughStyle.color.map {
          NativePlatformColor.terminalColor($0, alphaMultiplier: style.opacity)
        } ?? fallbackColor
      strokeLine(
        y: rect.midY,
        color: color,
        rect: rect,
        context: context
      )
    }
  }

  private static func strokeLine(
    y: CGFloat,
    color: NativePlatformColor,
    rect: CGRect,
    context: CGContext
  ) {
    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: rect.minX, y: y))
    context.addLine(to: CGPoint(x: rect.maxX, y: y))
    context.strokePath()
    context.restoreGState()
  }

  private static func drawImageAttachment(
    _ attachment: RasterImageAttachment,
    metrics: NativeTerminalMetrics,
    dirtyRect: CGRect,
    context _: CGContext
  ) {
    guard let image = NativePlatformImage.terminalImage(from: attachment.source) else {
      return
    }

    let bounds = attachment.visibleBounds
    guard !bounds.isEmpty else {
      return
    }

    let rect = CGRect(
      x: CGFloat(bounds.origin.x) * metrics.cellSize.width,
      y: CGFloat(bounds.origin.y) * metrics.cellSize.height,
      width: CGFloat(bounds.size.width) * metrics.cellSize.width,
      height: CGFloat(bounds.size.height) * metrics.cellSize.height
    )
    guard rect.intersects(dirtyRect) else {
      return
    }
    image.drawTerminalImage(in: rect)
  }
}
