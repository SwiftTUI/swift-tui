public import SwiftTUICore

/// A focusable control that triggers an action when activated.
public struct Button<Label: View>: View, ResolvableView {
  public var role: ButtonRole?
  package var systemHintText: String?
  private var action: (@MainActor @Sendable () -> Void)?
  private var label: Label
  private let authoringScope: AuthoringContext?

  public init(
    _ title: String,
    role: ButtonRole? = nil
  ) where Label == Text {
    self.role = role
    action = nil
    label = Text(title)
    authoringScope = currentAuthoringContext()
  }

  public init(
    role: ButtonRole? = nil,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    action = nil
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  public init(
    _ title: String,
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void
  ) where Label == Text {
    self.role = role
    self.action = action
    label = Text(title)
    authoringScope = currentAuthoringContext()
  }

  public init(
    role: ButtonRole? = nil,
    action: @escaping @MainActor @Sendable () -> Void,
    @ViewBuilder label: () -> Label
  ) {
    self.role = role
    self.action = action
    self.label = label()
    authoringScope = currentAuthoringContext()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    [resolvedNode(in: context)]
  }

  package func resolve(
    in context: ResolveContext
  ) -> ResolvedNode {
    resolvedNode(in: context)
  }

  /// Attaches a muted, right-aligned shortcut hint that renders inside
  /// the button's label area (so the active control chrome — focus
  /// highlight, press state, role coloring — covers it consistently).
  ///
  /// The hint uses `Spacer(minLength: 1)` between the label and the
  /// hint text: when the row provides extra width (e.g. a menu row that
  /// has been width-equalized), the spacer expands and the hint rests
  /// against the trailing edge; when the row is intrinsically sized
  /// (e.g. a toolbar item), the spacer collapses to a single-cell gap
  /// and the hint sits flush after the label.
  ///
  /// A `nil`, empty, or whitespace-only hint suppresses the suffix
  /// entirely — the button renders exactly as it would without the
  /// modifier (no ghost spacer or trailing whitespace).
  public func systemHint(_ hint: String?) -> Button {
    var copy = self
    copy.systemHintText = Self.normalizeSystemHint(hint)
    return copy
  }

  package static func normalizeSystemHint(_ hint: String?) -> String? {
    guard let hint else { return nil }
    // Stdlib-only trim to avoid pulling Foundation into the Controls
    // module just for `trimmingCharacters(in:)`.
    let lead = hint.drop(while: { $0.isWhitespace })
    var trailingEnd = lead.endIndex
    while trailingEnd > lead.startIndex {
      let prior = lead.index(before: trailingEnd)
      if !lead[prior].isWhitespace { break }
      trailingEnd = prior
    }
    let trimmed = String(lead[lead.startIndex..<trailingEnd])
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Button {
  private func resolvedNode(
    in context: ResolveContext
  ) -> ResolvedNode {
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let isFocused = context.environmentValues.focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    let isPressed = context.environmentValues.pressedIdentity == context.identity
    let buttonStyle = context.environmentValues.buttonStyle

    if context.environmentValues.isEnabled, let action {
      let dynamicPropertyScope = currentAuthoringContext() ?? authoringScope
      context.localActionRegistry?.register(
        identity: context.identity,
        handler: {
          return withAuthoringContext(dynamicPropertyScope) {
            action()
            return true
          }
        },
        followUpInvalidationIdentity: dynamicPropertyScope?.viewIdentity
      )
    }

    let effectiveProminence = buttonStyle.resolvedProminence(
      base: context.environmentValues.controlProminence
    )
    let resolvedHint = systemHintText
    let originalLabel = label
    let configuration = ButtonStyleConfiguration(
      label: .init(authoringContext: authoringScope) {
        if let hint = resolvedHint {
          HStack(spacing: 0) {
            originalLabel
            Spacer(minLength: 1)
            Text(hint).foregroundStyle(.muted)
          }
        } else {
          originalLabel
        }
      },
      role: role,
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused,
      showsFocusEffect: showsFocusEffect,
      isPressed: isPressed,
      controlProminence: effectiveProminence,
      buttonBorderShape: context.environmentValues.buttonBorderShape,
      styleEnvironment: styleEnvironment
    )
    let child = buttonStyle.resolveBody(
      configuration: configuration,
      in: context.child(component: .named("ButtonBody"))
    )

    return ResolvedNode(
      identity: context.identity,
      kind: .view("Button"),
      children: [child],
      environmentSnapshot: context.environment,
      transactionSnapshot: context.transaction,
      semanticMetadata: focusableControlMetadata(
        focusInteractions: .activate,
        presentationRole: .button
      )
    )
  }
}
