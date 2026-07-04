public import SwiftTUICore

/// A palette-command contribution carried via
/// `PaletteCommandsPreferenceKey` and absorbed by `.paletteSheet(...)`
/// at the nearest enclosing `ActionScope`. The absorbing scope passes
/// the snapshot from its subtree into the sheet content closure.
public struct ActivePaletteCommand: Sendable {
  public let name: String
  public let description: String?
  public let isEnabled: Bool
  public let action: @MainActor @Sendable () -> Void

  package init(
    name: String,
    description: String?,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// Preference key that accumulates `paletteCommand` contributions from
/// every descendant in a scope's subtree. Consumed and cleared at the
/// nearest `ActionScope` host with a `.paletteSheet(...)` modifier
/// (i.e. the `ActionScope`-scoped overload), which passes the absorbed
/// snapshot into the sheet content closure. Mirrors
/// `ToolbarItemsPreferenceKey`.
package enum PaletteCommandsPreferenceKey: PreferenceKey {
  package static var defaultValue: [ActivePaletteCommand] { [] }

  package static func reduce(
    value: inout [ActivePaletteCommand],
    nextValue: () -> [ActivePaletteCommand]
  ) {
    value.append(contentsOf: nextValue())
  }
}

extension ActionScope where Self: View & Sendable {
  /// Declares a searchable, consumer-invocable command. Contributions
  /// bubble up to the nearest enclosing `.paletteSheet(...)` (an
  /// `ActionScope`), which absorbs them and passes the snapshot into
  /// its content closure. Mirrors `.toolbarItem(...)` ↔ `.toolbar(style:)`.
  @MainActor
  public func paletteCommand(
    name: String,
    description: String? = nil,
    isEnabled: Bool = true,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View & ActionScope & Sendable {
    modifier(
      PaletteCommandRegistrationModifier(
        name: name,
        description: description,
        isEnabled: isEnabled,
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }
}

public struct PaletteCommandRegistrationModifier: PrimitiveViewModifier, Sendable {
  package let name: String
  package let description: String?
  package let isEnabled: Bool
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable () -> Void

  package init(
    name: String,
    description: String?,
    isEnabled: Bool,
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = (currentImperativeAuthoringContextSnapshot() ?? authoringContext)?
      .withEnvironmentValues(context.environmentValues)
    let contribution = ActivePaletteCommand(
      name: name,
      description: description,
      isEnabled: isEnabled,
      action: {
        withImperativeAuthoringContext(dynamicPropertyScope) {
          action()
        }
      }
    )
    node.preferenceValues.merge(
      PaletteCommandsPreferenceKey.self,
      value: [contribution]
    )
    return [node]
  }
}
