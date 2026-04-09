extension LayoutEngine {
  package func alignedOrigin(
    for childDimensions: ViewDimensions,
    in bounds: Rect,
    alignment: Alignment
  ) -> Point {
    alignedOrigin(
      for: childDimensions,
      referenceDimensions: ViewDimensions(width: bounds.size.width, height: bounds.size.height),
      in: bounds,
      alignment: alignment
    )
  }

  package func alignedOrigin(
    for childDimensions: ViewDimensions,
    referenceDimensions: ViewDimensions,
    in bounds: Rect,
    alignment: Alignment
  ) -> Point {
    let x =
      if alignment.horizontal == .center,
        referenceDimensions.explicitValue(for: HorizontalAlignment.center) == nil,
        childDimensions.explicitValue(for: HorizontalAlignment.center) == nil
      {
        bounds.origin.x + max(0, (referenceDimensions.width - childDimensions.width) / 2)
      } else {
        bounds.origin.x
          + referenceDimensions[alignment.horizontal]
          - childDimensions[alignment.horizontal]
      }

    let y =
      if alignment.vertical == .center,
        referenceDimensions.explicitValue(for: VerticalAlignment.center) == nil,
        childDimensions.explicitValue(for: VerticalAlignment.center) == nil
      {
        bounds.origin.y + max(0, (referenceDimensions.height - childDimensions.height) / 2)
      } else {
        bounds.origin.y
          + referenceDimensions[alignment.vertical]
          - childDimensions[alignment.vertical]
      }

    return Point(
      x: x,
      y: y
    )
  }

  package func simpleAlignedOrigin(
    for child: ResolvedNode,
    measured childMeasurement: MeasuredNode,
    in bounds: Rect,
    alignment: Alignment
  ) -> Point? {
    guard
      let x = simpleAlignedCoordinate(
        childSize: childMeasurement.measuredSize.width,
        availableSize: bounds.size.width,
        origin: bounds.origin.x,
        alignment: alignment.horizontal,
        hasExplicitGuide: child.layoutMetadata.hasExplicitHorizontalAlignmentGuide(
          alignment.horizontal)
      ),
      let y = simpleAlignedCoordinate(
        childSize: childMeasurement.measuredSize.height,
        availableSize: bounds.size.height,
        origin: bounds.origin.y,
        alignment: alignment.vertical,
        hasExplicitGuide: child.layoutMetadata.hasExplicitVerticalAlignmentGuide(alignment.vertical)
      )
    else {
      return nil
    }

    return .init(x: x, y: y)
  }

  package func simpleAlignedCoordinate(
    childSize: Int,
    availableSize: Int,
    origin: Int,
    alignment: HorizontalAlignment,
    hasExplicitGuide: Bool
  ) -> Int? {
    guard !hasExplicitGuide else {
      return nil
    }

    switch alignment {
    case .leading:
      return origin
    case .center:
      return origin + max(0, (availableSize - childSize) / 2)
    case .trailing:
      return origin + max(0, availableSize - childSize)
    default:
      return nil
    }
  }

  package func simpleAlignedCoordinate(
    childSize: Int,
    availableSize: Int,
    origin: Int,
    alignment: VerticalAlignment,
    hasExplicitGuide: Bool
  ) -> Int? {
    guard !hasExplicitGuide else {
      return nil
    }

    switch alignment {
    case .top:
      return origin
    case .center:
      return origin + max(0, (availableSize - childSize) / 2)
    case .bottom:
      return origin + max(0, availableSize - childSize)
    default:
      return nil
    }
  }

  package func overlayAlignmentMetrics(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    alignment: Alignment
  ) -> (leading: Int, trailing: Int, top: Int, bottom: Int) {
    let dimensions = zip(children, childMeasurements).map { child, measurement in
      viewDimensions(for: child, measured: measurement)
    }

    let leading = dimensions.map { max(0, $0[alignment.horizontal]) }.max() ?? 0
    let trailing = dimensions.map { max(0, $0.width - $0[alignment.horizontal]) }.max() ?? 0
    let top = dimensions.map { max(0, $0[alignment.vertical]) }.max() ?? 0
    let bottom = dimensions.map { max(0, $0.height - $0[alignment.vertical]) }.max() ?? 0

    return (leading, trailing, top, bottom)
  }

  package func viewDimensions(
    for resolved: ResolvedNode,
    measured: MeasuredNode
  ) -> ViewDimensions {
    let baseDimensions: ViewDimensions

    switch resolved.layoutBehavior {
    case .padding(let insets):
      if let child = resolved.children.first,
        let childMeasurement = measured.childMeasurements.first
      {
        baseDimensions = propagatedViewDimensions(
          size: measured.measuredSize,
          from: viewDimensions(for: child, measured: childMeasurement),
          offsetX: insets.leading,
          offsetY: insets.top
        )
      } else {
        baseDimensions = ViewDimensions(
          width: measured.measuredSize.width,
          height: measured.measuredSize.height
        )
      }
    case .frame(_, _, let alignment), .flexibleFrame(_, _, _, _, _, _, let alignment):
      if let child = resolved.children.first,
        let childMeasurement = measured.childMeasurements.first
      {
        let childDimensions = viewDimensions(for: child, measured: childMeasurement)
        let childOrigin = alignedOrigin(
          for: childDimensions,
          in: Rect(origin: .zero, size: measured.measuredSize),
          alignment: alignment
        )
        baseDimensions = propagatedViewDimensions(
          size: measured.measuredSize,
          from: childDimensions,
          offsetX: childOrigin.x,
          offsetY: childOrigin.y
        )
      } else {
        baseDimensions = ViewDimensions(
          width: measured.measuredSize.width,
          height: measured.measuredSize.height
        )
      }
    case .offset:
      if let child = resolved.children.first,
        let childMeasurement = measured.childMeasurements.first
      {
        baseDimensions = propagatedViewDimensions(
          size: measured.measuredSize,
          from: viewDimensions(for: child, measured: childMeasurement),
          offsetX: 0,
          offsetY: 0
        )
      } else {
        baseDimensions = ViewDimensions(
          width: measured.measuredSize.width,
          height: measured.measuredSize.height
        )
      }
    case .decoration(let primaryIndex, _):
      if resolved.children.indices.contains(primaryIndex),
        measured.childMeasurements.indices.contains(primaryIndex)
      {
        baseDimensions = propagatedViewDimensions(
          size: measured.measuredSize,
          from: viewDimensions(
            for: resolved.children[primaryIndex],
            measured: measured.childMeasurements[primaryIndex]
          ),
          offsetX: 0,
          offsetY: 0
        )
      } else {
        baseDimensions = ViewDimensions(
          width: measured.measuredSize.width,
          height: measured.measuredSize.height
        )
      }
    default:
      baseDimensions = ViewDimensions(
        width: measured.measuredSize.width,
        height: measured.measuredSize.height
      )
    }

    let textAwareDimensions =
      switch resolved.drawPayload {
      case .text, .textFigure, .richText:
        baseDimensions.overridingVerticalGuides { alignment in
          switch alignment {
          case .firstTextBaseline:
            return baseDimensions.height > 0 ? 1 : 0
          case .lastTextBaseline:
            return baseDimensions.height
          default:
            return nil
          }
        }
      case .image, .list, .table, .shape, .rule, .none:
        baseDimensions
      }

    return resolved.layoutMetadata.applyingGuides(to: textAwareDimensions)
  }

  package func propagatedViewDimensions(
    size: Size,
    from childDimensions: ViewDimensions,
    offsetX: Int,
    offsetY: Int
  ) -> ViewDimensions {
    ViewDimensions(width: size.width, height: size.height)
      .overridingHorizontalGuides { alignment in
        childDimensions.explicitValue(for: alignment).map { $0 + offsetX }
      }
      .overridingVerticalGuides { alignment in
        childDimensions.explicitValue(for: alignment).map { $0 + offsetY }
      }
  }
}
