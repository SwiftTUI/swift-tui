import SwiftTUICore

/// How a ``Text`` view's content changes when its string changes inside an
/// animated transaction.
///
/// Set one with ``View/contentTransition(_:)``; it flows through the
/// environment (``EnvironmentValues/contentTransition``) to every `Text` it
/// encloses, including `Label` and `Button` titles. A content transition
/// plays only when the text changes inside an animated transaction
/// (``withAnimation(_:_:)``, ``View/animation(_:value:)``); an unanimated
/// change cuts, as does reduce motion.
///
/// On the cell grid a rolling digit is a counter: each changed digit column
/// steps through the intermediate digits toward its target over the
/// animation's curve and dims at the midpoint, other changed columns
/// cross-fade, and a change in length lays out at the new width at once.
/// SwiftUI's `.interpolate` has no cell-grid reading and is not offered.
public struct ContentTransition: Hashable, Sendable {
  package enum Storage: Hashable, Sendable {
    case identity
    case opacity
    case numericText(countsDown: Bool)
    case numericTextValue(Double)
  }

  package var storage: Storage

  package init(storage: Storage) {
    self.storage = storage
  }

  /// The text cuts to its new string.
  public static let identity = ContentTransition(storage: .identity)

  /// The old string dims out to the midpoint of the animation, then the new
  /// string dims in.
  public static let opacity = ContentTransition(storage: .opacity)

  /// Changed digit columns count toward their new digit; other changed
  /// columns cross-fade.
  ///
  /// - Parameter countsDown: roll each changed digit downward
  ///   (`3 → 2 → 1 → 0`) instead of upward.
  public static func numericText(countsDown: Bool = false) -> ContentTransition {
    ContentTransition(storage: .numericText(countsDown: countsDown))
  }

  /// ``numericText(countsDown:)`` with the direction taken from the sign of
  /// the change in `value` between the old and the new text.
  public static func numericText(value: Double) -> ContentTransition {
    ContentTransition(storage: .numericTextValue(value))
  }

  /// The draw-layer model a `Text` stamps on its node, or `nil` for
  /// ``identity``.
  package var textContentTransition: TextContentTransition? {
    switch storage {
    case .identity:
      nil
    case .opacity:
      TextContentTransition(kind: .opacity)
    case .numericText(let countsDown):
      TextContentTransition(kind: .numericText, countsDown: countsDown)
    case .numericTextValue(let value):
      TextContentTransition(kind: .numericText, value: value)
    }
  }
}

private enum ContentTransitionKey: EnvironmentKey {
  static let defaultValue = ContentTransition.identity
}

extension EnvironmentValues {
  /// The content transition ``Text`` views in this environment play when
  /// their string changes inside an animated transaction. Defaults to
  /// ``ContentTransition/identity``.
  public var contentTransition: ContentTransition {
    get { self[ContentTransitionKey.self] }
    set { self[ContentTransitionKey.self] = newValue }
  }
}

/// The content transition a `Text` leaf stamps on its node at resolve.
///
/// An untracked read, like the ambient text attributes
/// (`ambientTextLayoutMetadata`): a changed value re-resolves the writer's
/// subtree through snapshot inequality, and a tracked read would stamp
/// framework noise into every text node's dependency set.
@MainActor
package func ambientContentTransition(
  in context: ResolveContext
) -> TextContentTransition? {
  context.environmentValues[untracked: ContentTransitionKey.self].textContentTransition
}

extension View {
  /// Sets the ``ContentTransition`` the ``Text`` views inside this view play
  /// when their string changes inside an animated transaction.
  ///
  /// ```swift
  /// Text("\(count)")
  ///   .contentTransition(.numericText())
  /// Button("Count") {
  ///   withAnimation(.easeInOut(duration: .milliseconds(600))) { count += 1 }
  /// }
  /// ```
  public func contentTransition(_ transition: ContentTransition) -> some View {
    environment(\.contentTransition, transition)
  }
}
