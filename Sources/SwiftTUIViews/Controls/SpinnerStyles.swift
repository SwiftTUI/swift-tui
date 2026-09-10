public import SwiftTUICore

/// An extensible spinner style.
///
/// A spinner style resolves a ``SpinnerStylePresentation`` — glyph frames,
/// cadence, and paint — from the spinner's render state. The `Spinner`
/// primitive owns its animation task, iteration state, cancellation
/// identity, stage semantics, and reduced-motion behavior; a style cannot
/// change them.
///
/// This is a presentation-value family: a conformance implements
/// ``resolvePresentation(for:)`` and returns data, and the framework keeps the
/// composition because the cadence is the primitive's invariant. Apply a style
/// with `spinnerStyle(_:)`, which stores it in the environment for its
/// subtree; the nearest modifier wins, and a ``Spinner`` composed by another
/// style, such as ``CircularProgressViewStyle``, inherits it too.
///
/// The built-ins are ``GlyphSpinnerStyle`` values: `.automatic`, the braille
/// loop, and 37 further glyph presets. A custom sequence usually needs no
/// conformance at all, just a ``GlyphSpinnerStyle`` with your frames; conform
/// when the presentation depends on the configuration.
///
/// An invalid presentation, meaning empty active frames, a non-positive
/// interval, or active frames of mixed cell width, reports
/// `style.invalidPresentation` and renders the automatic presentation instead.
/// The spinner reports once per invalid style value per spinner, not once per
/// animated frame, and reports again when the style value changes.
///
/// A conformance is a `Sendable` value type; a class cannot conform.
///
/// ```swift
/// struct DotsSpinnerStyle: SpinnerStyle {
///   func resolvePresentation(
///     for configuration: SpinnerStyleConfiguration
///   ) -> SpinnerStylePresentation {
///     SpinnerStylePresentation(
///       activeFrames: ["•  ", " • ", "  •"],
///       interval: .milliseconds(120)
///     )
///   }
/// }
///
/// Spinner().spinnerStyle(DotsSpinnerStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol SpinnerStyle: Sendable {
  /// The label this style reports in snapshots, debug bundles, and style
  /// runtime issues.
  ///
  /// The default implementation reflects the conforming type's name; the
  /// presets pin their own, such as `"SpinnerStyle.dotChase"`. It is
  /// diagnostic text, not identity: do not branch on it.
  var snapshotLabel: String { get }

  /// Resolves the frames, cadence, and paint the spinner renders.
  ///
  /// Runs on the main actor for every resolve of the spinner, including each
  /// animation tick, so it should be cheap and free of side effects.
  ///
  /// - Parameter configuration: The spinner's stage, the reduced-motion
  ///   policy, and the style environment.
  /// - Returns: The presentation to render. An invalid one reports
  ///   `style.invalidPresentation` and the automatic presentation renders in
  ///   its place.
  @MainActor
  func resolvePresentation(
    for configuration: SpinnerStyleConfiguration
  ) -> SpinnerStylePresentation
}

