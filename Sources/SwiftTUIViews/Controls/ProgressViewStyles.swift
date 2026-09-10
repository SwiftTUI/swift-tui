public import SwiftTUICore

/// Defines the visual composition of a ``ProgressView``.
///
/// A progress style is body-producing: ``makeBody(configuration:)`` receives a
/// ``ProgressViewStyleConfiguration`` and returns the replacement body. The
/// configuration hands the style the optional completed fraction, the optional
/// authored label slots, the bar width, a live phase for indeterminate
/// progress, and the reduced-motion policy in force.
///
/// The primitive keeps the cadence and the accessibility role: it owns the
/// task that advances ``ProgressViewStyleConfiguration/indeterminatePhase``,
/// its cancellation, and the decision not to start it under reduced motion or
/// stable output. A progress view takes no focus and has no routes, so a
/// style composes only appearance.
///
/// Three built-ins ship. ``LinearProgressViewStyle`` draws a header and a
/// horizontal track, ``AutomaticProgressViewStyle`` is a fixed alias of it,
/// and ``CircularProgressViewStyle`` draws a ring for determinate progress and
/// composes a ``Spinner`` for indeterminate progress. Apply one with
/// `progressViewStyle(_:)`, which stores the style in the environment
/// for its subtree; the nearest modifier wins.
///
/// A conformance is a `Sendable` value type; a class cannot conform.
///
/// ```swift
/// struct PercentProgressViewStyle: ProgressViewStyle {
///   func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
///     HStack(spacing: 1) {
///       configuration.label
///       if let fraction = configuration.fractionCompleted {
///         Text("\(Int((fraction * 100).rounded()))%")
///       } else {
///         Text(String(repeating: "·", count: configuration.barWidth) + "…")
///       }
///     }
///   }
/// }
///
/// ProgressView("Sync", value: done, total: 4)
///   .progressViewStyle(PercentProgressViewStyle())
/// ```
///
/// See <doc:Style-System> and <doc:Authoring-Styles>.
public protocol ProgressViewStyle: Sendable {
  /// The view type ``makeBody(configuration:)`` returns.
  associatedtype Body: View
  /// The label this style reports in snapshots, debug bundles, and style
  /// runtime issues.
  ///
  /// The default implementation reflects the conforming type's name; the
  /// built-ins pin their own, such as `"AnyProgressViewStyle.circular"`. It is
  /// diagnostic text, not identity: do not branch on it.
  var snapshotLabel: String { get }

  /// Composes the captured content and progress state into the rendered body.
  ///
  /// Runs on the main actor once per resolve of the styled progress view, and
  /// again on every phase step while indeterminate progress animates.
  ///
  /// - Parameter configuration: The optional fraction, the optional label
  ///   slots, the bar width, the indeterminate phase, and the reduced-motion
  ///   policy.
  /// - Returns: The replacement body for the progress view.
  @ViewBuilder @MainActor
  func makeBody(configuration: ProgressViewStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _progressViewStyleValueTypeWitness: Void { get }
}

extension ProgressViewStyle {
  /// The reflected name of the conforming type, used unless the style pins a
  /// label of its own.
  public var snapshotLabel: String { String(reflecting: Self.self) }

  @_documentation(visibility: internal)
  public static var _progressViewStyleValueTypeWitness: Void { () }
}

extension ProgressViewStyle where Self: AnyObject {
  @_documentation(visibility: internal)
  @available(
    *, unavailable,
    message: "SwiftTUI styles must be value types; a class cannot conform to ProgressViewStyle"
  )
  public static var _progressViewStyleValueTypeWitness: Void { () }
}

/// Authored content and primitive-owned state supplied to a ``ProgressViewStyle``.
///
/// ``Label`` and ``CurrentValueLabel`` are captured authored slots, both
/// optional: placing one in the style body renders the authored content with
/// the state and scope it was declared in. The remaining members are read-only
/// render state for this resolve, including the completed fraction, the bar
/// width, the live indeterminate phase, and the reduced-motion policy.
///
/// A progress view has no binding, no focus stop, and no routes, so a style
/// only arranges and paints what it is given.
public struct ProgressViewStyleConfiguration: Sendable {
  /// The captured authored label.
  ///
  /// Place it in the style body to render the caption; the authored content
  /// keeps its own state and authoring scope wherever it is placed.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures `content` as the authored label of a fixture-constructed
    /// configuration for a style test (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured authored current-value label.
  ///
  /// The value initializers author it as the summary text `"value/total"`; a
  /// custom label supplied to the full initializer is captured verbatim.
  public struct CurrentValueLabel: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures `content` as the authored current-value label of a
    /// fixture-constructed configuration for a style test
    /// (see <doc:Testing-Styles>).
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    /// The captured authored content.
    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The completed fraction in `0...1`, or `nil` for indeterminate progress.
  ///
  /// The live path divides the declared value by the total and clamps the
  /// result, substituting zero for a value that is not finite; a fixture may
  /// supply any `Double`, so a style that derives a cell count from it should
  /// clamp as the built-ins do.
  public var fractionCompleted: Double?
  /// The captured authored label, or `nil` when the declaration has none.
  ///
  /// An explicitly authored `EmptyView` label is also `nil` here, because the
  /// unlabeled initializers author one; the group-box rule that an authored
  /// `EmptyView` is a present slot does not apply to this family.
  public var label: Label?
  /// The captured authored current-value label, or `nil` when the declaration
  /// has none.
  ///
  /// The same rule applies as for ``label``: an explicitly authored
  /// `EmptyView` reads as absent.
  public var currentValueLabel: CurrentValueLabel?
  /// The track width in terminal cells, at least `1`.
  ///
  /// It comes from the declaration's `barWidth` argument, which defaults to
  /// `12`; the primitive raises a smaller authored value to `1`. A style may
  /// draw any width, and nothing requires it to draw a track at all.
  public var barWidth: Int
  /// A counter the primitive advances on its own cadence, one step per 120 ms,
  /// while indeterminate progress animates.
  ///
  /// It is `0` for determinate progress and whenever the animation is
  /// suppressed. Take it modulo a period to place a moving band; it wraps
  /// around at the end of `UInt64` rather than trapping.
  public var indeterminatePhase: UInt64
  /// Whether motion is reduced for this resolve.
  ///
  /// It is `true` when the reduced-motion accessibility preference is set or
  /// when stable output is on, so a style sees the combined rendering policy
  /// rather than the accessibility preference alone. The primitive schedules
  /// no phase task under it, and the built-ins render only the header.
  public var accessibilityReduceMotion: Bool
  /// The `StyleEnvironmentSnapshot` for this resolve: the terminal
  /// appearance, the active theme, the ambient foreground and tint paints,
  /// the enabled state, and the cell metrics.
  public var styleEnvironment: StyleEnvironmentSnapshot

