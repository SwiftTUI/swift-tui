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
