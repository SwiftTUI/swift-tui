import SwiftTUICore

@MainActor
private func setPickerMenuExpanded(
  _ expanded: Bool, in ownerNode: SwiftTUICore.ViewNode?, identity: Identity
) {
  ownerNode?.setStateSlot(
    ordinal: StateSlotOrdinals.pickerMenuExpansion,
    value: expanded as Bool?,
    invalidationIdentity: identity
  )
}

/// Selects one value from a set of tagged options.
public struct Picker<SelectionValue: Hashable, Label: View, Content: View>: PrimitiveView,
  ResolvableView
{
  public var selection: Binding<SelectionValue>
  package var label: Label
  package var content: Content
  private let authoringScope: AuthoringContext?

  public init<S: StringProtocol>(
    _ title: S,
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    self.selection = selection
    label = Text(String(title))
    self.content = content()
    authoringScope = currentAuthoringContext()
  }

  public init(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.label = label()
    self.content = content()
    authoringScope = currentAuthoringContext()
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

  private struct ResolvedOptions {
    var options: [Option] = []
    var runtimeIssues: [RuntimeIssue] = []
  }

  private enum OptionContentRepresentation {
    case representable(label: String)
    case unrepresentable(label: String, reasons: [String])
  }

  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let pickerStyle = context.environmentValues.pickerStyle
    let isFocused =
      context.environmentValues.focusedIdentity(comparedAgainst: [context.identity])
      == context.identity
    let isEnabled = context.environmentValues.isEnabled
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let wantsTrigger = pickerStyle.wantsTriggerPointerRoute
    let ownerNode = ViewNodeContext.current ?? context.viewGraph?.nodeForIdentity(context.identity)
    let expansion =
      ownerNode?.stateSlot(
        ordinal: StateSlotOrdinals.pickerMenuExpansion,
        seed: nil as Bool?
      ) ?? nil
    if !isFocused || !isEnabled || !wantsTrigger, expansion != nil {
      ownerNode?.setStateSlotSilently(
        ordinal: StateSlotOrdinals.pickerMenuExpansion,
        value: nil as Bool?
      )
    }
    // Until explicitly toggled, preserve the menu's expanded-on-focus default.
    let isActiveNavigation = isFocused && isEnabled && (!wantsTrigger || (expansion ?? true))
    let resolvedOptions = resolvedOptions(
      in: context.child(component: .named("PickerOptions"))
    )
    let options = resolvedOptions.options
    let selectedIndex = options.firstIndex { option in
      pickerSelectionMatches(
        option.tag,
        selection: selection.wrappedValue
      )
    }

    if isEnabled {
      let binding = selection
      let intake = HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringScope
      )
      intake.registerKeyPressHandler(identity: context.identity) { keyPress in
        guard keyPress.modifiers.isEmpty else {
          return false
        }
        if wantsTrigger, keyPress.key == .escape, isActiveNavigation {
          setPickerMenuExpanded(false, in: ownerNode, identity: context.identity)
          return true
        }
        let delta = pickerStyle.selectionDelta(for: keyPress.key)
        guard let delta, !options.isEmpty else {
          return false
        }

        if wantsTrigger {
          setPickerMenuExpanded(true, in: ownerNode, identity: context.identity)
        }
        return stepBoundSelection(
          binding,
          orderedTags: options.map(\.tag),
          delta: delta
        )
      }

      let rootRouteID = runtimePrimaryRouteID(for: context.identity)
      intake.registerPointerHandler(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind,
          let delta = pointerSelectionDelta(deltaX: deltaX, deltaY: deltaY)
        else {
          return .ignored
        }

        let handled = stepBoundSelection(
          binding,
          orderedTags: options.map(\.tag),
          delta: delta
        )
        return handled ? .claimed : .ignored
      }

      for (index, option) in options.enumerated() {
        let routeID = runtimePrimaryRouteID(
          for: pickerOptionIdentity(
            for: context.identity,
            index: index
          )
        )
        intake.registerPointerHandler(routeID: routeID) { event in
          switch event.kind {
          case .down(.primary):
            _ = setBoundSelection(binding, to: option.tag)
            return .claimed
          case .up(.primary):
            return .claimed
          default:
            return .ignored
          }
        }
      }

      if wantsTrigger {
        intake.registerAction(identity: context.identity) {
          setPickerMenuExpanded(!isActiveNavigation, in: ownerNode, identity: context.identity)
          return true
        }
        let triggerRouteID = runtimePrimaryRouteID(
          for: pickerTriggerIdentity(for: context.identity)
        )
        intake.registerPointerHandler(routeID: triggerRouteID) { event in
          switch event.kind {
          case .down(.primary):
            setPickerMenuExpanded(!isActiveNavigation, in: ownerNode, identity: context.identity)
            return .claimed
          case .up(.primary):
            return .claimed
          default:
            return .ignored
          }
        }
      }
    }

    var configuration = PickerStyleConfiguration(
      controlIdentity: context.identity,
      label: .init(authoringContext: authoringScope) { label },
      options: options.map { .init(label: $0.label) },
      selectedIndex: selectedIndex,
      isFocused: isFocused,
      isActiveNavigation: isActiveNavigation,
      showsFocusEffect: showsFocusEffect,
      isEnabled: isEnabled,
      styleEnvironment: styleEnvironment,
      viewportLineCount: context.environmentValues.pickerViewportLineCount,
      lineWidth: context.environmentValues.pickerLineWidth
    )
    configuration.bindRoutes(to: context.identity)
    let child = pickerStyle.resolveBody(
      configuration: configuration,
      in: context.child(component: .named("PickerBody"))
    )

    var node = ResolvedNode(
      identity: context.identity,
      kind: .view("Picker"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .edit,
        accessibilityRole: .picker
      )
    )
    if !resolvedOptions.runtimeIssues.isEmpty {
      node.preferenceValues.merge(
        RuntimeIssuePreferenceKey.self,
        value: resolvedOptions.runtimeIssues
      )
    }
    return node
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> ResolvedOptions {
    let nodes = content.resolveElements(in: context)

    // The authored options resolve ONLY to extract tags/labels — the style
    // body renders separate `PickerOption` chrome, so these resolved nodes
    // are committed nowhere. Any ViewNodes the resolution minted (a
    // `ForEach`'s tagged rows carrying option state) are reachable through
    // neither committed values nor parent links; resolve-lifetime scope owns
    // each at the nearest declaring host so picker teardown reaches them.
    for node in nodes {
      context.viewGraph?.reportDetachedResolvedLifetimeResult(node)
    }

    var result = ResolvedOptions()
    collectOptions(
      from: nodes,
      expectedEnvironment: context.environment,
      expectedTransaction: context.transaction,
      // An unmodified `Text` still carries the ambient text-layout attributes
      // every text node inherits, so the representable baseline is the ambient
      // metadata for this context — not a default-initialized `LayoutMetadata`.
      expectedLayoutMetadata: ambientTextLayoutMetadata(in: context),
      into: &result
    )
    return result
  }

  private func collectOptions(
    from nodes: [ResolvedNode],
    expectedEnvironment: EnvironmentSnapshot,
    expectedTransaction: TransactionSnapshot,
    expectedLayoutMetadata: LayoutMetadata,
    into result: inout ResolvedOptions
  ) {
    for node in nodes {
      if let tag = node.semanticMetadata.selectionTag {
        let representation = optionContentRepresentation(
          for: node,
          expectedEnvironment: expectedEnvironment,
          expectedTransaction: expectedTransaction,
          expectedLayoutMetadata: expectedLayoutMetadata
        )
        let label: String
        switch representation {
        case .representable(let extractedLabel):
          label = extractedLabel
        case .unrepresentable(let extractedLabel, let reasons):
          label = extractedLabel
          let issue = RuntimeIssue(
            severity: .warning,
            code: "picker.unrepresentableOptionContent",
            message:
              "Picker option content cannot be represented by the text-only option metadata "
              + "model (discarded: \(reasons.joined(separator: ", "))). "
              + "The extracted text and tag remain active; use a single unmodified Text value "
              + "for deterministic picker chrome.",
            identity: node.identity,
            source: "Picker"
          )
          if !result.runtimeIssues.contains(issue) {
            result.runtimeIssues.append(issue)
          }
        }
        result.options.append(Option(tag: tag, label: label))
      } else {
        collectOptions(
          from: node.children,
          expectedEnvironment: expectedEnvironment,
          expectedTransaction: expectedTransaction,
          expectedLayoutMetadata: expectedLayoutMetadata,
          into: &result
        )
      }
    }
  }

  /// Classifies the exact boundary the Picker metadata model can preserve.
  /// A tagged, unmodified `Text` leaf is lossless. Everything else still
  /// contributes its recursively extracted text and tag, but reports which
  /// authored structure or behavior was discarded.
  private func optionContentRepresentation(
    for node: ResolvedNode,
    expectedEnvironment: EnvironmentSnapshot,
    expectedTransaction: TransactionSnapshot,
    expectedLayoutMetadata: LayoutMetadata
  ) -> OptionContentRepresentation {
    let label = resolvedNodeLabelText(from: node)
    var reasons: [String] = []

    if case .view("Text") = node.kind {
      // Expected primitive shape.
    } else {
      reasons.append("non-Text structure")
    }

    if !node.children.isEmpty {
      reasons.append("child layout structure")
    }
    if node.layoutBehavior != .intrinsic || node.layoutMetadata != expectedLayoutMetadata {
      reasons.append("layout modifier")
    }
    if node.drawMetadata != .init() || !node.drawEffects.isEmpty {
      reasons.append("visual modifier")
    }
    if node.environmentSnapshot != expectedEnvironment {
      reasons.append("environment modifier")
    }
    if !node.transactionSnapshot.isReuseEquivalent(to: expectedTransaction) {
      reasons.append("transaction modifier")
    }

    var unsupportedSemantics = node.semanticMetadata
    unsupportedSemantics.selectionTag = nil
    if unsupportedSemantics != .init() {
      reasons.append("semantic modifier")
    }
    if !node.lifecycleMetadata.isEmpty
      || node.handlerInventory != .init()
      || !node.preferenceValues.isEmpty
    {
      reasons.append("behavior modifier")
    }
    if node.surfaceComposition != .normal || node.matchedGeometry != nil {
      reasons.append("composition modifier")
    }

    if reasons.isEmpty {
      return .representable(label: label)
    }
    return .unrepresentable(
      label: label,
      reasons: Array(Set(reasons)).sorted()
    )
  }
}