  /// Whether the work has no measurable fraction, that is whether
  /// ``fractionCompleted`` is `nil`.
  public var isIndeterminate: Bool { fractionCompleted == nil }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
  ///
  /// The arguments follow this type's stored-property declaration order.
  /// `indeterminatePhase` defaults to zero, the value a live determinate
  /// progress view supplies.
  @_spi(StyleFixtures)
  public init(
    fractionCompleted: Double?,
    label: Label?,
    currentValueLabel: CurrentValueLabel?,
    barWidth: Int,
    indeterminatePhase: UInt64 = 0,
    accessibilityReduceMotion: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.fractionCompleted = fractionCompleted
    self.label = label
    self.currentValueLabel = currentValueLabel
    self.barWidth = barWidth
    self.indeterminatePhase = indeterminatePhase
    self.accessibilityReduceMotion = accessibilityReduceMotion
    self.styleEnvironment = styleEnvironment
  }
}

/// Type-erased storage for a concrete ``ProgressViewStyle``, the value the
/// environment carries.
public struct AnyProgressViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyProgressViewStyleBox

  /// Wraps a concrete progress style for the environment.
  ///
  /// The generic `progressViewStyle(_:)` overload calls this for you.
  ///
  /// - Parameter style: The style to erase.
  public init<S: ProgressViewStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteStyleBox(style: style)
  }

  /// The wrapped style's `snapshotLabel`.
  public var description: String { snapshotLabel }
  /// The wrapped style's `snapshotLabel`.
  public var debugDescription: String { snapshotLabel }

  /// The ``AutomaticProgressViewStyle`` treatment, a fixed alias of
  /// ``AnyProgressViewStyle/linear``.
  public static var automatic: Self {
    Self(AutomaticProgressViewStyle())
  }
  /// The ``LinearProgressViewStyle`` treatment: a header row above a
  /// horizontal track.
  public static var linear: Self {
    Self(LinearProgressViewStyle())
  }
  /// The ``CircularProgressViewStyle`` treatment: a five-step ring for
  /// determinate progress, a composed ``Spinner`` for indeterminate progress.
  public static var circular: Self {
    Self(CircularProgressViewStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: ProgressViewStyleConfiguration, in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(configuration: configuration, in: context)
  }
}

extension AnyProgressViewStyle: TypedReuseEqualityProviding {
  package func isEqualForReuse(to other: any Sendable) -> Bool {
    guard let other = other as? Self else { return false }
    return box.isEqualForReuse(to: other.box)
  }
}

/// The `automatic` treatment for ``ProgressView``: a fixed alias of
/// ``LinearProgressViewStyle``.
///
/// It renders exactly what the linear style renders and exists so that
/// `.automatic` names one documented treatment rather than a hidden second
/// one. It reports its own snapshot label.
public struct AutomaticProgressViewStyle: ProgressViewStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyProgressViewStyle.automatic" }

  /// Composes the linear treatment's body: the header, then the track.
  ///
  /// - Parameter configuration: The progress view's captured content and state.
  /// - Returns: The same body ``LinearProgressViewStyle`` produces.
  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    LinearProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == AutomaticProgressViewStyle {
  /// The automatic progress treatment, spelled `.automatic` wherever a
  /// ``ProgressViewStyle`` is expected.
  public static var automatic: AutomaticProgressViewStyle { .init() }
}

