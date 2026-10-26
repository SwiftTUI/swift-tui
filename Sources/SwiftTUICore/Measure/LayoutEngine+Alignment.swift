@_spi(Testing) import SwiftTUIPrimitives

/// Where a stack's or ZStack's children align on one axis.
///
/// `leading` is the greatest child guide value and `trailing` the greatest
/// remainder of a child past its guide, so the container spans
/// `leading + trailing` cells. A guide's exact position can sit half a cell
/// past its integer value (`ViewDimensions.halfCellPosition(of:)`): the
/// default centre of an odd length, and any guide computed from it. The line
/// is the greatest exact position, so it sits half a cell past `leading` when
/// a child whose value is `leading` is half a cell past it.
package struct AlignmentLine: Equatable, Sendable {
  package var leading: Int
  package var trailing: Int
  /// Whether the line's exact position is half a cell past `leading`.
  package var isHalfCell: Bool

  package init(leading: Int, trailing: Int, isHalfCell: Bool) {
    self.leading = leading
    self.trailing = trailing
    self.isHalfCell = isHalfCell
  }

  /// The line through children with these guide positions and lengths.
  package init(guides: [(value: Int, isHalfCell: Bool, length: Int)]) {
    let leading = guides.map(\.value).max() ?? 0
    self.init(
      leading: leading,
      trailing: guides.map { SaturatingConversion.subtracting($0.length, $0.value) }.max() ?? 0,
      isHalfCell: guides.contains { $0.value == leading && $0.isHalfCell })
  }

  package var extent: Int { SaturatingConversion.adding(leading, trailing) }

  /// The line through the union of the children behind `self` and `other`,
  /// as a windowed product accumulates measured runs.
  package func merged(with other: AlignmentLine) -> AlignmentLine {
    let leading = max(leading, other.leading)
    return AlignmentLine(
      leading: leading,
      trailing: max(trailing, other.trailing),
      isHalfCell: (self.leading == leading && isHalfCell)
        || (other.leading == leading && other.isHalfCell))
  }

  /// The offset from the container's leading or top edge of a child whose
  /// guide has this position: the child's exact guide sits on the exact line,
  /// and a child that would start half a cell in moves toward the leading or
  /// top edge, so the odd cell falls after it (`LayoutEngine.centredOffset`).
  /// The offset is never negative: a half-cell child whose value is `leading`
  /// makes the line half-cell too.
  package func offset(guideValue: Int, isHalfCell childIsHalfCell: Bool) -> Int {
    SaturatingConversion.subtracting(
      SaturatingConversion.subtracting(leading, guideValue), childIsHalfCell && !isHalfCell ? 1 : 0)
  }

  package func offset(of dimensions: ViewDimensions, on guide: HorizontalAlignment) -> Int {
    let position = dimensions.halfCellPosition(of: guide)
    return offset(guideValue: position.value, isHalfCell: position.isHalfCell)
  }

  package func offset(of dimensions: ViewDimensions, on guide: VerticalAlignment) -> Int {
    let position = dimensions.halfCellPosition(of: guide)
    return offset(guideValue: position.value, isHalfCell: position.isHalfCell)
  }
}

extension LayoutEngine {
  /// The one centring rule (STUI-591, STUI-1212, STUI-1242). A child placed
  /// with its exact guide on an exact line that would start half a cell in
  /// moves toward the leading or top edge, so the odd cell falls after it.
  /// Frames, decorations, safe-area insets, stacks and ZStacks place a child
  /// whose guide and container both sit exactly at their centres at
  /// `(extent - length) / 2`. Content larger than its container overflows both
  /// edges, as in SwiftUI, so the offset can go negative; integer division
  /// truncates toward zero, so the odd cell falls on the container's trailing
  /// (or bottom) side whether it is a gap or an overflow.
  package static func centredOffset(length: Int, in extent: Int) -> Int {
    SaturatingConversion.subtracting(extent, length) / 2
  }

