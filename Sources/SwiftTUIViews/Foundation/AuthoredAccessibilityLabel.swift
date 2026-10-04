import SwiftTUICore

extension View {
  /// Marks the authored slot, before a style adds chrome or control values.
  package func authoredAccessibilityLabel() -> some View {
    AuthoredAccessibilityLabel(content: self, isValue: false)
  }

  package func authoredAccessibilityValueLabel() -> some View {
    AuthoredAccessibilityLabel(content: self, isValue: true)
  }
}

/// Stamp resolved content after capture has preserved the authored child census.
/// A view wrapper here would change menu relocation and retained state ownership.
package func markingAccessibilityContent(_ completed: [ResolvedNode]) -> [ResolvedNode] {
  var nodes = completed
  for index in nodes.indices {
    nodes[index].semanticMetadata.isAccessibilityContent = true
  }
  return nodes
}

/// Transparent forwarding keeps the authored layout elements and graph census.
/// Unlike a metadata modifier, this does not introduce a modifier-content node.
private struct AuthoredAccessibilityLabel<Content: View>: PrimitiveView, IterativeResolvableView {
  var content: Content
  var isValue: Bool

  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    return resolveViewElementsWork(content, in: context).map { completed in
      var nodes = completed
      var startsSlot = true
      for index in nodes.indices {
        guard !nodes[index].semanticMetadata.accessibilityHidden, !nodes[index].isTransient else {
          continue
        }
        let source: AccessibilityLabelSource = startsSlot ? .start : .continuation
        if isValue {
          nodes[index].semanticMetadata.accessibilityValueLabel = .source(source)
        } else {
          nodes[index].semanticMetadata.accessibilityLabelSource = source
        }
        startsSlot = false
      }
      return nodes
    }
  }
}

extension AuthoredAccessibilityLabel: AdditionalDynamicPropertyUpdating {
  func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool { index == 0 }

  mutating func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult {
    runForwardedDynamicPropertyUpdates(on: &content, in: context)
  }

  func hasAdditionalDynamicPropertyUpdateSurface() -> Bool {
    hasDynamicPropertyUpdateSurface(content)
  }
}

extension SemanticMetadata {
  @MainActor
  package func namingControl<Label: View>(with label: Label) -> Self {
    var metadata = self
    metadata.usesAuthoredAccessibilityLabel = true
    if let text = label as? Text {
      metadata.accessibilityTitle =
        text.semanticMetadata.accessibilityHidden
        ? "" : text.semanticMetadata.accessibilityLabel ?? text.content
    }
    return metadata
  }
}

/// Styles may omit a generic authored slot. Resolve that slot only when no placed
/// source exists, retaining its captured authoring scope without painting it twice.
@MainActor
package func retainingAuthoredAccessibilitySlot<Slot: View>(
  in styled: ResolvedNode, slot: Slot, required: Bool, isValue: Bool = false,
  context: ResolveContext
) -> ResolveWork<ResolvedNode> {
  guard required else { return .value(styled) }
  var stack = [styled]
  while let node = stack.popLast() {
    if isValue {
      if case .source = node.semanticMetadata.accessibilityValueLabel { return .value(styled) }
      if node.semanticMetadata.isAccessibilityContent { return .value(styled) }
    } else if node.semanticMetadata.accessibilityLabelSource != nil {
      return .value(styled)
    }
    if node.semanticMetadata.usesAuthoredAccessibilityLabel { continue }
    stack.append(contentsOf: node.children)
  }
  let slotName: StaticString = isValue ? "SemanticValue" : "SemanticLabel"
  let presentationName: StaticString =
    isValue ? "SemanticValuePresentation" : "SemanticLabelPresentation"
  return resolveViewWork(slot, in: context.child(component: .named(slotName))).map { source in
    ResolvedNode(
      identity: context.identity.child(.named(presentationName)),
      kind: .view("AuthoredAccessibilitySlot"),
      children: [styled, markingVirtualAccessibility(source, labelOnly: !isValue)],
      environmentSnapshot: context.environment, transactionSnapshot: context.transaction,
      layoutBehavior: .decoration(primaryIndex: 0, alignment: .topLeading))
  }
}
