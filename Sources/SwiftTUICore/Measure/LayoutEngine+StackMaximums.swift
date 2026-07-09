@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  /// The largest main-axis size a stack child will absorb when offered
  /// more space, or `nil` when the subtree is unbounded (Spacer, raw
  /// shapes, `.infinity` flexible frames).
  ///
  /// This is an *offering* estimate for stack space allocation: it
  /// bounds what the allocator proposes and orders children by
  /// flexibility. Totals stay exact regardless of estimate precision
  /// because every child is re-measured at its offered size and the
  /// actual response feeds back into the remaining budget. Rigid
  /// content (text, images, `.fixedSize` subtrees, min/ideal-only
  /// flexible frames) reports its ideal size so it is never offered
  /// more than it would keep — min/ideal-only frames in particular
  /// would otherwise fill any finite over-proposal.
  ///
  /// The traversal mirrors `derivedMinimumMainSize`.
  package func derivedMaximumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> Int? {
    struct MaximumFrame {
      var node: ResolvedNode
      var idealMeasurement: MeasuredNode
      var visited: Bool
    }

    var work: [MaximumFrame] = [
      .init(node: node, idealMeasurement: idealMeasurement, visited: false)
    ]
    var maximums: [Identity: Int?] = [:]

    while let frame = work.popLast() {
      if !frame.visited {
        if let direct = directMaximumMainSize(
          for: frame.node,
          idealMeasurement: frame.idealMeasurement,
          axis: axis
        ) {
          maximums[frame.node.identity] = direct.value
          continue
        }

        work.append(
          .init(
            node: frame.node,
            idealMeasurement: frame.idealMeasurement,
            visited: true
          )
        )
        let stackChildren = stackChildren(for: frame.node)
        for (child, measurement)
          in zip(stackChildren, frame.idealMeasurement.childMeasurements).reversed()
        {
          work.append(.init(node: child, idealMeasurement: measurement, visited: false))
        }
        continue
      }

      let stackChildren = stackChildren(for: frame.node)
      let childPairs = Array(zip(stackChildren, frame.idealMeasurement.childMeasurements))
      let childMaximums: [Int?] = childPairs.map { child, measurement in
        maximums[child.identity]
          ?? .some(mainDimension(of: measurement.measuredSize, for: axis))
      }
      maximums[frame.node.identity] = compositeMaximumMainSize(
        for: frame.node,
        idealMeasurement: frame.idealMeasurement,
        childMaximums: childMaximums,
        stackChildren: stackChildren,
        axis: axis
      )
    }

    return maximums[node.identity]
      ?? .some(mainDimension(of: idealMeasurement.measuredSize, for: axis))
  }

  /// Wrapper distinguishing "resolved without children" from "needs the
  /// child maximums first". `value == nil` means unbounded.
  private struct DirectMaximum {
    var value: Int?
  }

  private func directMaximumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> DirectMaximum? {
    let idealMain = mainDimension(of: idealMeasurement.measuredSize, for: axis)

    if node.layoutRealizedContent != nil {
      return DirectMaximum(value: nil)
    }
    if isSpacer(node) {
      return DirectMaximum(value: nil)
    }
    if isFixedSize(node.layoutMetadata, on: axis) {
      return DirectMaximum(value: idealMain)
    }

    switch node.layoutBehavior {
    case .intrinsic:
      switch node.drawPayload {
      case .shape, .canvas, .foreignSurface:
        return DirectMaximum(value: nil)
      case .rule:
        if let ruleStackAxis = node.drawMetadata.ruleStackAxis, ruleStackAxis != axis {
          return DirectMaximum(value: nil)
        }
        return DirectMaximum(value: idealMain)
      case .text, .richText, .textFigure, .image, .list, .table:
        return DirectMaximum(value: idealMain)
      case .none:
        // An explicit intrinsic size pins the node regardless of
        // children (mirrors `measuredSize`'s intrinsic precedence).
        if node.intrinsicSize != nil || node.children.isEmpty {
          return DirectMaximum(value: idealMain)
        }
        return nil
      }
    case .frame(let width, let height, _):
      let explicit: Int? =
        switch axis {
        case .horizontal: width
        case .vertical: height
        }
      if let explicit {
        return DirectMaximum(value: explicit)
      }
      return nil
    case .flexibleFrame(let minW, let idealW, let maxW, let minH, let idealH, let maxH, _):
      let (axisMin, axisIdeal, axisMax):
        (ProposedDimension?, ProposedDimension?, ProposedDimension?) =
          switch axis {
          case .horizontal: (minW, idealW, maxW)
          case .vertical: (minH, idealH, maxH)
          }
      if case .infinity = axisMax {
        return DirectMaximum(value: nil)
      }
      if case .finite(let cap) = axisMax {
        return DirectMaximum(value: cap)
      }
      guard hasFlexibleConstraint(min: axisMin, ideal: axisIdeal, max: axisMax) else {
        // No constraint on this axis: the frame passes the proposal
        // through, so the child decides.
        return nil
      }
      // min/ideal-only on this axis: the measured response would fill
      // any finite proposal, but today's allocator never offers such a
      // frame more than its ideal — keep it rigid so that stays true.
      return DirectMaximum(value: idealMain)
    case .viewThatFits:
      return DirectMaximum(value: idealMain)
    case .custom:
      if subtreeHasFlexibleContent(node, axis: axis) {
        return DirectMaximum(value: nil)
      }
      return DirectMaximum(value: idealMain)
    case .stack, .lazyStack, .overlay, .padding, .safeAreaIgnoring, .safeAreaInset,
      .border, .offset, .position, .decoration:
      return nil
    }
  }

  private func compositeMaximumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    childMaximums: [Int?],
    stackChildren: [ResolvedNode],
    axis: Axis
  ) -> Int? {
    let idealMain = mainDimension(of: idealMeasurement.measuredSize, for: axis)

    switch node.layoutBehavior {
    case .intrinsic:
      return boundedMaximum(of: childMaximums) ?? idealMain
    case .overlay:
      // Overlay's first child is the content; overlays are pinned to it.
      guard let content = childMaximums.first else {
        return idealMain
      }
      return content
    case .offset, .position, .safeAreaIgnoring:
      guard let content = childMaximums.first else {
        return idealMain
      }
      return content
    case .decoration(let primaryIndex, _):
      // Backgrounds/overlays size to the primary child; a flexible
      // Rectangle background must not make rigid content flexible.
      guard childMaximums.indices.contains(primaryIndex) else {
        return boundedMaximum(of: childMaximums) ?? idealMain
      }
      return childMaximums[primaryIndex]
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      guard let base = childMaximums.first else {
        return idealMain
      }
      let insetMaximum = childMaximums.dropFirst().first ?? .some(0)
      let insetAxis: Axis =
        switch edge {
        case .top, .bottom: .vertical
        case .leading, .trailing: .horizontal
        }
      if axis == insetAxis {
        guard let base, let inset = insetMaximum else {
          return nil
        }
        let allowance = safeArea.value(for: edge)
        return base + max(0, inset + spacing - allowance)
      }
      guard let base, let inset = insetMaximum else {
        return nil
      }
      return max(base, inset)
    case .stack(axis: let stackAxis, let spacing, _, _),
      .lazyStack(axis: let stackAxis, let spacing, _, _):
      if stackAxis == axis {
        var total = resolvedStackSpacings(
          for: stackChildren,
          axis: axis,
          spacingOverride: spacing
        ).reduce(0, +)
        for childMaximum in childMaximums {
          guard let childMaximum else {
            return nil
          }
          total += childMaximum
        }
        return total
      }
      return boundedMaximum(of: childMaximums) ?? idealMain
    case .padding(let insets):
      guard let content = childMaximums.first, let content else {
        return childMaximums.first == nil ? idealMain : nil
      }
      return content + (axis == .horizontal ? insets.horizontal : insets.vertical)
    case .border(let set, let placement, _, _, _, _, let sides):
      let insets = borderLayoutInsets(
        set: set,
        placement: placement,
        sides: sides
      )
      guard let content = childMaximums.first, let content else {
        return childMaximums.first == nil ? idealMain : nil
      }
      return content + (axis == .horizontal ? insets.horizontal : insets.vertical)
    case .frame:
      guard let content = childMaximums.first else {
        return idealMain
      }
      return content
    case .flexibleFrame:
      // Only the pass-through case (no constraint on this axis) reaches
      // the composite step.
      guard let content = childMaximums.first else {
        return idealMain
      }
      return content
    case .viewThatFits, .custom:
      return idealMain
    }
  }

  /// Maximum over child maximums where any unbounded child makes the
  /// union unbounded. Returns `.some(nil)` for that case and `nil` when
  /// there are no children.
  private func boundedMaximum(of childMaximums: [Int?]) -> Int?? {
    guard !childMaximums.isEmpty else {
      return nil
    }
    var best = 0
    for childMaximum in childMaximums {
      guard let childMaximum else {
        return .some(nil)
      }
      best = max(best, childMaximum)
    }
    return .some(best)
  }
}
