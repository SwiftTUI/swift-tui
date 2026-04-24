package import Core

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

  @MainActor
  public init(
    title: String,
    icon: Image? = nil,
    position: Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    let authoringContext = currentImperativeAuthoringContextSnapshot()
    self.title = title
    self.icon = icon
    self.position = position
    self.isEnabled = isEnabled
    self.action = {
      withImperativeAuthoringContext(authoringContext) {
        action()
      }
    }
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
  @MainActor
  public func toolbarItem(_ config: ToolbarItemConfig) -> some View {
    modifier(
      ToolbarItemContributionModifier(
        config: config,
        authoringContext: currentImperativeAuthoringContextSnapshot()
      )
    )
  }
}

public struct ToolbarItemContributionModifier: PrimitiveViewModifier, Sendable {
  package let config: ToolbarItemConfig
  package let authoringContext: ImperativeAuthoringContextSnapshot?

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentImperativeAuthoringContextSnapshot() ?? authoringContext
    var wrappedConfig = config
    wrappedConfig.action = { [action = config.action] in
      withImperativeAuthoringContext(dynamicPropertyScope) {
        action()
      }
    }
    node.preferenceValues.merge(
      ToolbarItemsPreferenceKey.self,
      value: [wrappedConfig]
    )
    return [node]
  }
}

extension View {
  /// Contributes a toolbar item whose label and icon are supplied as
  /// view builders. The contributed item is delivered to the nearest
  /// enclosing ActionScope with a `.toolbar(style:)` modifier.
  ///
  /// The current implementation stores a text title extracted from the
  /// label builder. A richer label/icon render path lands once toolbar
  /// rendering grows beyond a plain-text strip.
  @MainActor
  public func toolbarItem<Label: View, Icon: View>(
    position: ToolbarItemConfig.Position = .automatic,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    let labelText = extractPrimaryText(from: label()) ?? ""
    _ = icon()
    return toolbarItem(
      ToolbarItemConfig(
        title: labelText,
        position: position,
        isEnabled: isEnabled,
        action: action
      )
    )
  }
}

/// Best-effort title extraction from a label view. Handles a plain
/// `Text` directly; returns nil for anything else. The builder variant
/// of `.toolbarItem` falls back to an empty string when extraction
/// fails, which is acceptable until the toolbar render path plumbs
/// full label views through.
@MainActor
private func extractPrimaryText<Label: View>(from label: Label) -> String? {
  if let text = label as? Text {
    return text.content
  }
  return nil
}
