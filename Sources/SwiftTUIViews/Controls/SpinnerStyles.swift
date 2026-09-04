public import SwiftTUICore

/// An extensible spinner style.
///
/// A spinner style resolves a ``SpinnerStylePresentation`` — glyph frames,
/// cadence, and paint — from the spinner's render state. The `Spinner`
/// primitive owns its animation task, iteration state, cancellation
/// identity, stage semantics, and reduced-motion behavior; a style cannot
/// change them.
public protocol SpinnerStyle: Sendable {
  var snapshotLabel: String { get }

  @MainActor
  func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation
}

extension SpinnerStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a spinner style may consult.
public struct SpinnerStyleConfiguration: Sendable {
  public var stage: Spinner.Stage
  public var accessibilityReduceMotion: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// The framework's construction path, exposed to test targets through
  /// `@_spi(StyleFixtures)` so a style resolves against a fixture without a
  /// live render (see <doc:Testing-Styles>).
  @_spi(StyleFixtures)
  public init(
    stage: Spinner.Stage,
    accessibilityReduceMotion: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.stage = stage
    self.accessibilityReduceMotion = accessibilityReduceMotion
    self.styleEnvironment = styleEnvironment
  }
}

/// Resolved spinner rendering data.
///
/// All frames of one `activeFrames` sequence must share a single
/// terminal-cell width so the animation cannot change layout between ticks;
/// the inactive and finished frames may differ from that width, because a
/// stage change is an ordinary re-layout. An invalid presentation — empty
/// frames, a non-positive interval, mixed active-frame widths — emits a
/// `style.invalidPresentation` runtime issue and the automatic presentation
/// renders for that resolve.
public struct SpinnerStylePresentation: Sendable, Equatable {
  public var activeFrames: [String]
  public var inactiveFrame: String
  public var finishedFrame: String
  public var interval: Duration
  /// Glyph paint. `nil` inherits the ambient foreground style.
  public var foregroundStyle: AnyShapeStyle?

  public init(
    activeFrames: [String],
    inactiveFrame: String = " ",
    finishedFrame: String = " ",
    interval: Duration = .milliseconds(64),
    foregroundStyle: AnyShapeStyle? = nil
  ) {
    self.activeFrames = activeFrames
    self.inactiveFrame = inactiveFrame
    self.finishedFrame = finishedFrame
    self.interval = interval
    self.foregroundStyle = foregroundStyle
  }
}

/// A spinner style described entirely by its glyph frames and cadence.
///
/// Every built-in spinner style is a `GlyphSpinnerStyle` value with a
/// distinctive `snapshotLabel`; custom application styles use the public
/// initializer, whose label defaults to type reflection.
public struct GlyphSpinnerStyle: SpinnerStyle, Equatable, Sendable {
  public var activeFrames: [String]
  public var inactiveFrame: String
  public var finishedFrame: String
  public var interval: Duration
  public var foregroundStyle: AnyShapeStyle?
  public var snapshotLabel: String

  public init(
    activeFrames: [String],
    inactiveFrame: String = " ",
    finishedFrame: String = " ",
    interval: Duration = .milliseconds(64),
    foregroundStyle: AnyShapeStyle? = nil,
    snapshotLabel: String = String(reflecting: GlyphSpinnerStyle.self)
  ) {
    self.activeFrames = activeFrames
    self.inactiveFrame = inactiveFrame
    self.finishedFrame = finishedFrame
    self.interval = interval
    self.foregroundStyle = foregroundStyle
    self.snapshotLabel = snapshotLabel
  }

  @MainActor
  public func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation {
    SpinnerStylePresentation(
      activeFrames: activeFrames,
      inactiveFrame: inactiveFrame,
      finishedFrame: finishedFrame,
      interval: interval,
      foregroundStyle: foregroundStyle
    )
  }
}

private protocol AnySpinnerStyleBox: Sendable {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: SpinnerStyleConfiguration) -> SpinnerStylePresentation
  func isEqualForReuse(to other: any AnySpinnerStyleBox) -> Bool
}

private struct ConcreteSpinnerStyleBox<S: SpinnerStyle>: AnySpinnerStyleBox {
  let style: S

  var snapshotLabel: String {
    style.snapshotLabel
  }

  var debugDescription: String {
    String(reflecting: style)
  }

  @MainActor
  func presentation(for configuration: SpinnerStyleConfiguration) -> SpinnerStylePresentation {
    style.resolvePresentation(for: configuration)
  }

  func isEqualForReuse(to other: any AnySpinnerStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return styleValuesAreEqualForReuse(style, other.style)
  }
}

/// A type-erased spinner style.
public struct AnySpinnerStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnySpinnerStyleBox

  public init<S: SpinnerStyle>(
    _ style: S
  ) {
    box = ConcreteSpinnerStyleBox(style: style)
  }

  public var description: String {
    box.snapshotLabel
  }

  public var debugDescription: String {
    box.debugDescription
  }

  @MainActor
  package func presentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation {
    box.presentation(for: configuration)
  }
}