extension SpinnerStyle {
  /// The reflected name of the conforming type, used unless the style pins a
  /// label of its own.
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

/// The render state a spinner style may consult.
///
/// Everything here is read-only: the spinner's stage, the rendering policy for
/// motion, and the ambient style environment. A spinner has no focus stop, no
/// binding, and no routes.
public struct SpinnerStyleConfiguration: Sendable {
  /// Which phase of work the spinner represents: `inactive`, `active`, or
  /// `finished`.
  ///
  /// It comes from the `Spinner(stage:)` declaration and decides which frame
  /// of the resolved presentation renders.
  public var stage: Spinner.Stage
  /// Whether motion is reduced for this resolve.
  ///
  /// It is `true` when the reduced-motion accessibility preference is set or
  /// when stable output is on, so a style sees the combined rendering policy
  /// rather than the accessibility preference alone. The primitive already
  /// collapses the animation to the first active frame and schedules no tick
  /// task under it, so a style need not branch on this flag, though it may
  /// return fewer frames or a different static glyph.
  public var accessibilityReduceMotion: Bool
  /// The `StyleEnvironmentSnapshot` for this resolve: the terminal
  /// appearance, the active theme, the ambient foreground and tint paints,
  /// the enabled state, and the cell metrics.
  ///
  /// Use it to derive ``SpinnerStylePresentation/foregroundStyle`` from the
  /// theme instead of hard-coding a color.
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
  /// The frames cycled while the spinner is active, one per tick, in order.
  ///
  /// Every frame must occupy the same number of terminal cells, and the list
  /// must not be empty. Under reduced motion or stable output only the first
  /// frame renders.
  public var activeFrames: [String]
  /// The frame rendered for the `inactive` stage, a single space by default.
  ///
  /// It may differ in cell width from the active frames, and it is not
  /// validated.
  public var inactiveFrame: String
  /// The frame rendered for the `finished` stage, a single space by default.
  ///
  /// It may differ in cell width from the active frames, and it is not
  /// validated. Presets that end on a filled glyph set it, for example `●`
  /// for the circle fill.
  public var finishedFrame: String
  /// The delay between active frames, 64 ms by default.
  ///
  /// It must be greater than zero. The primitive owns the clock, so the
  /// interval is the cadence request, not a guarantee about scheduling.
  public var interval: Duration
  /// Glyph paint. `nil` inherits the ambient foreground style.
  public var foregroundStyle: AnyShapeStyle?

  /// Creates a spinner presentation.
  ///
  /// - Parameters:
  ///   - activeFrames: The frames cycled while the spinner is active. They
  ///     must be non-empty and of one cell width.
  ///   - inactiveFrame: The frame for the `inactive` stage; a space by
  ///     default, which renders as a blank cell.
  ///   - finishedFrame: The frame for the `finished` stage; a space by
  ///     default.
  ///   - interval: The delay between active frames; 64 ms by default, and it
  ///     must be positive.
  ///   - foregroundStyle: The glyph paint, or `nil` to inherit the ambient
  ///     foreground style.
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
  /// The frames cycled while the spinner is active, one per tick, in order.
  public var activeFrames: [String]
  /// The frame rendered for the `inactive` stage.
  public var inactiveFrame: String
  /// The frame rendered for the `finished` stage.
  public var finishedFrame: String
  /// The delay between active frames.
  public var interval: Duration
  /// The glyph paint, or `nil` to inherit the ambient foreground style.
  public var foregroundStyle: AnyShapeStyle?
  /// The label reported in snapshots and diagnostics.
  ///
  /// Unlike the other style families this is a stored property, so two glyph
  /// styles can share a type and still be told apart in a snapshot.
  public var snapshotLabel: String

  /// Creates a glyph spinner style from a frame sequence.
  ///
  /// Two glyph styles with equal stored properties compare equal, which is how
  /// the reuse gate tells one preset from another when the environment value
  /// is replaced.
  ///
  /// - Parameters:
  ///   - activeFrames: The frames cycled while the spinner is active. They
  ///     must be non-empty and of one cell width, or the spinner reports
  ///     `style.invalidPresentation` and renders the automatic preset.
  ///   - inactiveFrame: The frame for the `inactive` stage; a space by
  ///     default.
  ///   - finishedFrame: The frame for the `finished` stage; a space by
  ///     default.
  ///   - interval: The delay between active frames; 64 ms by default, and it
  ///     must be positive.
  ///   - foregroundStyle: The glyph paint, or `nil` to inherit the ambient
  ///     foreground style.
  ///   - snapshotLabel: The diagnostic label. It defaults to this type's
  ///     reflected name, so every custom glyph style that does not pass one
  ///     reports the same label; pass a distinct string when a snapshot or a
  ///     runtime issue has to name the style.
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

