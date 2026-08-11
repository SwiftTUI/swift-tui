public import SwiftTUICore

// Ambient text-layout attributes.
//
// `View.lineLimit(_:)`, `.truncationMode(_:)`, and `.textWrappingStrategy(_:)`
// are plain environment writes (innermost write wins; `lineLimit(nil)`
// clears), matching SwiftUI's ambient-propagation contract. Text-run-producing
// leaves stamp the effective values into their node's `LayoutMetadata` at
// resolve time, because the fused frame tail cannot read the environment —
// measurement, draw extraction, and semantics all consume the stamped
// metadata.

private enum LineLimitKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

private enum TruncationModeKey: EnvironmentKey {
  static let defaultValue = Text.TruncationMode.tail
}

private enum TextWrappingStrategyKey: EnvironmentKey {
  static let defaultValue = Text.WrappingStrategy.wordBoundary
}

private enum UnderlineStyleKey: EnvironmentKey {
  static let defaultValue: TextLineStyle? = nil
}

private enum StrikethroughStyleKey: EnvironmentKey {
  static let defaultValue: TextLineStyle? = nil
}

extension EnvironmentValues {
  /// The maximum number of lines descendant text runs may occupy, or `nil`
  /// for no limit.
  ///
  /// Matching SwiftUI, the environment carries the authored value verbatim:
  /// non-positive limits are clamped to one line where text is laid out, not
  /// at the write site.
  public var lineLimit: Int? {
    get { self[LineLimitKey.self] }
    set { self[LineLimitKey.self] = newValue }
  }

  /// How descendant text runs shorten an overflowing last line.
  public var truncationMode: Text.TruncationMode {
    get { self[TruncationModeKey.self] }
    set { self[TruncationModeKey.self] = newValue }
  }

  /// How descendant text runs wrap when they exceed the available width.
  public var textWrappingStrategy: Text.WrappingStrategy {
    get { self[TextWrappingStrategyKey.self] }
    set { self[TextWrappingStrategyKey.self] = newValue }
  }

  /// The inherited underline written by `View.underline(_:pattern:color:)`.
  /// Node-over-environment precedence: a `Text` that styles its own
  /// underline — including an explicit `.underline(false)` clear — wins over
  /// this value. SwiftUI exposes no public reader for this, so the key stays
  /// package-level.
  package var underlineStyle: TextLineStyle? {
    get { self[UnderlineStyleKey.self] }
    set { self[UnderlineStyleKey.self] = newValue }
  }

  /// The strikethrough counterpart of ``underlineStyle``.
  package var strikethroughStyle: TextLineStyle? {
    get { self[StrikethroughStyleKey.self] }
    set { self[StrikethroughStyleKey.self] = newValue }
  }
}

/// The ambient text decorations a `Text` leaf stamps where its own value
/// styling left them unset (untracked reads; see ``ambientTextLayoutMetadata``).
@MainActor
package func ambientTextDecorations(
  in context: ResolveContext
) -> (underline: TextLineStyle?, strikethrough: TextLineStyle?) {
  let environment = context.environmentValues
  return (
    underline: environment[untracked: UnderlineStyleKey.self],
    strikethrough: environment[untracked: StrikethroughStyleKey.self]
  )
}

/// The effective ambient text-layout attributes, stamped as node metadata so
/// the environment-blind frame tail can consume them.
///
/// Reads are untracked (see the `untracked` subscript): a changed value
/// re-resolves the writer's subtree through snapshot inequality, and tracked
/// reads would stamp framework noise into every text node's dependency set.
@MainActor
package func ambientTextLayoutMetadata(
  in context: ResolveContext
) -> LayoutMetadata {
  let environment = context.environmentValues
  return LayoutMetadata(
    lineLimit: environment[untracked: LineLimitKey.self].map { max(1, $0) },
    textTruncationMode: environment[untracked: TruncationModeKey.self],
    textWrappingStrategy: environment[untracked: TextWrappingStrategyKey.self]
  )
}

extension View {
  /// Restores the default text-layout attributes for this subtree. Views that
  /// perform their own text layout (`TextEditor`'s movement map wraps
  /// independently of the environment) opt out of ambient inheritance here.
  package func ambientTextAttributesReset() -> some View {
    transformEnvironment(\.self) { environment in
      environment.lineLimit = nil
      environment.truncationMode = .tail
      environment.textWrappingStrategy = .wordBoundary
    }
  }
}
