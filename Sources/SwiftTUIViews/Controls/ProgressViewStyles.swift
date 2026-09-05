public import SwiftTUICore

/// Defines the visual composition of a ``ProgressView``.
public protocol ProgressViewStyle: Sendable {
  associatedtype Body: View
  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(configuration: ProgressViewStyleConfiguration) -> Body

  /// Value-type conformance guard; use its default implementation.
  @_documentation(visibility: internal)
  static var _progressViewStyleValueTypeWitness: Void { get }
}

extension ProgressViewStyle {
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
public struct ProgressViewStyleConfiguration: Sendable {
  /// The captured authored label.
  public struct Label: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures authored content for a style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  /// The captured authored current-value label.
  public struct CurrentValueLabel: View, Sendable {
    package let payload: CapturedSubviewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = CapturedSubviewPayload(authoringContext: authoringContext, content: content)
    }

    /// Captures authored content for a style fixture.
    @_spi(StyleFixtures)
    public init<V: View>(@ViewBuilder content: @escaping @MainActor () -> V) {
      payload = CapturedSubviewPayload(content: content)
    }

    public var body: some View { CapturedSubviewView(payload: payload) }
  }

  public var fractionCompleted: Double?
  public var label: Label?
  public var currentValueLabel: CurrentValueLabel?
  public var barWidth: Int
  public var indeterminatePhase: UInt64
  public var accessibilityReduceMotion: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  public var isIndeterminate: Bool { fractionCompleted == nil }

  /// Constructs a configuration for a style test (see <doc:Testing-Styles>).
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

/// Type-erased storage for a concrete ``ProgressViewStyle``.
public struct AnyProgressViewStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible
{
  package let snapshotLabel: String
  private let box: any AnyProgressViewStyleBox

  public init<S: ProgressViewStyle>(_ style: S) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyProgressViewStyleBox(style: style)
  }

  public var description: String { snapshotLabel }
  public var debugDescription: String { snapshotLabel }

  public static var automatic: Self {
    Self(AutomaticProgressViewStyle())
  }
  public static var linear: Self {
    Self(LinearProgressViewStyle())
  }
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

/// The `automatic` treatment for ``ProgressView``.
public struct AutomaticProgressViewStyle: ProgressViewStyle {
  public init() {}
  public var snapshotLabel: String { "AnyProgressViewStyle.automatic" }

  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    LinearProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == AutomaticProgressViewStyle {
  public static var automatic: AutomaticProgressViewStyle { .init() }
}

extension AutomaticProgressViewStyle: ReuseTransparentStyle {}

/// The `linear` treatment for ``ProgressView``.
public struct LinearProgressViewStyle: ProgressViewStyle {
  public init() {}
  public var snapshotLabel: String { "AnyProgressViewStyle.linear" }

  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    LinearProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
  public static var linear: LinearProgressViewStyle { .init() }
}

extension LinearProgressViewStyle: ReuseTransparentStyle {}

/// The `circular` treatment for ``ProgressView``.
public struct CircularProgressViewStyle: ProgressViewStyle {
  public init() {}
  public var snapshotLabel: String { "AnyProgressViewStyle.circular" }

  @MainActor
  public func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    CircularProgressViewStyleBody(configuration: configuration)
  }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
  public static var circular: CircularProgressViewStyle { .init() }
}

extension CircularProgressViewStyle: ReuseTransparentStyle {}

private protocol AnyProgressViewStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyProgressViewStyleBox) -> Bool

  @MainActor
  func resolveBody(configuration: ProgressViewStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
}

private struct ConcreteAnyProgressViewStyleBox<S: ProgressViewStyle>: AnyProgressViewStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyProgressViewStyleBox) -> Bool {
    guard let other = other as? Self else { return false }
    return styleValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func resolveBody(configuration: ProgressViewStyleConfiguration, in context: ResolveContext)
    -> ResolvedNode
  {
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel, in: context)
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
          let filled = min(width, max(0, Int((normalized * Double(width)).rounded())))
          HStack(alignment: .center, spacing: 0) {
            Text(String(repeating: "█", count: filled)).foregroundStyle(.tint)
            Text(String(repeating: "─", count: width - filled)).foregroundStyle(.separator)
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
