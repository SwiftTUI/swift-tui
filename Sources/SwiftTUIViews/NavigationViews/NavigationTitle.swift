package import SwiftTUICore

package enum NavigationTitlePreferenceKey: PreferenceKey {
  package static var defaultValue: String? { nil }

  package static func reduce(
    value: inout String?,
    nextValue: () -> String?
  ) {
    if let next = nextValue() {
      value = next
    }
  }
}

extension View {
  /// Sets the title contributed by this view to its navigation stack's toolbar
  /// chrome.
  ///
  /// `NavigationStack` remains chrome-neutral by itself. Apply a toolbar style
  /// to the stack to render the visible destination's title.
  public func navigationTitle(_ title: String) -> some View {
    modifier(NavigationTitleModifier(title: title))
  }
}

/// The modifier value produced by ``View/navigationTitle(_:)``.
public struct NavigationTitleModifier: PrimitiveViewModifier, Sendable {
  package var title: String

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues[NavigationTitlePreferenceKey.self] = title
    return [node]
  }
}
