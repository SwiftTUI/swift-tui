@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  // MARK: - CellSize computation

  internal func measuredSize(
    for resolved: ResolvedNode,
    childMeasurements: [MeasuredNode],
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> CellSize {
    if let boundary = resolved.layoutRealizedContent {
      return boundary.sizingPolicy.measuredSize(for: proposal)
    }

    switch resolved.layoutBehavior {
    case .intrinsic:
      switch resolved.drawPayload {
      case .text(let content):
        return measuredTextSize(
          for: content,
          metadata: resolved.layoutMetadata,
          proposal: proposal
        )
      case .textFigure(let payload):
        return measuredTextFigureSize(
          for: payload,
          proposal: proposal
        )
      case .richText(let payload):
        return measuredTextSize(
          for: payload.visibleText,
          metadata: resolved.layoutMetadata,
          proposal: proposal
        )
      case .image(let payload):
        return measuredImageSize(
          for: payload,
          proposal: proposal
        )
      case .list(let payload):
        return measuredHostedListSize(
          for: payload,
          childMeasurements: childMeasurements,
          proposal: proposal
        )
      case .table(let payload):
        return measuredHostedTableSize(
          for: payload,
          childMeasurements: childMeasurements,
          proposal: proposal
        )
      case .shape:
        return measuredShapeSize(for: proposal)
      case .canvas, .foreignSurface:
        // Canvas and foreign surfaces fill any proposed size, the same
        // as raw shape primitives: drawing is resolved to the final cell
        // frame at paint time, so there's no intrinsic size.
        return measuredShapeSize(for: proposal)
      case .rule:
        return measuredRuleSize(
          for: proposal,
          stackAxis: resolved.drawMetadata.ruleStackAxis
        )
      case .none:
        break
      }
      if let intrinsicSize = resolved.intrinsicSize {
        return intrinsicSize
      }
      return overlaySize(from: childMeasurements)
    case .overlay(let alignment):
      let alignmentMetrics = overlayAlignmentMetrics(
        for: resolved.children,
        childMeasurements: childMeasurements,
        alignment: alignment
      )
      return CellSize(
        width: alignmentMetrics.leading + alignmentMetrics.trailing,
        height: alignmentMetrics.top + alignmentMetrics.bottom
      )
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
        childMeasurements: childMeasurements,
        axis: .vertical,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center
      )
      let contentHeight = childMeasurements.reduce(0) { $0 + $1.measuredSize.height }
      let totalSpacing = stackSpacings.reduce(0, +)
      return CellSize(
        width: crossMetrics.leading + crossMetrics.trailing,
        height: contentHeight + totalSpacing
      )
    case .lazyStack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
        childMeasurements: childMeasurements,
        axis: .vertical,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center
      )
      let contentHeight = childMeasurements.reduce(0) { $0 + $1.measuredSize.height }
      let totalSpacing = stackSpacings.reduce(0, +)
      return CellSize(
        width: crossMetrics.leading + crossMetrics.trailing,
        height: contentHeight + totalSpacing
      )
    case .stack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
        childMeasurements: childMeasurements,
        axis: .horizontal,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment
      )
      let totalWidth = childMeasurements.reduce(0) { $0 + $1.measuredSize.width }
      let totalSpacing = stackSpacings.reduce(0, +)
      return CellSize(
        width: totalWidth + totalSpacing,
        height: crossMetrics.leading + crossMetrics.trailing
      )
    case .lazyStack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      let stackChildren = stackChildren(for: resolved)
      let stackSpacings = resolvedStackSpacings(
        for: stackChildren,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: stackChildren,
        childMeasurements: childMeasurements,
        axis: .horizontal,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment
      )
      let totalWidth = childMeasurements.reduce(0) { $0 + $1.measuredSize.width }
      let totalSpacing = stackSpacings.reduce(0, +)
      return CellSize(
        width: totalWidth + totalSpacing,
        height: crossMetrics.leading + crossMetrics.trailing
      )
    case .padding(let insets):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return CellSize(
        width: contentSize.width + insets.horizontal,
        height: contentSize.height + insets.vertical
      )
    case .safeAreaIgnoring(let insets):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return CellSize(
        width: insets.horizontal == 0
          ? contentSize.width
          : measuredDimension(proposal.width, fallback: contentSize.width),
        height: insets.vertical == 0
          ? contentSize.height
          : measuredDimension(proposal.height, fallback: contentSize.height)
      )
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      let baseSize = childMeasurements.first?.measuredSize ?? .zero
      let insetSize = childMeasurements.dropFirst().first?.measuredSize ?? .zero
      let consumed = safeAreaInsetConsumedAmount(
        edge: edge,
        contentSize: insetSize,
        spacing: spacing,
        safeArea: safeArea
      )
      switch edge {
      case .top, .bottom:
        return CellSize(
          width: max(baseSize.width, insetSize.width),
          height: baseSize.height + consumed
        )
      case .leading, .trailing:
        return CellSize(
          width: baseSize.width + consumed,
          height: max(baseSize.height, insetSize.height)
        )
      }
    case .border(let set, let placement, _, _, _, _, let sides):
      let insets = borderLayoutInsets(
        set: set, placement: placement, sides: sides)
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return CellSize(
        width: contentSize.width + insets.horizontal,
        height: contentSize.height + insets.vertical
      )
    case .frame(let width, let height, _):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return CellSize(
        width: width ?? contentSize.width,
        height: height ?? contentSize.height
      )
    case .offset:
      return childMeasurements.first?.measuredSize ?? .zero
    case .position:
      // `.position` fills the proposed space so the parent reserves
      // room for the absolute placement area.  Unspecified
      // dimensions fall back to the child's measured size.
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      let width: Int =
        switch proposal.width {
        case .finite(let w): w
        case .infinity: max(contentSize.width, 0)
        case .unspecified: contentSize.width
        }
      let height: Int =
        switch proposal.height {
        case .finite(let h): h
        case .infinity: max(contentSize.height, 0)
        case .unspecified: contentSize.height
        }
      return CellSize(width: width, height: height)
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let contentSize = childMeasurements.first?.measuredSize ?? .zero
      return CellSize(
        width: flexibleFrameMeasuredDimension(
          proposal: proposal.width,
          child: contentSize.width,
          min: minW,
          ideal: idealW,
          max: maxW
        ),
        height: flexibleFrameMeasuredDimension(
          proposal: proposal.height,
          child: contentSize.height,
          min: minH,
          ideal: idealH,
          max: maxH
        )
      )
    case .decoration(let primaryIndex, _):
      guard childMeasurements.indices.contains(primaryIndex) else {
        return overlaySize(from: childMeasurements)
      }
      return childMeasurements[primaryIndex].measuredSize
    case .viewThatFits:
      return childMeasurements.first?.measuredSize ?? .zero
    case .custom(let token):
      guard let handle = token as? CustomLayoutHandle else {
        preconditionFailure("LayoutBehavior.custom must carry a CustomLayoutHandle")
      }
      return handle.measureContainer(
        engine: self,
        node: resolved,
        proposal: proposal,
        passContext: passContext
      )
    }
  }

  internal func finiteValue(_ dim: ProposedDimension?) -> Int? {
    guard case .finite(let v) = dim else { return nil }
    return v
  }

  internal func hasFlexibleConstraint(
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Bool {
    min != nil || ideal != nil || max != nil
  }

  internal func hasFiniteFlexibleConstraint(
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Bool {
    finiteValue(min) != nil || finiteValue(ideal) != nil || finiteValue(max) != nil
  }

  internal func flexibleFrameChildProposalDimension(
    proposal: ProposedDimension,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> ProposedDimension {
    guard hasFlexibleConstraint(min: min, ideal: ideal, max: max) else {
      return proposal
    }

    guard hasFiniteFlexibleConstraint(min: min, ideal: ideal, max: max) else {
      return proposal
    }

    return .finite(
      resolveFlexibleDimension(
        proposal: proposal,
        min: min,
        ideal: ideal,
        max: max
      )
    )
  }

  internal func flexibleFrameMeasuredDimension(
    proposal: ProposedDimension,
    child: Int,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Int {
    guard hasFlexibleConstraint(min: min, ideal: ideal, max: max) else {
      return child
    }

    if hasFiniteFlexibleConstraint(min: min, ideal: ideal, max: max) {
      switch proposal {
      case .unspecified:
        let minVal = finiteValue(min)
        let idealVal = finiteValue(ideal)
        let maxVal = finiteValue(max)
        var result = idealVal ?? child
        if let lo = minVal { result = Swift.max(lo, result) }
        if let hi = maxVal { result = Swift.min(hi, result) }
        return result
      case .finite, .infinity:
        return resolveFlexibleDimension(
          proposal: proposal,
          min: min,
          ideal: ideal,
          max: max
        )
      }
    }

    switch proposal {
    case .finite(let value):
      return value
    case .unspecified, .infinity:
      return child
    }
  }

  internal func resolveFlexibleDimension(
    proposal: ProposedDimension,
    min: ProposedDimension?,
    ideal: ProposedDimension?,
    max: ProposedDimension?
  ) -> Int {
    let minVal = finiteValue(min)
    let idealVal = finiteValue(ideal)
    let maxVal = finiteValue(max)

    let raw: Int
    switch proposal {
    case .unspecified:
      raw = idealVal ?? minVal ?? 0
    case .finite(let n):
      raw = n
    case .infinity:
      raw = maxVal ?? idealVal ?? minVal ?? 0
    }

    var result = raw
    if let lo = minVal { result = Swift.max(lo, result) }
    if let hi = maxVal { result = Swift.min(hi, result) }
    return result
  }

  internal func overlaySize(from childMeasurements: [MeasuredNode]) -> CellSize {
    CellSize(
      width: childMeasurements.map { $0.measuredSize.width }.max() ?? 0,
      height: childMeasurements.map { $0.measuredSize.height }.max() ?? 0
    )
  }

}
