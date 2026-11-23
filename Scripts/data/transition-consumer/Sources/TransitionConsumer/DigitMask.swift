public import SwiftTUIViews

/// Replaces each single-column digit with a marker, preserving its ink, paper and link.
public struct DigitMask: CellLayerKernel {
  public let marker: Character

  public init(marker: Character = "#") {
    self.marker = marker
  }

  public func shade(at point: CellPoint, in source: CellLayer, context: CellEffectContext)
    -> CellSample
  {
    let sample = source.sample(at: point)
    guard case .glyph(var glyph) = sample, glyph.width == 1, glyph.character.isNumber
    else { return sample }
    glyph.character = marker
    return .glyph(glyph)
  }
}

extension View {
  /// Applies the named, value-comparable program.
  public func maskingDigits(with marker: Character = "#", isEnabled: Bool = true) -> some View {
    layerEffect(
      CellLayerShader(DigitMask(marker: marker)), maxSampleOffset: .zero,
      isEnabled: isEnabled)
  }

  /// Spells the same effect as a trailing closure with an immutable capture.
  public func maskingDigitsInline(with marker: Character = "#", isEnabled: Bool = true) -> some View
  {
    let mask = DigitMask(marker: marker)
    return layerEffect(maxSampleOffset: .zero, isEnabled: isEnabled) { point, source, context in
      mask.shade(at: point, in: source, context: context)
    }
  }
}