  /// The offset of a child in a frame, decoration or inset reference, each
  /// guide given as a position (`ViewDimensions.halfCellPosition(of:)`) and
  /// its participant's length. Two exact centres use `centredOffset`; any
  /// other pair subtracts integer guides, and a half-cell child on an integer
  /// guide moves toward the leading or top edge as on a stack line.
  package static func alignedOffset(
    child: (value: Int, isHalfCell: Bool), length: Int,
    reference: (value: Int, isHalfCell: Bool), referenceLength: Int
  ) -> Int {
    func isExactCentre(_ guide: (value: Int, isHalfCell: Bool), of length: Int) -> Bool {
      let doubled = guide.value.multipliedReportingOverflow(by: 2)
      return !doubled.overflow
        && SaturatingConversion.adding(doubled.partialValue, guide.isHalfCell ? 1 : 0) == length
    }
    if isExactCentre(child, of: length), isExactCentre(reference, of: referenceLength) {
      return centredOffset(length: length, in: referenceLength)
    }
    // Only a gap moves: an overflowing half-cell child keeps the integer
    // difference, the truncation toward zero `centredOffset` applies.
    let startsHalfCellIn =
      child.isHalfCell && !reference.isHalfCell && reference.value > child.value
    return SaturatingConversion.subtracting(
      SaturatingConversion.subtracting(reference.value, child.value), startsHalfCellIn ? 1 : 0)
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
    // so centred and trailing offsets go negative. Centring follows
    // `alignedOffset`, the rule stacks and ZStacks share.
    let x = SaturatingConversion.adding(
      bounds.origin.x,
      Self.alignedOffset(
        child: childDimensions.halfCellPosition(of: alignment.horizontal),
        length: childDimensions.width,
        reference: referenceDimensions.halfCellPosition(of: alignment.horizontal),
        referenceLength: referenceDimensions.width))
    let y = SaturatingConversion.adding(
      bounds.origin.y,
      Self.alignedOffset(
        child: childDimensions.halfCellPosition(of: alignment.vertical),
        length: childDimensions.height,
        reference: referenceDimensions.halfCellPosition(of: alignment.vertical),
        referenceLength: referenceDimensions.height))

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
      return SaturatingConversion.adding(
        origin, Self.centredOffset(length: childSize, in: availableSize))
    case .trailing:
      return SaturatingConversion.adding(
        origin, SaturatingConversion.subtracting(availableSize, childSize))
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
      return SaturatingConversion.adding(
        origin, Self.centredOffset(length: childSize, in: availableSize))
    case .bottom:
      return SaturatingConversion.adding(
        origin, SaturatingConversion.subtracting(availableSize, childSize))
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
      guides: dimensions.map {
        let position = $0.halfCellPosition(of: alignment.horizontal)
        return (position.value, position.isHalfCell, $0.width)
      })
    let vertical = AlignmentLine(
      guides: dimensions.map {
        let position = $0.halfCellPosition(of: alignment.vertical)
        return (position.value, position.isHalfCell, $0.height)
      })
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
            offsetX: SaturatingConversion.negated(insets.leading),
            offsetY: SaturatingConversion.negated(insets.top)
          )
        case .safeAreaInset(let edge, _, let spacing, let safeArea):
          let insetSize =
            levelMeasured.childMeasurements.dropFirst().first?.measuredSize ?? .zero
          let consumed =
            switch edge {
            case .top, .bottom:
              max(
                0,
                SaturatingConversion.subtracting(
                  SaturatingConversion.adding(insetSize.height, spacing), safeArea.value(for: edge)
                ))
            case .leading, .trailing:
              max(
                0,
                SaturatingConversion.subtracting(
                  SaturatingConversion.adding(insetSize.width, spacing), safeArea.value(for: edge)))
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
    // The child's guides are read in the centre-rounding mode the wrapper's
    // guide is read in, so a propagated guide keeps its half cell.
    ViewDimensions(width: size.width, height: size.height)
      .overridingHorizontalGuides(modeAware: { alignment, roundsUp in
        childDimensions.roundingDefaultCentreUp(roundsUp).explicitValue(for: alignment)
          .map { SaturatingConversion.adding($0, offsetX) }
      })
      .overridingVerticalGuides(modeAware: { alignment, roundsUp in
        childDimensions.roundingDefaultCentreUp(roundsUp).explicitValue(for: alignment)
          .map { SaturatingConversion.adding($0, offsetY) }
      })
  }
}
