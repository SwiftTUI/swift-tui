public import Core

public protocol TextFieldStyle: Sendable {
  associatedtype Body: View

  var snapshotLabel: String { get }

  @ViewBuilder @MainActor
  func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> Body
}

extension TextFieldStyle {
  public var snapshotLabel: String {
    String(reflecting: Self.self)
  }
}

public struct TextFieldStyleConfiguration: Sendable {
  public struct Label: View, Sendable {
    package let payload: DeferredViewPayload

    package init<V: View>(
      authoringContext: AuthoringContext?,
      @ViewBuilder content: @escaping @MainActor () -> V
    ) {
      payload = DeferredViewPayload(
        authoringContext: authoringContext,
        content: content
      )
    }

    public var body: some View {
      DeferredPayloadView(payload: payload)
    }
  }

  public var displayText: String
  public var isShowingPrompt: Bool
  public var label: Label
  public var showsLabel: Bool
  public var chrome: ControlChrome
  public var placeholderStyle: AnyShapeStyle
  public var focusActive: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  package init(
    displayText: String,
    isShowingPrompt: Bool,
    label: Label,
    showsLabel: Bool,
    chrome: ControlChrome,
    placeholderStyle: AnyShapeStyle,
    focusActive: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.displayText = displayText
    self.isShowingPrompt = isShowingPrompt
    self.label = label
    self.showsLabel = showsLabel
    self.chrome = chrome
    self.placeholderStyle = placeholderStyle
    self.focusActive = focusActive
    self.styleEnvironment = styleEnvironment
  }
}

public struct AnyTextFieldStyle: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  package let snapshotLabel: String
  private let box: any AnyTextFieldStyleBox

  public init<S: TextFieldStyle>(
    _ style: S
  ) {
    snapshotLabel = style.snapshotLabel
    box = ConcreteAnyTextFieldStyleBox(style: style)
  }

  public var description: String {
    snapshotLabel
  }

  public var debugDescription: String {
    snapshotLabel
  }

  public static var automatic: Self {
    Self(AutomaticTextFieldStyle())
  }

  public static var plain: Self {
    Self(PlainTextFieldStyle())
  }

  public static var roundedBorder: Self {
    Self(RoundedBorderTextFieldStyle())
  }

  @MainActor
  package func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    box.resolveBody(
      configuration: configuration,
      in: context
    )
  }
}

public struct AutomaticTextFieldStyle: Sendable, TextFieldStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyTextFieldStyle.automatic"
  }

  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    RoundedBorderTextFieldStyleBody(configuration: configuration)
  }
}

public struct PlainTextFieldStyle: Sendable, TextFieldStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyTextFieldStyle.plain"
  }

  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    PlainTextFieldStyleBody(configuration: configuration)
  }
}

public struct RoundedBorderTextFieldStyle: Sendable, TextFieldStyle {
  public init() {}

  public var snapshotLabel: String {
    "AnyTextFieldStyle.roundedBorder"
  }

  @MainActor
  public func makeBody(
    configuration: TextFieldStyleConfiguration
  ) -> some View {
    RoundedBorderTextFieldStyleBody(configuration: configuration)
  }
}

private protocol AnyTextFieldStyleBox: Sendable {
  @MainActor
  func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

private struct ConcreteAnyTextFieldStyleBox<S: TextFieldStyle>: AnyTextFieldStyleBox {
  let style: S

  @MainActor
  func resolveBody(
    configuration: TextFieldStyleConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    normalizeResolvedElements(
      resolveViewElements(
        style.makeBody(configuration: configuration),
        in: context
      ),
      in: context
    )
  }
}

package struct PlainTextFieldStyleBody: View {
  let configuration: TextFieldStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let textStyle =
      configuration.isShowingPrompt
      ? configuration.placeholderStyle
      : configuration.chrome.foregroundStyle
    let field =
      Text(configuration.displayText)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(textStyle)
      .drawMetadata(.init(opacity: configuration.chrome.opacity))

    if configuration.showsLabel {
      VStack(alignment: .leading, spacing: 0) {
        configuration.label
          .foregroundStyle(.terminalBorder(.accent))
        field
      }
    } else {
      field
    }
  }
}

package struct RoundedBorderTextFieldStyleBody: View {
  let configuration: TextFieldStyleConfiguration

  @MainActor
  @ViewBuilder
  package var body: some View {
    let textStyle =
      configuration.isShowingPrompt
      ? configuration.placeholderStyle
      : configuration.chrome.foregroundStyle
    let baseField =
      Text(configuration.displayText)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(textStyle)
      .drawMetadata(.init(opacity: configuration.chrome.opacity))
    let field =
      HStack(alignment: .center, spacing: 0) {
        baseField
        Spacer(minLength: 0)
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .background {
        RoundedRectangle(cornerRadius: 1).inset(by: 1).fill(
          configuration.chrome.backgroundStyle
        )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 1).chromeStrokeBorder(
          configuration.chrome.borderStyle,
          style: configuration.focusActive ? .thick : .init(),
          backgroundStyle: configuration.chrome.borderBackgroundStyle
        )
      }

    let content =
      Group {
        if configuration.showsLabel {
          VStack(alignment: .leading, spacing: 0) {
            configuration.label
              .foregroundStyle(.terminalBorder(.accent))
            field
          }
        } else {
          field
        }
      }

    content.layoutMetadata(
      .init(
        minimumHeight: (configuration.showsLabel ? 1 : 0) + 3
      )
    )
  }
}
