import SwiftTUICore

private enum SubmitActionKey: EnvironmentKey {
  static let defaultValue: SubmitAction? = nil
}

extension EnvironmentValues {
  package var submitAction: SubmitAction? {
    get { self[SubmitActionKey.self] }
    set { self[SubmitActionKey.self] = newValue }
  }
}

extension View {
  /// Adds an action to perform when the user submits a value from a text
  /// input inside this view.
  ///
  /// Pressing Return in a focused `TextField` or `SecureField` runs the
  /// action; a `TextEditor` inserts a newline instead and never submits.
  /// Every enclosing `onSubmit` action runs, innermost first, unless a
  /// `submitScope(_:)` boundary stops submissions from propagating further
  /// up. When no `onSubmit` action encloses a field, Return keeps its
  /// default routing.
  @MainActor
  public func onSubmit(
    _ action: @escaping @MainActor @Sendable () -> Void
  ) -> ModifiedContent<Self, SubmitActionModifier> {
    modifier(
      SubmitActionModifier(
        authoringContext: currentImperativeAuthoringContextSnapshot(),
        action: action
      )
    )
  }

  /// Prevents text-input submissions inside this view from reaching
  /// `onSubmit` actions declared above it.
  @MainActor
  public func submitScope(
    _ isBlocking: Bool = true
  ) -> ModifiedContent<Self, SubmitScopeModifier> {
    modifier(SubmitScopeModifier(isBlocking: isBlocking))
  }
}

public struct SubmitActionModifier: PrimitiveViewModifier, Sendable {
  package let authoringContext: ImperativeAuthoringContextSnapshot?
  package let action: @MainActor @Sendable () -> Void

  package init(
    authoringContext: ImperativeAuthoringContextSnapshot?,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.authoringContext = authoringContext
    self.action = action
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let composed = SubmitAction(
      authoringContext: authoringContext,
      action: action,
      inherited: context.environmentValues.submitAction
    )
    return content.resolveElements(
      in: context.settingEnvironment(\.submitAction, to: composed)
    )
  }
}

public struct SubmitScopeModifier: PrimitiveViewModifier, Sendable, Equatable {
  package let isBlocking: Bool

  package init(isBlocking: Bool) {
    self.isBlocking = isBlocking
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    guard isBlocking else {
      return content.resolveElements(in: context)
    }
    return content.resolveElements(
      in: context.settingEnvironment(\.submitAction, to: nil)
    )
  }
}