extension AutomaticProgressViewStyle: ReuseTransparentStyle {}

/// The `linear` treatment for ``ProgressView``: a header row above a
/// horizontal track.
///
/// The header places the label in the theme's accent border role and pushes
/// the current-value label to the trailing edge with a spacer, and is omitted
/// when the declaration has neither. Determinate progress draws
/// ``ProgressViewStyleConfiguration/barWidth`` cells of `█` in the tint paint
/// followed by `─` in the separator paint. Indeterminate progress moves a band
/// of about a third of the width along the track, stepping with
/// ``ProgressViewStyleConfiguration/indeterminatePhase``. Under reduced motion
/// or stable output only the header renders.
public struct LinearProgressViewStyle: ProgressViewStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyProgressViewStyle.linear" }

  /// Composes the header and the determinate or moving track into a column.
  ///
  /// - Parameter configuration: The progress view's captured content and state.
  /// - Returns: The linear body for the progress view.
  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    LinearProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
  /// The linear progress treatment, spelled `.linear` wherever a
  /// ``ProgressViewStyle`` is expected.
  public static var linear: LinearProgressViewStyle { .init() }
}

extension LinearProgressViewStyle: ReuseTransparentStyle {}

/// The `circular` treatment for ``ProgressView``: a ring glyph under the same
/// header, or a composed spinner.
///
/// Determinate progress rounds the fraction to one of `○`, `◔`, `◑`, `◕`, `●`
/// and paints it with the tint. Indeterminate progress composes a ``Spinner``,
/// which picks up the nearest ``SpinnerStyle`` from the environment, so
/// `.spinnerStyle(...)` around the progress view changes its glyphs and
/// cadence. Under reduced motion or stable output only the header renders and
/// no spinner task is scheduled.
public struct CircularProgressViewStyle: ProgressViewStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics.
  public var snapshotLabel: String { "AnyProgressViewStyle.circular" }

  /// Composes the header and either the ring glyph or a ``Spinner`` into a
  /// column.
  ///
  /// - Parameter configuration: The progress view's captured content and state.
  /// - Returns: The circular body for the progress view.
  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    CircularProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
  /// The circular progress treatment, spelled `.circular` wherever a
  /// ``ProgressViewStyle`` is expected.
  public static var circular: CircularProgressViewStyle { .init() }
}

extension CircularProgressViewStyle: ReuseTransparentStyle {}

private protocol AnyProgressViewStyleBox: AnyStyleBox {

  @MainActor
  func resolveBody(configuration: ProgressViewStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

extension ConcreteStyleBox: AnyProgressViewStyleBox where S: ProgressViewStyle {

  @MainActor
  func resolveBody(configuration: ProgressViewStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
  }
}

private struct ProgressStyleHeader: View {
  let configuration: ProgressViewStyleConfiguration

  var body: some View {
    if configuration.label != nil || configuration.currentValueLabel != nil {
      HStack(alignment: .center, spacing: 1) {
        if let label = configuration.label {
          label.foregroundStyle(.terminalBorder(.accent))
        }
        if let value = configuration.currentValueLabel {
          Spacer()
          value.foregroundStyle(.separator)
        }
      }
    }
  }
}

private struct LinearProgressViewStyleBody: View {
  let configuration: ProgressViewStyleConfiguration

  var body: some View {
    if configuration.accessibilityReduceMotion {
      ProgressStyleHeader(configuration: configuration)
    } else {
      let width = max(1, configuration.barWidth)
      VStack(alignment: .leading, spacing: 0) {
        ProgressStyleHeader(configuration: configuration)
        if let fraction = configuration.fractionCompleted {
          let normalized = fraction.isFinite ? min(max(fraction, 0), 1) : 0
          let track = metricTrackString(fraction: normalized, barWidth: width)
          HStack(alignment: .center, spacing: 0) {
            Text(track.filled).foregroundStyle(.tint)
            Text(track.empty).foregroundStyle(.separator)
          }
        } else {
          let band = max(1, width / 3 + (width % 3 == 0 ? 0 : 1))
          let travel = max(1, width - band + 1)
          let offset = Int(configuration.indeterminatePhase % UInt64(travel))
          HStack(alignment: .center, spacing: 0) {
            Text(String(repeating: "─", count: offset)).foregroundStyle(.separator)
            Text(String(repeating: "█", count: band)).foregroundStyle(.tint)
            Text(String(repeating: "─", count: width - offset - band)).foregroundStyle(.separator)
          }
        }
      }
    }
  }
}

private struct CircularProgressViewStyleBody: View {
  let configuration: ProgressViewStyleConfiguration

  var body: some View {
    if configuration.accessibilityReduceMotion {
      ProgressStyleHeader(configuration: configuration)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ProgressStyleHeader(configuration: configuration)
        if let fraction = configuration.fractionCompleted {
          let normalized = fraction.isFinite ? min(max(fraction, 0), 1) : 0
          let rings = ["○", "◔", "◑", "◕", "●"]
          Text(rings[Int((normalized * 4).rounded())]).foregroundStyle(.tint)
        } else {
          Spinner()
        }
      }
    }
  }
}
