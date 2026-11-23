public import SwiftTUIViews

/// Replaces the first column with its lower glyph and clears the second column.
public struct LowerColumn: CellCompositingKernel {
  public init() {}

  public func composite(
    at destination: CellPoint, source: CellLayer, backdrop: CellLayer,
    context: CellEffectContext
  ) -> CellCompositeResult {
    switch destination.x - context.outputBounds.origin.x {
    case 0: return .replace(backdrop.sample(at: destination))
    case 1: return .replace(.empty)
    default: return .keepDestination
    }
  }
}

/// Swaps the first two one-column glyphs by copying from a stable snapshot.
public struct SwapColumns: CellRegionKernel {
  public init() {}

  public func apply(
    source: CellLayer, to buffer: inout CellEffectBuffer, context: CellEffectContext
  ) {
    let first = buffer.bounds.origin
    let second = CellPoint(x: first.x + 1, y: first.y)
    guard buffer.bounds.contains(second) else { return }
    let original = buffer.snapshot()
    buffer.clear(at: first)
    buffer.clear(at: second)
    let column = CellSize(width: 1, height: 1)
    buffer.blit(original, from: .init(origin: first, size: column), to: second)
    if case .glyph(let glyph) = source.sample(at: second) { buffer.set(glyph, at: first) }
  }
}

extension View {
  public func lowerColumn(inline: Bool) -> some View {
    let shader: CellLayerShader =
      inline
      ? .compositing { point, source, backdrop, context in
        LowerColumn().composite(at: point, source: source, backdrop: backdrop, context: context)
      } : .compositing(LowerColumn())
    return layerEffect(shader, maxSampleOffset: .zero)
  }

  public func swapColumnsBehind(inline: Bool, isEnabled: Bool = true) -> some View {
    let shader: CellLayerShader =
      inline
      ? .region { source, buffer, context in
        SwapColumns().apply(source: source, to: &buffer, context: context)
      } : .region(SwapColumns())
    return backdropEffect(shader, in: .viewport, maxSampleOffset: .zero, isEnabled: isEnabled)
  }
}
