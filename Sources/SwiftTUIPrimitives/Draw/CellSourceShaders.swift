/// Adjusts the stored paint of a covered glyph. Painted spaces participate.
public protocol CellColorKernel: Equatable, Sendable {
  nonisolated func shade(at position: CellPoint, paint: CellPaint, context: CellEffectContext)
    -> CellPaint
}

/// Maps each destination column to an absolute source-local column, or a hole.
public protocol CellDistortionKernel: Equatable, Sendable {
  nonisolated func sourcePosition(for destination: CellPoint, context: CellEffectContext)
    -> CellPoint?
}

private struct ColorLayer<K: CellColorKernel>: CellLayerKernel {
  let kernel: K

  func shade(at point: CellPoint, in source: CellLayer, context: CellEffectContext) -> CellSample {
    let sample = source.sample(at: point)
    guard case .glyph(var glyph) = sample else { return sample }
    glyph.paint = kernel.shade(at: point, paint: glyph.paint, context: context)
    return .glyph(glyph)
  }
}

/// A color program applied once to each painted lead.
public struct CellColorShader: Equatable, Sendable {
  public typealias Function = @Sendable (CellPoint, CellPaint, CellEffectContext) -> CellPaint
  package let layer: CellLayerShader

  public init<K: CellColorKernel>(_ kernel: K) {
    layer = CellLayerShader(ColorLayer(kernel: kernel))
  }

  public init(_ shade: @escaping Function) {
    layer = CellLayerShader { point, source, context in
      let sample = source.sample(at: point)
      guard case .glyph(var glyph) = sample else { return sample }
      glyph.paint = shade(point, glyph.paint, context)
      return .glyph(glyph)
    }
  }
}

private struct DistortionLayer<K: CellDistortionKernel>: CellLayerKernel {
  let kernel: K

  func shade(at point: CellPoint, in source: CellLayer, context: CellEffectContext) -> CellSample {
    guard let from = kernel.sourcePosition(for: point, context: context) else { return .empty }
    return source.sample(at: from)
  }
}

/// A destination-to-source mapping with a clipped output region.
public struct CellDistortionShader: Equatable, Sendable {
  public typealias Function = @Sendable (CellPoint, CellEffectContext) -> CellPoint?
  package var layer: CellLayerShader

  public init<K: CellDistortionKernel>(_ kernel: K) {
    layer = CellLayerShader(DistortionLayer(kernel: kernel))
  }

  public init(_ map: @escaping Function) {
    layer = CellLayerShader { point, source, context in
      guard let from = map(point, context) else { return .empty }
      return source.sample(at: from)
    }
  }

  /// Changes the region into which the mapping may move glyphs.
  public func drawing(in region: CellDrawingRegion) -> Self {
    var copy = self
    copy.layer = layer.drawing(in: region)
    return copy
  }
}
