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
    base.insetAmount + max(0, amount)
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
      amount: max(0, amount)
    )
  }
}
