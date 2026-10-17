@_spi(Testing) public import SwiftTUICore

/// A shape wrapper that insets its base geometry before rendering.
public struct InsetShape<Base: InsettableShape>: InsettableShape, ResolvableView {
  public var base: Base
  public var amount: Int

  public init(
    base: Base,
    amount: Int
  ) {
    self.base = base
    self.amount = amount
  }

  public var geometry: ShapeGeometry {
    base.geometry
  }

  public var kindName: String {
    base.kindName
  }

  public var insetAmount: Int {
    let (total, overflow) = base.insetAmount.addingReportingOverflow(amount)
    return overflow ? (amount > 0 ? Int.max : Int.min) : total
  }

  public func path(in rect: Rect) -> Path {
    let inset = Double(amount)
    return base.path(
      in: Rect(
        origin: Point(x: rect.origin.x + inset, y: rect.origin.y + inset),
        size: Size(
          width: max(0, rect.size.width - 2 * inset),
          height: max(0, rect.size.height - 2 * inset))))
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            insetAmount: insetAmount,
            operation: .fill(style: nil, mode: .full)
          )
        ),
        in: context
      )
    ]
  }
}

extension InsettableShape {
  public func inset(by amount: Int) -> some InsettableShape {
    InsetShape(
      base: self,
      amount: amount
    )
  }
}
