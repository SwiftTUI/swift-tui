package import SwiftTUICore

// Tab metadata peeking.
//
// A `TabView` needs each child's label and selection tag *before* fully
// resolving it — to build the tab strip. Rather than attach that metadata to
// concrete wrapper views, authored tab children expose it structurally:
//
// - `TabItemMetadataProvidingModifier` lets a built-in modifier contribute
//   label/tag semantics.
// - `TabMetadataPeekingView` / `TabDeclarationView` are the peeking hooks the
//   `ModifiedContent` conformances satisfy by walking the modifier chain.
// - `peekTabChildMetadata(from:)` is the entry point that resolves the
//   metadata for any authored child value.
//
// Split out of `TabView.swift` so that file stays focused on the `TabView`
// view itself, its focus/selection handling, and tab-strip layout.

// MARK: - Metadata peeking

package struct PeekedTabChildMetadata {
  package var label: TabItemLabel?
  package var tag: SelectionTag?

  package init(label: TabItemLabel? = nil, tag: SelectionTag? = nil) {
    self.label = label
    self.tag = tag
  }

  package mutating func merge(_ other: PeekedTabChildMetadata) {
    if let label = other.label, label != self.label {
      self.label = self.label ?? label
    }
    if let tag = other.tag, tag != self.tag {
      self.tag = self.tag ?? tag
    }
  }
}

/// Modifier-side tab metadata semantic hook.
///
/// Built-in modifiers should report label/tag semantics here instead
/// of attaching them to concrete wrapper views.
@MainActor
package protocol TabItemMetadataProvidingModifier: ViewModifier {
  var tabItemMetadataContribution: PeekedTabChildMetadata { get }
}

/// Structured metadata-peeking hook for authored tab child trees.
@MainActor
package protocol TabMetadataPeekingView {
  var peekedTabChildMetadata: PeekedTabChildMetadata { get }
}

/// Declaration-level hook for `Tab`-style child declarations.
///
/// Future `ModifiedContent` chains that wrap a `Tab` declaration may
/// also conform so the selected child can still resolve directly
/// without a declaration wrapper node.
@MainActor
package protocol TabDeclarationView {
  var tabDeclarationMetadata: PeekedTabChildMetadata { get }
  func resolveTabDeclarationContent(in context: ResolveContext) -> ResolvedNode
}

extension ModifiedContent: TabMetadataPeekingView
where Content: View, Modifier: ViewModifier {
  package var peekedTabChildMetadata: PeekedTabChildMetadata {
    if let provider = modifier as? any TabItemMetadataProvidingModifier {
      var result = provider.tabItemMetadataContribution
      result.merge(peekTabChildMetadata(from: content))
      return result
    }
    return peekTabChildMetadata(from: content)
  }
}

extension ModifiedContent: TabDeclarationView
where Content: TabDeclarationView & View, Modifier: ViewModifier {
  package var tabDeclarationMetadata: PeekedTabChildMetadata {
    if let provider = modifier as? any TabItemMetadataProvidingModifier {
      var result = provider.tabItemMetadataContribution
      result.merge(content.tabDeclarationMetadata)
      return result
    }
    return content.tabDeclarationMetadata
  }

  package func resolveTabDeclarationContent(in context: ResolveContext) -> ResolvedNode {
    resolveView(self, in: context)
  }
}

@MainActor
package func peekTabChildMetadata(from view: Any) -> PeekedTabChildMetadata {
  if let declaration = view as? any TabDeclarationView {
    return declaration.tabDeclarationMetadata
  }
  if let peekable = view as? any TabMetadataPeekingView {
    return peekable.peekedTabChildMetadata
  }
  return PeekedTabChildMetadata()
}
