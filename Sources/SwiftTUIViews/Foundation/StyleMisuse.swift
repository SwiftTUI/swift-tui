import SwiftTUICore

// The shared misuse rule for style-facing contracts: misuse never traps and is
// never silent.
//
// A style can hand the framework an invalid presentation value — empty spinner
// frames, a non-positive cadence, a multi-cell indicator glyph. The resolving
// surface validates what it received; on any problem it emits one
// `style.invalidPresentation` runtime issue and renders the family's automatic
// presentation for that resolve. Nothing traps on a style-supplied value, and
// no invalid value reaches layout, where it could corrupt realized bounds.
//
// This is the channel only. Each family owns its validation predicate and its
// automatic fallback; consumers merge the issue into their node's
// `RuntimeIssuePreferenceKey` preferences (the `image.unresolvedSource`
// idiom) or an equivalent resolve-time route.

/// Constructs and routes the runtime issues shared by every style family's
/// presentation validation.
enum StyleMisuse {
  /// The one issue code every invalid-presentation emission uses. The family
  /// and the offending style are named in the message, not the code, so
  /// issue-code filtering stays stable as families are added.
  static let invalidPresentationCode = "style.invalidPresentation"

  /// Returns `presentation` unchanged when `problems` is empty; otherwise
  /// reports one issue describing every problem and returns `fallback()` —
  /// the family's automatic presentation — for this resolve.
  static func validatedPresentation<Presentation>(
    _ presentation: Presentation,
    problems: [String],
    family: String,
    styleLabel: String,
    identity: Identity?,
    report: (RuntimeIssue) -> Void,
    fallback: () -> Presentation
  ) -> Presentation {
    guard !problems.isEmpty else {
      return presentation
    }
    report(
      invalidPresentationIssue(
        family: family,
        styleLabel: styleLabel,
        problems: problems,
        identity: identity
      )
    )
    return fallback()
  }

  /// One warning naming what the style resolved, what the runtime rendered
  /// instead, and where to fix it.
  static func invalidPresentationIssue(
    family: String,
    styleLabel: String,
    problems: [String],
    identity: Identity?
  ) -> RuntimeIssue {
    RuntimeIssue(
      severity: .warning,
      code: invalidPresentationCode,
      message:
        "\(family) \(styleLabel) resolved an invalid presentation: "
        + problems.joined(separator: "; ")
        + ". The automatic presentation was rendered for this resolve. "
        + "Return valid values from the style's resolvePresentation(for:).",
      identity: identity,
      source: family
    )
  }
}
