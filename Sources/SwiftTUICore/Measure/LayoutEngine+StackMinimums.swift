extension LayoutEngine {
  package func minimumMainSize(
    for child: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> Int {
    max(
      minimumMainDimension(
        for: child.layoutMetadata,
        axis: axis
      ) ?? 0,
      derivedMinimumMainSize(
        for: child,
        idealMeasurement: idealMeasurement,
        axis: axis
      )
    )
  }

  /// Whether re-measuring `child` with a wider cross dimension during stack
  /// reconciliation is guaranteed to produce the same measurement as its ideal
  /// pass.
  ///
  /// The reconciliation pass only helps when the subtree contains
  /// something that can actually claim the extra space along the
  /// parent's cross axis — a `Spacer` inside a stack aligned to that
  /// axis, or a `flexibleFrame` with a `.infinity` max along the
  /// axis.  Subtrees of purely rigid views (Text, nested VStacks of
  /// Texts, etc.) measure identically at any wider cross, so
  /// re-measuring them is pure waste and also evicts their retained
  /// placement cache across frames.
  package func stackChildRemeasurementIsNoop(
    _ child: ResolvedNode,
    parentStackAxis: Axis
  ) -> Bool {
    let crossAxis: Axis =
      switch parentStackAxis {
      case .horizontal: .vertical
      case .vertical: .horizontal
      }
    return !subtreeHasFlexibleContent(child, axis: crossAxis)
  }

  internal func subtreeHasFlexibleContent(
    _ node: ResolvedNode,
    axis: Axis
  ) -> Bool {
    var stack: [ResolvedNode] = [node]

    while let current = stack.popLast() {
      if current.layoutRealizedContent != nil {
        return true
      }

      switch current.layoutBehavior {
      case .intrinsic:
        switch current.drawPayload {
        case .rule:
          // A Divider/Rule fills the cross axis of its enclosing stack
          // (stored in `drawMetadata.ruleStackAxis`). A rule inside a
          // VStack expands horizontally; a rule inside an HStack
          // expands vertically. It counts as flexible on any axis that
          // isn't its own stack axis.
          if let ruleStackAxis = current.drawMetadata.ruleStackAxis {
            if ruleStackAxis != axis {
              return true
            }
            continue
          }
        case .shape, .canvas:
          // Raw shape primitives (Rectangle, RoundedRectangle, ...) and
          // Canvas views size to the proposal on every axis, so they
          // will expand to any finite cross the reconciliation hands
          // them.
          return true
        default:
          break
        }
      case .flexibleFrame(let minW, _, let maxW, let minH, _, let maxH, _):
        let (axisMin, axisMax): (ProposedDimension?, ProposedDimension?) =
          switch axis {
          case .horizontal: (minW, maxW)
          case .vertical: (minH, maxH)
          }
        if case .infinity = axisMax {
          return true
        }
        if case .finite(let lo) = axisMin ?? .finite(0),
          case .finite(let hi) = axisMax ?? .finite(0),
          hi > lo
        {
          return true
        }
      case .frame(let width, let height, _):
        // A fixed-size frame pins its axis regardless of child
        // flexibility, so that axis is not flexible. The other axis
        // still passes through to the child.
        let explicit: Int? =
          switch axis {
          case .horizontal: width
          case .vertical: height
          }
        if explicit != nil {
          continue
        }
      case .stack(let stackAxis, _, _, _), .lazyStack(let stackAxis, _, _, _):
        if stackAxis == axis, current.children.contains(where: isSpacer) {
          return true
        }
      case .decoration(let primaryIndex, _):
        // A decoration (background/overlay) sizes its non-primary
        // children to match the primary child, so only the primary
        // contributes flexibility. Walking into background Rectangles
        // would otherwise spuriously mark Text-with-background as
        // flexible on every axis.
        guard current.children.indices.contains(primaryIndex) else {
          continue
        }
        stack.append(current.children[primaryIndex])
        continue
      case .overlay:
        // Overlay's first child is the content; additional children
        // are overlays pinned to the content's size. Only the content
        // contributes flexibility.
        guard let content = current.children.first else {
          continue
        }
        stack.append(content)
        continue
      case .safeAreaInset:
        guard let base = current.children.first else {
          continue
        }
        stack.append(base)
        continue
      default:
        break
      }

      stack.append(contentsOf: current.children)
    }

    return false
  }

  package func isFixedSize(
    _ metadata: LayoutMetadata,
    on axis: Axis
  ) -> Bool {
    switch axis {
    case .horizontal:
      return metadata.fixedSizeHorizontal
    case .vertical:
      return metadata.fixedSizeVertical
    }
  }

  package func minimumMainDimension(
    for metadata: LayoutMetadata,
    axis: Axis
  ) -> Int? {
    switch axis {
    case .horizontal:
      return metadata.minimumWidth
    case .vertical:
      return metadata.minimumHeight
    }
  }

  package func derivedMinimumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    axis: Axis
  ) -> Int {
    struct MinimumFrame {
      var node: ResolvedNode
      var idealMeasurement: MeasuredNode
      var visited: Bool
    }

    var work: [MinimumFrame] = [
      .init(node: node, idealMeasurement: idealMeasurement, visited: false)
    ]
    var minimums: [Identity: Int] = [:]

    while let frame = work.popLast() {
      if isFixedSize(frame.node.layoutMetadata, on: axis) || isSpacer(frame.node) {
        minimums[frame.node.identity] = mainDimension(
          of: frame.idealMeasurement.measuredSize,
          for: axis
        )
        continue
      }

      let stackChildren = stackChildren(for: frame.node)
      let childPairs = Array(zip(stackChildren, frame.idealMeasurement.childMeasurements))

      if !frame.visited {
        work.append(
          .init(
            node: frame.node,
            idealMeasurement: frame.idealMeasurement,
            visited: true
          )
        )
        for (child, measurement) in childPairs.reversed() {
          work.append(.init(node: child, idealMeasurement: measurement, visited: false))
        }
        continue
      }

      let childMinimums = childPairs.map { child, measurement in
        max(
          minimumMainDimension(
            for: child.layoutMetadata,
            axis: axis
          ) ?? 0,
          minimums[child.identity]
            ?? mainDimension(of: measurement.measuredSize, for: axis)
        )
      }
      minimums[frame.node.identity] = derivedMinimumMainSize(
        for: frame.node,
        idealMeasurement: frame.idealMeasurement,
        childMinimums: childMinimums,
        stackChildren: stackChildren,
        axis: axis
      )
    }

    return minimums[node.identity] ?? 0
  }

  private func derivedMinimumMainSize(
    for node: ResolvedNode,
    idealMeasurement: MeasuredNode,
    childMinimums: [Int],
    stackChildren: [ResolvedNode],
    axis: Axis
  ) -> Int {
    switch node.layoutBehavior {
    case .intrinsic:
      if case .textFigure(let payload) = node.drawPayload {
        if axis == .horizontal {
          return TextFigureSupport.layoutMetrics(for: payload).minimumWidth
        }
        if !payload.content.isEmpty {
          return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
        }
      }
      if case .text(let content) = node.drawPayload,
        axis == .vertical,
        !content.isEmpty
      {
        return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
      }
      if case .richText(let payload) = node.drawPayload,
        axis == .vertical,
        !payload.visibleText.isEmpty
      {
        return min(1, mainDimension(of: idealMeasurement.measuredSize, for: axis))
      }
      return childMinimums.max() ?? 0
    case .overlay, .offset, .position, .decoration, .safeAreaIgnoring:
      return childMinimums.max() ?? 0
    case .safeAreaInset(let edge, _, let spacing, let safeArea):
      let baseMinimum = childMinimums.first ?? 0
      let insetMinimum = childMinimums.dropFirst().first ?? 0
      let safeAreaAllowance = safeArea.value(for: edge)
      let consumed = max(0, insetMinimum + spacing - safeAreaAllowance)
      switch edge {
      case .top, .bottom:
        if axis == .vertical {
          return baseMinimum + consumed
        }
        return max(baseMinimum, insetMinimum)
      case .leading, .trailing:
        if axis == .horizontal {
          return baseMinimum + consumed
        }
        return max(baseMinimum, insetMinimum)
      }
    case .stack(
      axis: let stackAxis,
      let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      if stackAxis == axis {
        let spacingBudget = resolvedStackSpacings(
          for: stackChildren,
          axis: axis,
          spacingOverride: spacing
        ).reduce(0, +)
        return childMinimums.reduce(0, +) + spacingBudget
      }
      return childMinimums.max() ?? 0
    case .lazyStack(
      axis: let stackAxis,
      let spacing,
      horizontalAlignment: _,
      verticalAlignment: _
    ):
      if stackAxis == axis {
        let spacingBudget = resolvedStackSpacings(
          for: stackChildren,
          axis: axis,
          spacingOverride: spacing
        ).reduce(0, +)
        return childMinimums.reduce(0, +) + spacingBudget
      }
      return childMinimums.max() ?? 0
    case .padding(let insets):
      let contentMinimum = childMinimums.first ?? 0
      return contentMinimum + (axis == .horizontal ? insets.horizontal : insets.vertical)
    case .border(let set, let placement, _, _, _, _, let sides):
      let insets = borderLayoutInsets(
        set: set,
        placement: placement,
        sides: sides
      )
      let contentMinimum = childMinimums.first ?? 0
      return contentMinimum + (axis == .horizontal ? insets.horizontal : insets.vertical)
    case .frame(let width, let height, _):
      let explicit =
        switch axis {
        case .horizontal:
          width
        case .vertical:
          height
        }
      return max(explicit ?? 0, childMinimums.first ?? 0)
    case .flexibleFrame(let minW, _, _, let minH, _, _, _):
      let minDim: ProposedDimension? =
        switch axis {
        case .horizontal:
          minW
        case .vertical:
          minH
        }
      if case .finite(let v) = minDim {
        return max(v, childMinimums.first ?? 0)
      }
      return childMinimums.first ?? 0
    case .viewThatFits:
      return childMinimums.max() ?? 0
    case .custom(let token):
      guard let handle = token as? CustomLayoutHandle else {
        preconditionFailure("LayoutBehavior.custom must carry a CustomLayoutHandle")
      }
      return handle.stackMinimumMainSize(
        engine: self,
        node: node,
        idealMeasurement: idealMeasurement,
        axis: axis,
        passContext: nil
      ) ?? 0
    }
  }
}
