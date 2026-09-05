public import SwiftTUICore

/// A contribution absorbed by the nearest palette declaration and projected
/// into public command data with primitive-owned activation routes.
package struct ActivePaletteCommand: Sendable {
  package let identity: Identity
  package let name: String
  package let description: String?
  package let isEnabled: Bool
  package let action: @MainActor @Sendable () -> Void

  package init(
    identity: Identity,
    name: String,
    description: String?,
    isEnabled: Bool,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.identity = identity
    self.name = name
    self.description = description
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// Preference key that accumulates `paletteCommand` contributions from
/// every descendant in a scope's subtree. Consumed and cleared at the
/// nearest `ActionScope` host with a `.paletteSheet(...)` modifier
/// (i.e. the `ActionScope`-scoped overload), which passes command data to its
/// style. Mirrors
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
  /// `ActionScope`), which absorbs them and supplies its palette style.
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
    // Each modifier is a contribution site. Give its base a structural child
    // edge so repeated modifiers on the same chain have distinct identities
    // without deriving identity from labels or mutable preference cardinality.
    var node = content.resolve(in: context.child(component: .named("PaletteCommandContent")))
    let intake = HandlerDescriptorIntake(
      context: context,
      preferringSnapshot: authoringContext
    )
    let contribution = ActivePaletteCommand(
      identity: context.identity,
      name: name,
      description: description,
      isEnabled: isEnabled,
      action: intake.wrappingSendable(action)
    )
    node.preferenceValues.merge(
      PaletteCommandsPreferenceKey.self,
      value: [contribution]
    )
    return [node]
  }
}
