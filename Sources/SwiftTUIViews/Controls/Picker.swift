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
  IterativeResolvableView
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

  package func makeResolveWork(
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    resolvedNode(in: context).map { [$0] }
  }
}

extension Picker {
  struct Option: Sendable {
    var tag: SelectionTag
    var label: String
    var accessibilityLabel: String
    var identity: Identity
    var isEnabled: Bool
    var token: String = ""
  }

  private struct SelectionTokens: Sendable {
    struct Key: Hashable, Sendable {
      var identity: Identity
      var tag: AnyID
    }
    var next: UInt64 = 0
    var current: [Key: String] = [:]

    mutating func assign(_ options: inout [Option]) {
      var retained: [Key: String] = [:]
      for index in options.indices {
        let key = Key(identity: options[index].identity, tag: options[index].tag.identityValue)
        let token: String
        if let existing = current[key] {
          token = existing
        } else {
          next += 1
          token = String(next)
        }
        options[index].token = token
        retained[key] = token
      }
      current = retained
    }
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
  ) -> ResolveWork<ResolvedNode> {
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
    return resolvedOptions(
      in: context.child(component: .named("PickerOptions"))
    ).flatMap { resolvedOptions in
      var options = resolvedOptions.options
      var tokens =
        ownerNode?.stateSlot(
          ordinal: StateSlotOrdinals.pickerSelectionTokens, seed: SelectionTokens()
        ) ?? SelectionTokens()
      tokens.assign(&options)
      ownerNode?.setStateSlotSilently(
        ordinal: StateSlotOrdinals.pickerSelectionTokens, value: tokens)
      let enabledTags = options.filter(\.isEnabled).map(\.tag)
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
            orderedTags: enabledTags,
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
            orderedTags: enabledTags,
            delta: delta
          )
          return handled ? .claimed : .ignored
        }

        for (index, option) in options.enumerated() where option.isEnabled {
          let routeID = runtimePrimaryRouteID(
            for: pickerOptionIdentity(
              for: context.identity,
              index: index
            )
          )
          intake.registerPointerHandler(routeID: routeID) { event in
            switch event.kind {
            case .down(.primary):
              let before = binding.wrappedValue
              _ = setBoundSelection(binding, to: option.tag)
              if wantsTrigger, before != binding.wrappedValue {
                setPickerMenuExpanded(false, in: ownerNode, identity: context.identity)
              }
              return .claimed
            case .up(.primary):
              return .claimed
            default:
              return .ignored
            }
          }
        }

        let currentOptions = options
        intake.registerAction(
          identity: context.identity,
          accessibilityHandler: { action in
            guard case .setValue(.text(let token)) = action else { return .unsupported }
            guard let option = currentOptions.first(where: { $0.token == token }),
              option.isEnabled
            else { return .invalidValue }
            let before = binding.wrappedValue
            guard setBoundSelection(binding, to: option.tag) else { return .invalidValue }
            if wantsTrigger {
              setPickerMenuExpanded(false, in: ownerNode, identity: context.identity)
            }
            return before == binding.wrappedValue ? .unchanged : .changed
          }
        ) {
          guard wantsTrigger else { return false }
          setPickerMenuExpanded(!isActiveNavigation, in: ownerNode, identity: context.identity)
          return true
        }
        if wantsTrigger {
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
        label: .init(
          authoringContext: authoringScope, accessibilityContext: label is Text ? nil : context
        ) { label.authoredAccessibilityLabel() },
        options: options.map { .init(label: $0.label, isEnabled: $0.isEnabled) },
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
      return pickerStyle.resolveBody(
        configuration: configuration,
        in: context.child(component: .named("PickerBody"))
      ).flatMap { child in
        retainingAuthoredAccessibilitySlot(
          in: child, slot: configuration.label, required: !(label is Text), context: context)
      }.map { child in

        var node = ResolvedNode(
          identity: context.identity,
          kind: .view("Picker"),
          children: [child],
          environmentSnapshot: context.environment,
          transactionSnapshot: context.transaction,
          semanticMetadata: focusableControlMetadata(
            focusInteractions: .edit,
            accessibilityRole: .picker
          ).namingControl(with: label).accessibilityControl(
            .init(
              actions: [.focus, .setValue],
              value: .text(selectedIndex.map { options[$0].token } ?? ""),
              selection: .init(
                presentation: pickerStyle.accessibilityPresentation,
                options: options.map {
                  .init(
                    id: $0.token, label: $0.accessibilityLabel, isEnabled: isEnabled && $0.isEnabled
                  )
                })))
        )
        node.semanticMetadata.accessibilityProperties = .init(
          valueDescription: selectedIndex.map { options[$0].accessibilityLabel })
        if !resolvedOptions.runtimeIssues.isEmpty {
          node.preferenceValues.merge(
            RuntimeIssuePreferenceKey.self,
            value: resolvedOptions.runtimeIssues
          )
        }
        return node

      }
    }
  }

  private func resolvedOptions(
    in context: ResolveContext
  ) -> ResolveWork<ResolvedOptions> {
    return content.resolveElementsWork(in: context).map { nodes in

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
      var enabledValues = context.environmentValues
      enabledValues.isEnabled = context.environmentValues.isEnabled
      var disabledValues = context.environmentValues
      disabledValues.isEnabled = false
      collectOptions(
        from: nodes,
        expectedEnvironments: [
          context.environment,
          enabledValues.applying(to: context.environment),
          disabledValues.applying(to: context.environment),
        ],
        expectedTransaction: context.transaction,
        // An unmodified `Text` still carries the ambient text-layout attributes
        // every text node inherits, so the representable baseline is the ambient
        // metadata for this context — not a default-initialized `LayoutMetadata`.
        expectedLayoutMetadata: ambientTextLayoutMetadata(in: context),
        into: &result
      )
      return result
    }
  }

  private func collectOptions(
    from nodes: [ResolvedNode],
    expectedEnvironments: [EnvironmentSnapshot],
    expectedTransaction: TransactionSnapshot,
    expectedLayoutMetadata: LayoutMetadata,
    into result: inout ResolvedOptions
  ) {
    for node in nodes {
      if let tag = node.semanticMetadata.selectionTag {
        let representation = optionContentRepresentation(
          for: node,
          expectedEnvironments: expectedEnvironments,
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
              + "or PickerOption declaration for deterministic picker chrome.",
            identity: node.identity,
            source: "Picker"
          )
          if !result.runtimeIssues.contains(issue) {
            result.runtimeIssues.append(issue)
          }
        }
        result.options.append(
          Option(
            tag: tag, label: label,
            accessibilityLabel: node.semanticMetadata.accessibilityLabel ?? label,
            identity: node.identity,
            isEnabled: node.environmentSnapshot.style.isEnabled))
      } else {
        collectOptions(
          from: node.children,
          expectedEnvironments: expectedEnvironments,
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
    expectedEnvironments: [EnvironmentSnapshot],
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
    if !expectedEnvironments.contains(node.environmentSnapshot) {
      reasons.append("environment modifier")
    }
    if !node.transactionSnapshot.isReuseEquivalent(to: expectedTransaction) {
      reasons.append("transaction modifier")
    }

    var unsupportedSemantics = node.semanticMetadata
    unsupportedSemantics.selectionTag = nil
    unsupportedSemantics.accessibilityLabel = nil
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
