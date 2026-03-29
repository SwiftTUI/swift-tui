package import Core

/// Selects one value from a set of tagged options.
public struct Picker<SelectionValue: Hashable>: View, ResolvableView {
  public var selection: Binding<SelectionValue>
  var labelViews: [AnyView]
  var contentViews: [AnyView]

  public init<S: StringProtocol, Content: View>(
    _ title: S,
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) {
    self.selection = selection
    labelViews = [AnyView(Text(String(title)))]
    contentViews = parallelBuilderChildren(from: content())
  }

  public init<Content: View, Label: View>(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    labelViews = parallelBuilderChildren(from: label())
    contentViews = parallelBuilderChildren(from: content())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }
}

extension Picker {
  struct Option: Sendable {
    var tag: SelectionTag
    var label: String
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let pickerStyle =
      context.environmentValues.pickerStyle == .automatic
      ? PickerStyle.inline
      : context.environmentValues.pickerStyle
    let isFocused = context.environmentValues.parallelFocusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let appearance = context.environmentValues.terminalAppearance
    let options = resolvedOptions(in: context.child(component: "PickerOptions"))
    let selectedIndex = options.firstIndex { option in
      pickerSelectionMatches(
        option.tag,
        selection: selection.wrappedValue
      )
    }

    if isEnabled {
      let binding = selection
      let dynamicPropertyScope = currentDynamicPropertyScope()
      context.localKeyHandlerRegistry?.register(identity: context.identity) { event in
        let delta: Int?
        switch pickerStyle {
        case .segmented:
          switch event {
          case .arrowLeft:
            delta = -1
          case .arrowRight:
            delta = 1
          default:
            delta = nil
          }
        case .inline, .automatic, .radioGroup, .menu:
          switch event {
          case .arrowUp:
            delta = -1
          case .arrowDown:
            delta = 1
          default:
            delta = nil
          }
        }

        guard let delta, !options.isEmpty else {
          return false
        }

        return stepBoundSelection(
          binding,
          orderedTags: options.map(\.tag),
          delta: delta
        )
      }

      let rootRouteID = parallelPrimaryRouteID(for: context.identity)
      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return false
        }

        return withDynamicPropertyScope(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: options.map(\.tag),
            delta: delta
          )
        }
      }

      for (index, option) in options.enumerated() {
        let routeID = parallelPrimaryRouteID(
          for: parallelPickerOptionIdentity(
            for: context.identity,
            index: index
          )
        )
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          guard case .down(.primary) = event.kind else {
            return false
          }

          return withDynamicPropertyScope(dynamicPropertyScope) {
            setBoundSelection(binding, to: option.tag)
          }
        }
      }

      if pickerStyle == .menu {
        let triggerRouteID = parallelPrimaryRouteID(
          for: parallelPickerTriggerIdentity(for: context.identity)
        )
        context.localPointerHandlerRegistry?.register(routeID: triggerRouteID) { _ in
          false
        }
      }
    }

    let body = pickerBody(
      controlIdentity: context.identity,
      options: options,
      selectedIndex: selectedIndex,
      pickerStyle: pickerStyle,
      isFocused: isFocused,
      isActiveNavigation: isFocused,
      showsFocusEffect: showsFocusEffect,
      isEnabled: isEnabled,
      appearance: appearance,
      viewportLineCount: context.environmentValues.parallelPickerViewportLineCount,
      lineWidth: context.environmentValues.parallelPickerLineWidth
    )
    let child = body.resolve(
      in: context.child(component: "PickerBody")
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Picker"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: parallelFocusableControlMetadata(
        focusInteractions: .edit,
        presentationRole: .picker
      )
    )
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> [Option] {
    let nodes = combinedView(from: contentViews, kindName: "PickerContent")
      .resolveElements(in: context)

    var options: [Option] = []
    collectOptions(from: nodes, into: &options)
    return options
  }

  private func collectOptions(
    from nodes: [ResolvedNode],
    into options: inout [Option]
  ) {
    for node in nodes {
      if let tag = node.semanticMetadata.selectionTag {
        options.append(
          Option(
            tag: tag,
            label: parallelNodeLabelText(from: node)
          )
        )
      } else {
        collectOptions(from: node.children, into: &options)
      }
    }
  }
}
