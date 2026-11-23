public import SwiftTUIViews

/// Echoes the last column of the first source into the second column on later samples.
public struct FirstSampleEcho: CellPreparedLayerKernel {
  public init() {}

  public func makeState() -> CellLayer? { nil }

  public func prepare(
    _ state: inout CellLayer?, source: CellLayer, context: CellPreparationContext
  ) -> CellLayerShader {
    let first = state ?? source
    state = first
    return CellLayerShader { point, current, _ in
      if point.x == first.bounds.origin.x + 1, first.bounds.size.width > 0 {
        return first.sample(at: CellPoint(x: first.bounds.maxX - 1, y: point.y))
      }
      return current.sample(at: point)
    }
  }
}

private struct BorderStar: CellLayerKernel {
  func shade(at point: CellPoint, in stroke: CellLayer, context: CellEffectContext) -> CellSample {
    guard case .glyph(var glyph) = stroke.sample(at: point) else { return .empty }
    glyph.character = "*"
    glyph.paint.foreground = .color(Color(hexRGB: 0xE06080))
    return .glyph(glyph)
  }
}

extension View {
  /// Flies the newly laid-out cells from the last position in their parent.
  public func flyBetweenColumns(isEnabled: Bool = true) -> some View {
    placementEffect(maxSampleOffset: .layerBounds, isEnabled: isEnabled) { placement in
      let distance =
        Double(placement.previousFrame.origin.x) - Double(placement.currentFrame.origin.x)
      let shift = Int(exactly: (distance * (1 - placement.progress)).rounded()) ?? 0
      return CellLayerShader { point, source, _ in
        let (x, overflow) = point.x.subtractingReportingOverflow(shift)
        return overflow ? .empty : source.sample(at: CellPoint(x: x, y: point.y))
      }.drawing(in: .viewport)
    }
  }

  /// Replaces glyphs painted by an existing one-cell border.
  public func starredBorder(isEnabled: Bool = true, inline: Bool = false) -> some View {
    let star =
      inline
      ? CellLayerShader { point, stroke, context in
        BorderStar().shade(at: point, in: stroke, context: context)
      }
      : CellLayerShader(BorderStar())
    return border(
      Color(hexRGB: 0x287ABD), style: .init(), placement: .inset, sides: .all,
      effect: star, maxSampleOffset: .zero, isEnabled: isEnabled)
  }
}