  /// Returns this style's stored frames, cadence, and paint unchanged.
  ///
  /// The configuration is not consulted: stage, reduced motion, and the style
  /// environment leave the resolved value the same, and the primitive applies
  /// the stage and the motion policy to it.
  ///
  /// - Parameter configuration: The spinner's render state, unused here.
  /// - Returns: A presentation built from this style's stored properties.
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

private protocol AnySpinnerStyleBox: AnyStyleBox {
  var snapshotLabel: String { get }
  var debugDescription: String { get }

  @MainActor
  func presentation(for configuration: SpinnerStyleConfiguration) -> SpinnerStylePresentation
}

extension ConcreteStyleBox: AnySpinnerStyleBox where S: SpinnerStyle {

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

}

/// A type-erased spinner style, the value the environment carries.
public struct AnySpinnerStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  private let box: any AnySpinnerStyleBox

  /// Wraps a concrete spinner style for the environment.
  ///
  /// The generic `spinnerStyle(_:)` overload calls this for you.
  ///
  /// - Parameter style: The style to erase.
  public init<S: SpinnerStyle>(
    _ style: S
  ) {
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String {
    box.snapshotLabel
  }

  /// The wrapped style's `snapshotLabel`, the same text ``description``
  /// reports, so printing an erased preset never dumps its whole frame list.
  public var debugDescription: String {
    box.snapshotLabel
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

/// The built-in preset catalog: one `GlyphSpinnerStyle` value per retained
/// treatment, each pinning a `"SpinnerStyle.<name>"` snapshot label. Frames
/// run at 64 ms with inherited foreground unless the preset says otherwise.
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
  ///
  /// Ten frames, ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏, ending blank. The `brailleLoop` preset
  /// is the same sequence under a different label.
  public static var automatic: GlyphSpinnerStyle {
    .builtin("automatic", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
  }

  /// An arc travelling around a circle, ◡ ◟ ◜ ◠ ◝ ◞, finishing on ○.
  public static var circleOrbit: GlyphSpinnerStyle {
    .builtin("circleOrbit", ["◡", "◟", "◜", "◠", "◝", "◞"], finished: "○")
  }

  /// A gap orbiting a filled braille cell, ⣾ ⣷ ⣯ ⣟ ⡿ ⢿ ⣽ ⣻, finishing on the
  /// full cell ⣿.
  public static var brailleRingFilled: GlyphSpinnerStyle {
    .builtin(
      "brailleRingFilled", ["⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻"], finished: "⣿")
  }

  /// A braille cell filling from the top down, ⠉ ⠛ ⠿ ⣿, finishing full.
  public static var brailleBlockFill: GlyphSpinnerStyle {
    .builtin("brailleBlockFill", ["⠉", "⠛", "⠿", "⣿"], finished: "⣿")
  }

  /// A block bar growing in eight steps, ▁ ▂ ▃ ▄ ▅ ▆ ▇ █, finishing full.
  /// Identical to the `verticalBarFill` preset.
  public static var barRise: GlyphSpinnerStyle {
    .builtin("barRise", ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"], finished: "█")
  }

  /// A circle filling in five steps, ○ ◔ ◑ ◕ ●, finishing solid.
  public static var circleFill: GlyphSpinnerStyle {
    .builtin("circleFill", ["○", "◔", "◑", "◕", "●"], finished: "●")
  }

  /// A two-dot braille stroke sweeping around the cell, ⠉ ⠘ ⠰ ⢠ ⣀ ⡄ ⠆ ⠃,
  /// ending blank.
  public static var brailleSweep: GlyphSpinnerStyle {
    .builtin("brailleSweep", ["⠉", "⠘", "⠰", "⢠", "⣀", "⡄", "⠆", "⠃"])
  }

  /// A diamond pulsing hollow to solid and back, ◇ ◈ ◆ ◈, finishing on ◆.
  public static var diamondPulse: GlyphSpinnerStyle {
    .builtin("diamondPulse", ["◇", "◈", "◆", "◈"], finished: "◆")
  }

  /// A single braille dot orbiting the cell, ⠁ ⠈ ⠐ ⠠ ⢀ ⡀ ⠄ ⠂, ending blank.
  public static var brailleDotOrbit: GlyphSpinnerStyle {
    .builtin("brailleDotOrbit", ["⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂"])
  }

  /// The ten-frame braille loop ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏, finishing on the filled
  /// ⣶ instead of a blank.
  public static var brailleLoopFilled: GlyphSpinnerStyle {
    .builtin(
      "brailleLoopFilled", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"], finished: "⣶")
  }

  /// A quadrant block hopping clockwise from the lower left, ▖ ▘ ▝ ▗, ending
  /// blank.
  public static var quadrantOrbit: GlyphSpinnerStyle {
    .builtin("quadrantOrbit", ["▖", "▘", "▝", "▗"])
  }

  /// A filled quadrant turning counterclockwise, ◷ ◶ ◵ ◴, ending blank.
  public static var clockFace: GlyphSpinnerStyle {
    .builtin("clockFace", ["◷", "◶", "◵", "◴"])
  }

  /// A half-filled circle rotating, ◓ ◑ ◒ ◐, ending blank.
  public static var halfCircle: GlyphSpinnerStyle {
    .builtin("halfCircle", ["◓", "◑", "◒", "◐"])
  }

  /// A solid triangle pointing up, right, down, then left: ▲ ▶ ▼ ◀.
  public static var triangleCompass: GlyphSpinnerStyle {
    .builtin("triangleCompass", ["▲", "▶", "▼", "◀"])
  }

  /// A braille cell filling and emptying again, ⣀ ⣤ ⣶ ⣾ ⣿ ⣾ ⣶ ⣤, finishing
  /// full.
  public static var brailleRamp: GlyphSpinnerStyle {
    .builtin("brailleRamp", ["⣀", "⣤", "⣶", "⣾", "⣿", "⣾", "⣶", "⣤"], finished: "⣿")
  }

  /// A braille line moving top, middle, bottom, middle: ⠉ ⠒ ⣀ ⠒.
  public static var brailleLinePulse: GlyphSpinnerStyle {
    .builtin("brailleLinePulse", ["⠉", "⠒", "⣀", "⠒"])
  }

  /// The six die faces in order, ⚀ ⚁ ⚂ ⚃ ⚄ ⚅, ending blank.
  public static var diceRoll: GlyphSpinnerStyle {
    .builtin("diceRoll", ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"])
  }

  /// A box-drawing corner rotating clockwise, ┌ ┐ ┘ └, ending blank.
  public static var boxCornerOrbit: GlyphSpinnerStyle {
    .builtin("boxCornerOrbit", ["┌", "┐", "┘", "└"])
  }

  /// A single braille dot walking down the right column and back up the left,
  /// ⠈ ⠐ ⠠ ⠄ ⠂ ⠁, ending blank.
  public static var brailleDotFade: GlyphSpinnerStyle {
    .builtin("brailleDotFade", ["⠈", "⠐", "⠠", "⠄", "⠂", "⠁"])
  }

  /// A braille two-dot line rotating around the cell, ⠘ ⠰ ⠤ ⠆ ⠃ ⠉, ending
  /// blank.
  public static var brailleLineSweep: GlyphSpinnerStyle {
    .builtin("brailleLineSweep", ["⠘", "⠰", "⠤", "⠆", "⠃", "⠉"])
  }

  /// A gap orbiting a filled braille cell, ⣾ ⣷ ⣯ ⣟ ⡿ ⢿ ⣽ ⣻: the
  /// `brailleRingFilled` frames, ending blank rather than on ⣿.
  public static var brailleRing: GlyphSpinnerStyle {
    .builtin("brailleRing", ["⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣽", "⣻"])
  }

  /// A quarter arc rotating clockwise from the upper left, ◜ ◝ ◞ ◟, ending
  /// blank.
  public static var arcOrbit: GlyphSpinnerStyle {
    .builtin("arcOrbit", ["◜", "◝", "◞", "◟"])
  }

  /// The ten-frame braille loop ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏, the same sequence
  /// `automatic` renders, under its own label.
  public static var brailleLoop: GlyphSpinnerStyle {
    .builtin("brailleLoop", ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])
  }

  /// A block fading through the shade glyphs, █ ▓ ▒ ░, finishing solid.
  public static var shadeFade: GlyphSpinnerStyle {
    .builtin("shadeFade", ["█", "▓", "▒", "░"], finished: "█")
  }

  /// Three cells with one dot moving along them, `∙∙∙` `●∙∙` `∙●∙` `∙∙●`,
  /// finishing `●●●`.
  public static var dotChase: GlyphSpinnerStyle {
    .builtin("dotChase", ["∙∙∙", "●∙∙", "∙●∙", "∙∙●"], finished: "●●●")
  }

  /// The three globe emoji, 🌍 🌎 🌏, two cells wide, ending blank.
  public static var globe: GlyphSpinnerStyle {
    .builtin("globe", ["🌍", "🌎", "🌏"])
  }

  /// The eight moon phases, 🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘, two cells wide, finishing
  /// on the full moon.
  public static var moonPhase: GlyphSpinnerStyle {
    .builtin("moonPhase", ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"], finished: "🌕")
  }

  /// A three-segment bar filling then emptying, ▱▱▱ to ▰▰▰ and back,
  /// finishing full.
  public static var segmentedBar: GlyphSpinnerStyle {
    .builtin(
      "segmentedBar", ["▱▱▱", "▰▱▱", "▰▰▱", "▰▰▰", "▰▰▱", "▰▱▱", "▱▱▱"], finished: "▰▰▰")
  }

  /// A light arrow turning clockwise through the eight compass points from ←,
  /// ending blank.
  public static var arrowCompass: GlyphSpinnerStyle {
    .builtin("arrowCompass", ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"])
  }

  /// A decorative glyph pulsing between ᔐ and ᔑ through ᯇ, finishing on ᦟ.
  public static var glyphPulse: GlyphSpinnerStyle {
    .builtin("glyphPulse", ["ᔐ", "ᯇ", "ᔑ", "ᯇ"], finished: "ᦟ")
  }

  /// A three-quarter block rotating, ▙ ▛ ▜ ▟, finishing on the full block █.
  public static var blockCorners: GlyphSpinnerStyle {
    .builtin("blockCorners", ["▙", "▛", "▜", "▟"], finished: "█")
  }

  /// A cell filling left to right in eighths, ▏ ▎ ▍ ▌ ▋ ▊ ▉ █, finishing full.
  public static var horizontalBarFill: GlyphSpinnerStyle {
    .builtin("horizontalBarFill", ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"], finished: "█")
  }

  /// A quadrant block hopping clockwise from the upper right, ▝ ▗ ▖ ▘,
  /// finishing on the full block █.
  public static var quadrantCorners: GlyphSpinnerStyle {
    .builtin("quadrantCorners", ["▝", "▗", "▖", "▘"], finished: "█")
  }

  /// A block bar growing in eight steps, ▁ ▂ ▃ ▄ ▅ ▆ ▇ █, finishing full.
  /// Identical to the `barRise` preset.
  public static var verticalBarFill: GlyphSpinnerStyle {
    .builtin("verticalBarFill", ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"], finished: "█")
  }

  /// A double-stroke arrow turning clockwise through the eight compass points
  /// from ⇑, ending blank.
  public static var heavyArrowCompass: GlyphSpinnerStyle {
    .builtin("heavyArrowCompass", ["⇑", "⇗", "⇒", "⇘", "⇓", "⇙", "⇐", "⇖"])
  }

  /// A line rotating through │ ╱ ─ ╲, finishing on the crossing ┼.
  public static var lineCompass: GlyphSpinnerStyle {
    .builtin("lineCompass", ["│", "╱", "─", "╲"], finished: "┼")
  }

  /// A four-glyph cycle of asterisk, middle dot, plus, and division sign,
  /// * · + ÷, at a slower 240 ms cadence.
  public static var asteriskCycle: GlyphSpinnerStyle {
    .builtin("asteriskCycle", ["*", "·", "+", "÷"], interval: .milliseconds(240))
  }

  /// Twenty frames climbing and descending two ogham ladders, a blank then
  /// ᚁ up to ᚅ and back, a blank then ᚆ up to ᚊ and back, finishing on ᚔ.
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
  /// The erased default spinner: the braille loop ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏ at 64 ms.
  public static var automatic: Self { Self(.automatic) }
  /// The erased circle-orbit preset: an arc travelling around a circle,
  /// ◡ ◟ ◜ ◠ ◝ ◞, finishing on ○.
  public static var circleOrbit: Self { Self(.circleOrbit) }
  /// The erased filled braille ring: a gap orbiting a filled cell,
  /// ⣾ ⣷ ⣯ ⣟ ⡿ ⢿ ⣽ ⣻, finishing on ⣿.
  public static var brailleRingFilled: Self { Self(.brailleRingFilled) }
  /// The erased braille block fill: ⠉ ⠛ ⠿ ⣿, finishing full.
  public static var brailleBlockFill: Self { Self(.brailleBlockFill) }
  /// The erased bar rise: ▁ ▂ ▃ ▄ ▅ ▆ ▇ █, finishing full. Identical to
  /// `verticalBarFill`.
  public static var barRise: Self { Self(.barRise) }
  /// The erased circle fill: ○ ◔ ◑ ◕ ●, finishing solid.
  public static var circleFill: Self { Self(.circleFill) }
  /// The erased braille sweep: a two-dot stroke going around the cell,
  /// ⠉ ⠘ ⠰ ⢠ ⣀ ⡄ ⠆ ⠃.
  public static var brailleSweep: Self { Self(.brailleSweep) }
  /// The erased diamond pulse: ◇ ◈ ◆ ◈, finishing on ◆.
  public static var diamondPulse: Self { Self(.diamondPulse) }
  /// The erased braille dot orbit: one dot circling the cell,
  /// ⠁ ⠈ ⠐ ⠠ ⢀ ⡀ ⠄ ⠂.
  public static var brailleDotOrbit: Self { Self(.brailleDotOrbit) }
  /// The erased filled braille loop: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏, finishing on ⣶.
  public static var brailleLoopFilled: Self { Self(.brailleLoopFilled) }
  /// The erased quadrant orbit: a quadrant block hopping clockwise from the
  /// lower left, ▖ ▘ ▝ ▗.
  public static var quadrantOrbit: Self { Self(.quadrantOrbit) }
  /// The erased clock face: a filled quadrant turning counterclockwise,
  /// ◷ ◶ ◵ ◴.
  public static var clockFace: Self { Self(.clockFace) }
  /// The erased half circle: ◓ ◑ ◒ ◐.
  public static var halfCircle: Self { Self(.halfCircle) }
  /// The erased triangle compass: ▲ ▶ ▼ ◀.
  public static var triangleCompass: Self { Self(.triangleCompass) }
  /// The erased braille ramp: a cell filling and emptying,
  /// ⣀ ⣤ ⣶ ⣾ ⣿ ⣾ ⣶ ⣤, finishing full.
  public static var brailleRamp: Self { Self(.brailleRamp) }
  /// The erased braille line pulse: ⠉ ⠒ ⣀ ⠒.
  public static var brailleLinePulse: Self { Self(.brailleLinePulse) }
  /// The erased dice roll: the six die faces, ⚀ ⚁ ⚂ ⚃ ⚄ ⚅.
  public static var diceRoll: Self { Self(.diceRoll) }
  /// The erased box-corner orbit: ┌ ┐ ┘ └.
  public static var boxCornerOrbit: Self { Self(.boxCornerOrbit) }
  /// The erased braille dot fade: one dot down the right column and back up
  /// the left, ⠈ ⠐ ⠠ ⠄ ⠂ ⠁.
  public static var brailleDotFade: Self { Self(.brailleDotFade) }
  /// The erased braille line sweep: a two-dot line rotating, ⠘ ⠰ ⠤ ⠆ ⠃ ⠉.
  public static var brailleLineSweep: Self { Self(.brailleLineSweep) }
  /// The erased braille ring: the `brailleRingFilled` frames
  /// ⣾ ⣷ ⣯ ⣟ ⡿ ⢿ ⣽ ⣻, ending blank.
  public static var brailleRing: Self { Self(.brailleRing) }
  /// The erased arc orbit: a quarter arc rotating clockwise, ◜ ◝ ◞ ◟.
  public static var arcOrbit: Self { Self(.arcOrbit) }
  /// The erased braille loop: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏, the frames `automatic`
  /// renders.
  public static var brailleLoop: Self { Self(.brailleLoop) }
  /// The erased shade fade: █ ▓ ▒ ░, finishing solid.
  public static var shadeFade: Self { Self(.shadeFade) }
  /// The erased dot chase: three cells with one dot moving along them,
  /// `∙∙∙` `●∙∙` `∙●∙` `∙∙●`, finishing `●●●`.
  public static var dotChase: Self { Self(.dotChase) }
  /// The erased globe: 🌍 🌎 🌏, two cells wide.
  public static var globe: Self { Self(.globe) }
  /// The erased moon phases: 🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘, two cells wide, finishing
  /// full.
  public static var moonPhase: Self { Self(.moonPhase) }
  /// The erased segmented bar: ▱▱▱ filling to ▰▰▰ and emptying again,
  /// finishing full.
  public static var segmentedBar: Self { Self(.segmentedBar) }
  /// The erased arrow compass: a light arrow turning clockwise from ←.
  public static var arrowCompass: Self { Self(.arrowCompass) }
  /// The erased glyph pulse: ᔐ ᯇ ᔑ ᯇ, finishing on ᦟ.
  public static var glyphPulse: Self { Self(.glyphPulse) }
  /// The erased block corners: ▙ ▛ ▜ ▟, finishing on █.
  public static var blockCorners: Self { Self(.blockCorners) }
  /// The erased horizontal bar fill: ▏ ▎ ▍ ▌ ▋ ▊ ▉ █, finishing full.
  public static var horizontalBarFill: Self { Self(.horizontalBarFill) }
  /// The erased quadrant corners: a quadrant block hopping clockwise from the
  /// upper right, ▝ ▗ ▖ ▘, finishing on █.
  public static var quadrantCorners: Self { Self(.quadrantCorners) }
  /// The erased vertical bar fill: ▁ ▂ ▃ ▄ ▅ ▆ ▇ █, finishing full. Identical
  /// to `barRise`.
  public static var verticalBarFill: Self { Self(.verticalBarFill) }
  /// The erased heavy arrow compass: a double-stroke arrow turning clockwise
  /// from ⇑.
  public static var heavyArrowCompass: Self { Self(.heavyArrowCompass) }
  /// The erased line compass: │ ╱ ─ ╲, finishing on ┼.
  public static var lineCompass: Self { Self(.lineCompass) }
  /// The erased asterisk cycle: * · + ÷ at a slower 240 ms cadence.
  public static var asteriskCycle: Self { Self(.asteriskCycle) }
  /// The erased ogham pulse: twenty frames climbing and descending the ᚁ-to-ᚅ
  /// and ᚆ-to-ᚊ ladders, finishing on ᚔ.
  public static var oghamPulse: Self { Self(.oghamPulse) }
}
