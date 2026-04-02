package import Core

/// Selects one value from a set of tagged options.
public struct Picker<SelectionValue: Hashable, Label: View, Content: View>: View,
  ResolvableView
{
  public var selection: Binding<SelectionValue>
  package var label: Label
  package var content: Content
  private let authoringScope: DynamicPropertyScope?

  public init<S: StringProtocol>(
    _ title: S,
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    self.selection = selection
    label = Text(String(title))
    self.content = content()
    authoringScope = currentDynamicPropertyScope()
  }

  public init(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.label = label()
    self.content = content()
    authoringScope = currentDynamicPropertyScope()
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
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let pickerStyle =
      context.environmentValues.pickerStyle == .automatic
      ? PickerStyle.inline
      : context.environmentValues.pickerStyle
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let options = resolvedOptions(in: context.child(component: .named("PickerOptions")))
    let selectedIndex = options.firstIndex { option in
      pickerSelectionMatches(
        option.tag,
        selection: selection.wrappedValue
      )
    }

    if isEnabled {
      let binding = selection
      let dynamicPropertyScope = currentDynamicPropertyScope() ?? authoringScope
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

        return withDynamicPropertyScope(dynamicPropertyScope) {
          stepBoundSelection(
            binding,
            orderedTags: options.map(\.tag),
            delta: delta
          )
        }
      }

      let rootRouteID = primaryRouteID(for: context.identity)
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
        let routeID = primaryRouteID(
          for: pickerOptionIdentity(
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
        let triggerRouteID = primaryRouteID(
          for: pickerTriggerIdentity(for: context.identity)
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
      styleEnvironment: styleEnvironment,
      viewportLineCount: context.environmentValues.pickerViewportLineCount,
      lineWidth: context.environmentValues.pickerLineWidth
    )
    let child = body.resolve(
      in: context.child(component: .named("PickerBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Picker"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        presentationRole: .picker
      )
    )
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> [Option] {
    let nodes = content.resolveElements(in: context)

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
            label: resolvedNodeLabelText(from: node)
          )
        )
      } else {
        collectOptions(from: node.children, into: &options)
      }
    }
  }
}
