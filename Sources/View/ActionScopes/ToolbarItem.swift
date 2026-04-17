public import Core

/// A declarative description of a single toolbar item contributed by a
/// descendant view via `.toolbarItem(_:)`.
///
/// Items are hoisted up the resolved tree via `ToolbarItemsPreferenceKey`
/// until the nearest ancestor `ActionScope` with a `.toolbar(style:)`
/// modifier absorbs them and renders a toolbar strip.
public struct ToolbarItemConfig: Sendable {
  public enum Position: Sendable {
    case top
    case bottom
    case automatic
  }

  public var title: String
  public var icon: Image?
  public var position: Position
  public var isEnabled: Bool
  public var action: @MainActor @Sendable () -> Void

  public init(
    title: String,
    icon: Image? = nil,
    position: Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.title = title
    self.icon = icon
    self.position = position
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// Preference key that accumulates toolbar-item contributions from
/// descendants up to the nearest ActionScope that has declared a
/// toolbar. Consumed and cleared at that scope.
package enum ToolbarItemsPreferenceKey: PreferenceKey {
  package static var defaultValue: [ToolbarItemConfig] { [] }

  package static func reduce(
    value: inout [ToolbarItemConfig],
    nextValue: () -> [ToolbarItemConfig]
  ) {
    value.append(contentsOf: nextValue())
  }
}

extension View {
  /// Contributes a single toolbar item to the nearest enclosing
  /// ActionScope that has declared a `.toolbar(style:)` modifier.
  ///
  /// Contributions accumulate in declaration order and are delivered
  /// as a single aggregated list to the absorbing scope.
  public func toolbarItem(_ config: ToolbarItemConfig) -> some View {
    ToolbarItemContribution(content: self, config: config)
  }
}

private struct ToolbarItemContribution<Content: View>: View, ResolvableView {
  let content: Content
  let config: ToolbarItemConfig

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(
      ToolbarItemsPreferenceKey.self,
      value: [config]
    )
    return [node]
  }
}
