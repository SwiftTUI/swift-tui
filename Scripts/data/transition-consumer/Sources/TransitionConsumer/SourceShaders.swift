public import SwiftTUIViews

/// An application can replace ink while leaving a row's paper, coverage and links intact.
public struct PaletteInk: CellColorKernel {
  public var index: UInt8

  public init(index: UInt8) {
    self.index = index
  }

  public func shade(at position: CellPoint, paint: CellPaint, context: CellEffectContext)
    -> CellPaint
  {
    var result = paint
    result.foreground = .indexed(index)
    return result
  }
}

/// Moves the source one column to the right inside its drawing region.
public struct ShiftRight: CellDistortionKernel {
  public init() {}

  public func sourcePosition(for destination: CellPoint, context: CellEffectContext) -> CellPoint? {
    guard destination.x > context.sourceBounds.origin.x else { return nil }
    return CellPoint(x: destination.x - 1, y: destination.y)
  }
}

extension View {
  public func paletteInk(_ index: UInt8, isEnabled: Bool = true) -> some View {
    colorEffect(CellColorShader(PaletteInk(index: index)), isEnabled: isEnabled)
  }

  public func paletteInkInline(_ index: UInt8, isEnabled: Bool = true) -> some View {
    let ink = PaletteInk(index: index)
    return colorEffect(isEnabled: isEnabled) { position, paint, context in
      ink.shade(at: position, paint: paint, context: context)
    }
  }

  public func shiftRight(isEnabled: Bool = true) -> some View {
    distortionEffect(
      CellDistortionShader(ShiftRight()).drawing(in: .source),
      maxSampleOffset: .cells(x: 1, y: 0), isEnabled: isEnabled)
  }

  public func shiftRightInline(isEnabled: Bool = true) -> some View {
    let shift = ShiftRight()
    return distortionEffect(maxSampleOffset: .cells(x: 1, y: 0), isEnabled: isEnabled) {
      destination, context in
      shift.sourcePosition(for: destination, context: context)
    }
  }
}
