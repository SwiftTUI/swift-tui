@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  package func alignedOrigin(
    for childDimensions: ViewDimensions,
    in bounds: CellRect,
    alignment: Alignment
  ) -> CellPoint {
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
    in bounds: CellRect,
    alignment: Alignment
  ) -> CellPoint {
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

    return CellPoint(
      x: x,
      y: y
    )
  }

  package func simpleAlignedOrigin(
    for child: ResolvedNode,
    measured childMeasurement: MeasuredNode,
    in bounds: CellRect,
    alignment: Alignment,
    passContext: LayoutPassContext? = nil
  ) -> CellPoint? {
    // A custom-layout child may answer the requested guide itself (plan
    // 2026-08-31-001). The fast path is exact only when neither the child's
    // modifier metadata nor its layout has an answer, so ask the layout
    // (memoized per pass) rather than blanket-routing custom children to
    // the slow path — the two paths differ for oversize children.
    let customHandle = customLayoutHandleAnsweringAlignment(for: child)
    let hasExplicitHorizontalGuide =
      child.layoutMetadata.hasExplicitHorizontalAlignmentGuide(alignment.horizontal)
      || customHandle?.explicitAlignment(
        engine: self,
        node: child,
        measured: childMeasurement,
        horizontalGuide: alignment.horizontal,
        passContext: passContext
      ) != nil
    let hasExplicitVerticalGuide =
      child.layoutMetadata.hasExplicitVerticalAlignmentGuide(alignment.vertical)
      || customHandle?.explicitAlignment(
        engine: self,
        node: child,
        measured: childMeasurement,
        verticalGuide: alignment.vertical,
        passContext: passContext
      ) != nil
    guard
      let x = simpleAlignedCoordinate(
        childSize: childMeasurement.measuredSize.width,
        availableSize: bounds.size.width,
        origin: bounds.origin.x,
        alignment: alignment.horizontal,
        hasExplicitGuide: hasExplicitHorizontalGuide
      ),
      let y = simpleAlignedCoordinate(
        childSize: childMeasurement.measuredSize.height,
        availableSize: bounds.size.height,
        origin: bounds.origin.y,
        alignment: alignment.vertical,
        hasExplicitGuide: hasExplicitVerticalGuide
      )
    else {
      return nil
    }

    return .init(x: x, y: y)
  }

  /// The custom-layout handle behind `node` when its layout can answer
  /// explicit alignment guides, else `nil`.
  private func customLayoutHandleAnsweringAlignment(
    for node: ResolvedNode
  ) -> CustomLayoutHandle? {
    guard case .custom(let token) = node.layoutBehavior,
      let handle = token as? CustomLayoutHandle,
      handle.answersExplicitAlignment
    else {
      return nil
    }
    return handle
  }

  /// A node's own dimensions before any wrapper propagation or modifier
  /// guides: plain width/height, or — for a custom-layout container whose
  /// layout answers explicit alignment (plan 2026-08-31-001) — width/height
  /// with lazy guide providers that ask the layout. The providers run only
  /// when a parent reads that guide, and the handle memoizes each answer on
  /// the pass context.
  private func ownDimensions(
    for node: ResolvedNode,
    measured: MeasuredNode,
    passContext: LayoutPassContext?
  ) -> ViewDimensions {
    let plain = ViewDimensions(
      width: measured.measuredSize.width,
      height: measured.measuredSize.height
    )
    guard let handle = customLayoutHandleAnsweringAlignment(for: node) else {
      return plain
    }
    let engine = self
    return
      plain
      .overridingHorizontalGuides { guide in
        handle.explicitAlignment(
          engine: engine,
          node: node,
          measured: measured,
          horizontalGuide: guide,
          passContext: passContext
        )
      }
      .overridingVerticalGuides { guide in
        handle.explicitAlignment(
          engine: engine,
          node: node,
          measured: measured,
          verticalGuide: guide,
          passContext: passContext
        )
      }
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
    alignment: Alignment,
    passContext: LayoutPassContext? = nil
  ) -> (leading: Int, trailing: Int, top: Int, bottom: Int) {
    let dimensions = zip(children, childMeasurements).map { child, measurement in
      viewDimensions(for: child, measured: measurement, passContext: passContext)
    }

    let leading = dimensions.map { max(0, $0[alignment.horizontal]) }.max() ?? 0
    let trailing = dimensions.map { max(0, $0.width - $0[alignment.horizontal]) }.max() ?? 0
    let top = dimensions.map { max(0, $0[alignment.vertical]) }.max() ?? 0
    let bottom = dimensions.map { max(0, $0.height - $0[alignment.vertical]) }.max() ?? 0

    return (leading, trailing, top, bottom)
  }

  package func viewDimensions(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    passContext: LayoutPassContext? = nil
  ) -> ViewDimensions {
    // Iterative wrapper-chain walk. The previous per-level recursion copied
    // an inline `LayoutBehavior` (~1.6 kB) onto the stack at every hop and
    // overflowed the 512 KiB frame-tail worker on deep wrapper chains — the
    // stack-safety class every other engine walk already converted away
    // from. Phase 1 descends the single propagation child each wrapper
    // forwards to; phase 2 ascends, applying the per-level propagation and
    // guide epilogue that the recursion applied on unwind.
    struct Level {
      var resolved: ResolvedNode
      var measured: MeasuredNode
    }
    var chain: [Level] = []
    var currentResolved = resolved
    var currentMeasured = measured
    while true {
      var next: (ResolvedNode, MeasuredNode)?
      switch currentResolved.layoutBehavior {
      case .padding, .safeAreaIgnoring, .safeAreaInset, .border, .frame,
        .flexibleFrame, .offset:
        if let child = currentResolved.children.first,
          let childMeasurement = currentMeasured.childMeasurements.first
        {
          next = (child, childMeasurement)
        }
      case .decoration(let primaryIndex, _):
        if currentResolved.children.indices.contains(primaryIndex),
          currentMeasured.childMeasurements.indices.contains(primaryIndex)
        {
          next = (
            currentResolved.children[primaryIndex],
            currentMeasured.childMeasurements[primaryIndex]
          )
        }
      default:
        next = nil
      }
      chain.append(Level(resolved: currentResolved, measured: currentMeasured))
      guard let (nextResolved, nextMeasured) = next else {
        break
      }
      currentResolved = nextResolved
      currentMeasured = nextMeasured
    }

    var childDimensions: ViewDimensions?
    for level in chain.reversed() {
      let levelResolved = level.resolved
      let levelMeasured = level.measured
      let baseDimensions: ViewDimensions
      if let child = childDimensions {
        switch levelResolved.layoutBehavior {
        case .padding(let insets):
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: insets.leading,
            offsetY: insets.top
          )
        case .safeAreaIgnoring(let insets, _):
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: -insets.leading,
            offsetY: -insets.top
          )
        case .safeAreaInset(let edge, _, let spacing, let safeArea):
          let insetSize =
            levelMeasured.childMeasurements.dropFirst().first?.measuredSize ?? .zero
          let consumed =
            switch edge {
            case .top, .bottom:
              max(0, insetSize.height + spacing - safeArea.value(for: edge))
            case .leading, .trailing:
              max(0, insetSize.width + spacing - safeArea.value(for: edge))
            }
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: edge == .leading ? consumed : 0,
            offsetY: edge == .top ? consumed : 0
          )
        case .border(let set, let placement, _, _, _, _, let sides):
          let insets = borderLayoutInsets(
            set: set, placement: placement, sides: sides)
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: insets.leading,
            offsetY: insets.top
          )
        case .frame(_, _, let alignment), .flexibleFrame(_, _, _, _, _, _, let alignment):
          let childOrigin = alignedOrigin(
            for: child,
            in: CellRect(origin: .zero, size: levelMeasured.measuredSize),
            alignment: alignment
          )
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: childOrigin.x,
            offsetY: childOrigin.y
          )
        case .offset, .decoration:
          baseDimensions = propagatedViewDimensions(
            size: levelMeasured.measuredSize,
            from: child,
            offsetX: 0,
            offsetY: 0
          )
        default:
          baseDimensions = ViewDimensions(
            width: levelMeasured.measuredSize.width,
            height: levelMeasured.measuredSize.height
          )
        }
      } else {
        // The chain's innermost level: the node whose own dimensions the
        // wrappers above propagate. A custom container answers its guides
        // here (plan 2026-08-31-001).
        baseDimensions = ownDimensions(
          for: levelResolved,
          measured: levelMeasured,
          passContext: passContext
        )
      }

      let textAwareDimensions =
        switch levelResolved.drawPayload {
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
        case .image, .list, .table, .shape, .rule, .canvas, .foreignSurface, .none:
          baseDimensions
        }

      childDimensions = levelResolved.layoutMetadata.applyingGuides(to: textAwareDimensions)
    }
    // The chain always contains at least the entry node.
    return childDimensions
      ?? ViewDimensions(
        width: measured.measuredSize.width,
        height: measured.measuredSize.height
      )
  }

  package func propagatedViewDimensions(
    size: CellSize,
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
