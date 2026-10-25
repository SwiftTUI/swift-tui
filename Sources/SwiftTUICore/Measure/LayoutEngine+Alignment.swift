@_spi(Testing) import SwiftTUIPrimitives

/// Where a stack's or ZStack's children align on one axis.
///
/// `leading` is the greatest child guide value and `trailing` the greatest
/// remainder of a child past its guide, so the container spans
/// `leading + trailing` cells.
package struct AlignmentLine: Equatable, Sendable {
  package var leading: Int
  package var trailing: Int
  /// Whether the line is the built-in centre guide and no child declares an
  /// explicit value for it. Children then centre by extent, exactly as a
  /// frame centres its content, instead of meeting at their floored guides.
  package var centresByExtent: Bool

  package init(leading: Int, trailing: Int, centresByExtent: Bool) {
    self.leading = leading
    self.trailing = trailing
    self.centresByExtent = centresByExtent
  }

  package var extent: Int { leading + trailing }

  /// The offset of a child from the container's leading or top edge.
  package func offset(guideValue: Int, length: Int) -> Int {
    centresByExtent
      ? LayoutEngine.centredOffset(length: length, in: extent)
      : leading - guideValue
  }
}

extension LayoutEngine {
  /// The one centring rule (STUI-591, STUI-1212). Frames, decorations,
  /// safe-area insets, stacks and ZStacks place a child that is centred by
  /// default — neither it nor the container declares an explicit centre
  /// guide — at `(extent - length) / 2`. Content larger than its container
  /// overflows both edges, as in SwiftUI, so the offset can go negative.
  /// Integer division truncates toward zero, so an odd cell falls on the
  /// container's trailing (or bottom) side whether it is a gap or an
  /// overflow. Explicit guides keep guide arithmetic.
  package static func centredOffset(length: Int, in extent: Int) -> Int {
    (extent - length) / 2
  }

  /// Whether children aligned on `guide` centre by extent: the guide is the
  /// built-in centre and no child declares an explicit value for it.
  package func centresByExtent(
    _ dimensions: [ViewDimensions],
    guide: HorizontalAlignment
  ) -> Bool {
    guide == .center && dimensions.allSatisfy { $0.explicitValue(for: guide) == nil }
  }

  /// Whether children aligned on `guide` centre by extent: the guide is the
  /// built-in centre and no child declares an explicit value for it.
  package func centresByExtent(
    _ dimensions: [ViewDimensions],
    guide: VerticalAlignment
  ) -> Bool {
    guide == .center && dimensions.allSatisfy { $0.explicitValue(for: guide) == nil }
  }

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
    // Content larger than its container overflows both edges, as in SwiftUI,
    // so centred and trailing offsets go negative. Default centring follows
    // `centredOffset`, the rule stacks and ZStacks share.
    let x =
      if alignment.horizontal == .center,
        referenceDimensions.explicitValue(for: HorizontalAlignment.center) == nil,
        childDimensions.explicitValue(for: HorizontalAlignment.center) == nil
      {
        bounds.origin.x
          + Self.centredOffset(length: childDimensions.width, in: referenceDimensions.width)
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
        bounds.origin.y
          + Self.centredOffset(length: childDimensions.height, in: referenceDimensions.height)
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
    var guideNode = child
    var guideMeasurement = childMeasurement
    while true {
      // Modifier guides can belong to any level of the propagation chain,
      // including an intermediate wrapper above an unguided leaf.
      if guideNode.layoutMetadata.hasExplicitHorizontalAlignmentGuide(alignment.horizontal)
        || guideNode.layoutMetadata.hasExplicitVerticalAlignmentGuide(alignment.vertical)
      {
        return nil
      }
      guard let next = alignmentPropagationChild(for: guideNode, measured: guideMeasurement) else {
        break
      }
      guideNode = next.0
      guideMeasurement = next.1
    }
    let customHandle = customLayoutHandleAnsweringAlignment(for: guideNode)
    let hasExplicitHorizontalGuide =
      customHandle?.explicitAlignment(
        engine: self,
        node: guideNode,
        measured: guideMeasurement,
        horizontalGuide: alignment.horizontal,
        passContext: passContext
      ) != nil
    let hasExplicitVerticalGuide =
      customHandle?.explicitAlignment(
        engine: self,
        node: guideNode,
        measured: guideMeasurement,
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
      return origin + Self.centredOffset(length: childSize, in: availableSize)
    case .trailing:
      return origin + availableSize - childSize
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
      return origin + Self.centredOffset(length: childSize, in: availableSize)
    case .bottom:
      return origin + availableSize - childSize
    default:
      return nil
    }
  }

  package func overlayAlignmentMetrics(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    alignment: Alignment,
    passContext: LayoutPassContext? = nil
  ) -> (horizontal: AlignmentLine, vertical: AlignmentLine) {
    let hasContent = children.contains { !isSpacer($0) }
    let dimensions = zip(children, childMeasurements).compactMap {
      child, measurement -> ViewDimensions? in
      if hasContent && isSpacer(child) { return nil }
      return viewDimensions(for: child, measured: measurement, passContext: passContext)
    }

    let horizontal = AlignmentLine(
      leading: dimensions.map { $0[alignment.horizontal] }.max() ?? 0,
      trailing: dimensions.map { $0.width - $0[alignment.horizontal] }.max() ?? 0,
      centresByExtent: centresByExtent(dimensions, guide: alignment.horizontal))
    let vertical = AlignmentLine(
      leading: dimensions.map { $0[alignment.vertical] }.max() ?? 0,
      trailing: dimensions.map { $0.height - $0[alignment.vertical] }.max() ?? 0,
      centresByExtent: centresByExtent(dimensions, guide: alignment.vertical))
    return (horizontal, vertical)
  }

  /// The child whose guides a wrapper propagates. Both alignment paths must
  /// follow this same chain, including a decoration's selected primary child.
  private func alignmentPropagationChild(
    for node: ResolvedNode,
    measured: MeasuredNode
  ) -> (ResolvedNode, MeasuredNode)? {
    let index: Int
    switch node.layoutBehavior {
    case .padding, .safeAreaIgnoring, .safeAreaInset, .border, .frame,
      .flexibleFrame, .offset:
      index = 0
    case .decoration(let primaryIndex, _):
      index = primaryIndex
    default:
      return nil
    }
    guard node.children.indices.contains(index),
      measured.childMeasurements.indices.contains(index)
    else { return nil }
    return (node.children[index], measured.childMeasurements[index])
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
      let next = alignmentPropagationChild(for: currentResolved, measured: currentMeasured)
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