extension AnySpinnerStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The former `Spinner.SpinnerSet` catalog, one built-in per retained
/// treatment. Frame sequences, head/tail glyphs, and cadences are preserved
/// from the removed set vocabulary; `.automatic` renders the braille loop
/// at 64 ms with inherited foreground.
extension GlyphSpinnerStyle {
  static func builtin(
    _ name: String,
    _ activeFrames: [String],
    inactive: String = " ",
    finished: String = " ",
    interval: Duration = .milliseconds(64)
  ) -> GlyphSpinnerStyle {
    GlyphSpinnerStyle(
      activeFrames: activeFrames,
      inactiveFrame: inactive,
      finishedFrame: finished,
      interval: interval,
      snapshotLabel: "SpinnerStyle.\(name)"
    )
  }
}

extension SpinnerStyle where Self == GlyphSpinnerStyle {
  /// The default spinner: the braille loop at 64 ms, inherited foreground.
  public static var automatic: GlyphSpinnerStyle {
    .builtin("automatic", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
  }

  public static var circleOrbit: GlyphSpinnerStyle {
    .builtin("circleOrbit", ["◡", "◟", "◜", "◠", "◝", "◞"], finished: "○")
  }

  public static var brailleRingFilled: GlyphSpinnerStyle {
    .builtin(
      "brailleRingFilled", ["⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻"], finished: "⣿")
  }

  public static var brailleBlockFill: GlyphSpinnerStyle {
    .builtin("brailleBlockFill", ["⠉", "⠛", "⠿", "⣿"], finished: "⣿")
  }

  public static var barRise: GlyphSpinnerStyle {
    .builtin("barRise", ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"], finished: "█")
  }

  public static var circleFill: GlyphSpinnerStyle {
    .builtin("circleFill", ["○", "◔", "◑", "◕", "●"], finished: "●")
  }

  public static var brailleSweep: GlyphSpinnerStyle {
    .builtin("brailleSweep", ["⠉", "⠘", "⠰", "⢠", "⣀", "⡄", "⠆", "⠃"])
  }

  public static var diamondPulse: GlyphSpinnerStyle {
    .builtin("diamondPulse", ["◇", "◈", "◆", "◈"], finished: "◆")
  }

  public static var brailleDotOrbit: GlyphSpinnerStyle {
    .builtin("brailleDotOrbit", ["⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂"])
  }

  public static var brailleLoopFilled: GlyphSpinnerStyle {
    .builtin(
      "brailleLoopFilled", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], finished: "⣶")
  }

  public static var quadrantOrbit: GlyphSpinnerStyle {
    .builtin("quadrantOrbit", ["▖", "▘", "▝", "▗"])
  }

  public static var clockFace: GlyphSpinnerStyle {
    .builtin("clockFace", ["◷", "◶", "◵", "◴"])
  }

  public static var halfCircle: GlyphSpinnerStyle {
    .builtin("halfCircle", ["◓", "◑", "◒", "◐"])
  }

  public static var triangleCompass: GlyphSpinnerStyle {
    .builtin("triangleCompass", ["▲", "▶", "▼", "◀"])
  }

  public static var brailleRamp: GlyphSpinnerStyle {
    .builtin("brailleRamp", ["⣀", "⣤", "⣶", "⣾", "⣿", "⣾", "⣶", "⣤"], finished: "⣿")
  }

  public static var brailleLinePulse: GlyphSpinnerStyle {
    .builtin("brailleLinePulse", ["⠉", "⠒", "⣀", "⠒"])
  }

  public static var diceRoll: GlyphSpinnerStyle {
    .builtin("diceRoll", ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"])
  }

  public static var boxCornerOrbit: GlyphSpinnerStyle {
    .builtin("boxCornerOrbit", ["┌", "┐", "┘", "└"])
  }

  public static var brailleDotFade: GlyphSpinnerStyle {
    .builtin("brailleDotFade", ["⠈", "⠐", "⠠", "⠄", "⠂", "⠁"])
  }

  public static var brailleLineSweep: GlyphSpinnerStyle {
    .builtin("brailleLineSweep", ["⠘", "⠰", "⠤", "⠆", "⠃", "⠉"])
  }

  public static var brailleRing: GlyphSpinnerStyle {
    .builtin("brailleRing", ["⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻"])
  }

  public static var arcOrbit: GlyphSpinnerStyle {
    .builtin("arcOrbit", ["◜", "◝", "◞", "◟"])
  }

  public static var brailleLoop: GlyphSpinnerStyle {
    .builtin("brailleLoop", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
  }

  public static var shadeFade: GlyphSpinnerStyle {
    .builtin("shadeFade", ["█", "▓", "▒", "░"], finished: "█")
  }

  public static var dotChase: GlyphSpinnerStyle {
    .builtin("dotChase", ["∙∙∙", "●∙∙", "∙●∙", "∙∙●"], finished: "●●●")
  }

  public static var globe: GlyphSpinnerStyle {
    .builtin("globe", ["🌍", "🌎", "🌏"])
  }

  public static var moonPhase: GlyphSpinnerStyle {
    .builtin("moonPhase", ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"], finished: "🌕")
  }

  public static var segmentedBar: GlyphSpinnerStyle {
    .builtin(
      "segmentedBar", ["▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱", "▱▱▱"], finished: "▰▰▰")
  }

  public static var arrowCompass: GlyphSpinnerStyle {
    .builtin("arrowCompass", ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"])
  }

  public static var glyphPulse: GlyphSpinnerStyle {
    .builtin("glyphPulse", ["ᔐ", "ᯇ", "ᔑ", "ᯇ"], finished: "ᦟ")
  }

  public static var blockCorners: GlyphSpinnerStyle {
    .builtin("blockCorners", ["▙", "▛", "▜", "▟"], finished: "█")
  }

  public static var horizontalBarFill: GlyphSpinnerStyle {
    .builtin("horizontalBarFill", ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"], finished: "█")
  }

  public static var quadrantCorners: GlyphSpinnerStyle {
    .builtin("quadrantCorners", ["▝", "▗", "▖", "▘"], finished: "█")
  }

  public static var verticalBarFill: GlyphSpinnerStyle {
    .builtin("verticalBarFill", ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"], finished: "█")
  }

  public static var heavyArrowCompass: GlyphSpinnerStyle {
    .builtin("heavyArrowCompass", ["⇑", "⇗", "⇒", "⇘", "⇓", "⇙", "⇐", "⇖"])
  }

  public static var lineCompass: GlyphSpinnerStyle {
    .builtin("lineCompass", ["│", "╱", "─", "╲"], finished: "┼")
  }

  /// Compact 4-glyph cycle used by Claude Code's terminal "working" header:
  /// asterisk, middle dot, plus, division sign, at the gallery's 240 ms
  /// cadence.
  public static var asteriskCycle: GlyphSpinnerStyle {
    .builtin("asteriskCycle", ["*", "·", "+", "÷"], interval: .milliseconds(240))
  }

  public static var oghamPulse: GlyphSpinnerStyle {
    .builtin(
      "oghamPulse",
      [
        " ", "ᚁ", "ᚂ", "ᚃ", "ᚄ", "ᚅ", "ᚄ", "ᚃ", "ᚂ", "ᚁ", " ", "ᚆ", "ᚇ", "ᚈ", "ᚉ", "ᚊ", "ᚉ",
        "ᚈ", "ᚇ", "ᚆ",
      ],
      finished: "ᚔ")
  }
}

extension AnySpinnerStyle {
  public static var automatic: Self { Self(.automatic) }
  public static var circleOrbit: Self { Self(.circleOrbit) }
  public static var brailleRingFilled: Self { Self(.brailleRingFilled) }
  public static var brailleBlockFill: Self { Self(.brailleBlockFill) }
  public static var barRise: Self { Self(.barRise) }
  public static var circleFill: Self { Self(.circleFill) }
  public static var brailleSweep: Self { Self(.brailleSweep) }
  public static var diamondPulse: Self { Self(.diamondPulse) }
  public static var brailleDotOrbit: Self { Self(.brailleDotOrbit) }
  public static var brailleLoopFilled: Self { Self(.brailleLoopFilled) }
  public static var quadrantOrbit: Self { Self(.quadrantOrbit) }
  public static var clockFace: Self { Self(.clockFace) }
  public static var halfCircle: Self { Self(.halfCircle) }
  public static var triangleCompass: Self { Self(.triangleCompass) }
  public static var brailleRamp: Self { Self(.brailleRamp) }
  public static var brailleLinePulse: Self { Self(.brailleLinePulse) }
  public static var diceRoll: Self { Self(.diceRoll) }
  public static var boxCornerOrbit: Self { Self(.boxCornerOrbit) }
  public static var brailleDotFade: Self { Self(.brailleDotFade) }
  public static var brailleLineSweep: Self { Self(.brailleLineSweep) }
  public static var brailleRing: Self { Self(.brailleRing) }
  public static var arcOrbit: Self { Self(.arcOrbit) }
  public static var brailleLoop: Self { Self(.brailleLoop) }
  public static var shadeFade: Self { Self(.shadeFade) }
  public static var dotChase: Self { Self(.dotChase) }
  public static var globe: Self { Self(.globe) }
  public static var moonPhase: Self { Self(.moonPhase) }
  public static var segmentedBar: Self { Self(.segmentedBar) }
  public static var arrowCompass: Self { Self(.arrowCompass) }
  public static var glyphPulse: Self { Self(.glyphPulse) }
  public static var blockCorners: Self { Self(.blockCorners) }
  public static var horizontalBarFill: Self { Self(.horizontalBarFill) }
  public static var quadrantCorners: Self { Self(.quadrantCorners) }
  public static var verticalBarFill: Self { Self(.verticalBarFill) }
  public static var heavyArrowCompass: Self { Self(.heavyArrowCompass) }
  public static var lineCompass: Self { Self(.lineCompass) }
  public static var asteriskCycle: Self { Self(.asteriskCycle) }
  public static var oghamPulse: Self { Self(.oghamPulse) }
}
