public import SwiftTUICore

/// Defines how single-line and secure text fields render their label and field content.
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

  public struct FieldContent: View, Sendable {
    package var displayText: String
    package var displayRuns: [TextInputDisplayRun]
    package var ownerIdentity: Identity?
    package var caretAnchor: CellPoint?

    nonisolated package init(
      displayText: String,
      displayRuns: [TextInputDisplayRun]? = nil,
      ownerIdentity: Identity? = nil,
      caretAnchor: CellPoint? = nil
    ) {
      self.displayText = displayText
      self.displayRuns =
        displayRuns ?? [
          TextInputDisplayRun(text: displayText, isSelected: false)
        ]
      self.ownerIdentity = ownerIdentity
      self.caretAnchor = caretAnchor
    }

    public var body: some View {
      TextInputContent(
        displayText: displayText,
        displayRuns: displayRuns,
        ownerIdentity: ownerIdentity,
        caretAnchor: caretAnchor
      )
    }
  }

  public var displayText: String
  public var fieldContent: FieldContent
  public var isShowingPrompt: Bool
  public var label: Label
  public var showsLabel: Bool
  public var chrome: ControlChrome
  public var placeholderStyle: AnyShapeStyle
  public var focusActive: Bool
  public var styleEnvironment: StyleEnvironmentSnapshot

  package init(
    displayText: String,
    fieldContent: FieldContent? = nil,
    isShowingPrompt: Bool,
    label: Label,
    showsLabel: Bool,
    chrome: ControlChrome,
    placeholderStyle: AnyShapeStyle,
    focusActive: Bool,
    styleEnvironment: StyleEnvironmentSnapshot
  ) {
    self.displayText = displayText
    self.fieldContent = fieldContent ?? FieldContent(displayText: displayText)
    self.isShowingPrompt = isShowingPrompt
    self.label = label
    self.showsLabel = showsLabel
    self.chrome = chrome
    self.placeholderStyle = placeholderStyle
    self.focusActive = focusActive
    self.styleEnvironment = styleEnvironment
  }
}

package func textInputChrome(
  styleEnvironment: StyleEnvironmentSnapshot,
  isEnabled: Bool,
  isFocused: Bool
) -> ControlChrome {
  let contentChrome = styleEnvironment.controlChrome(
    isEnabled: isEnabled,
    isFocused: false
  )
  guard isEnabled, isFocused else {
    return contentChrome
  }

  let focusChrome = styleEnvironment.controlChrome(
    isEnabled: true,
    isFocused: true
  )
  return ControlChrome(
    foregroundStyle: contentChrome.foregroundStyle,
    contentBackgroundStyle: contentChrome.contentBackgroundStyle,
    borderForegroundStyle: focusChrome.borderForegroundStyle,
    borderBackgroundStyle: focusChrome.borderBackgroundStyle,
    opacity: contentChrome.opacity
  )
}

/// Type-erased storage for a concrete text-field style.
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

/// The environment-driven default text-field style.
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

/// A text-field style that renders only the field content.
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

/// A text-field style that draws rounded border chrome around the field content.
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
      configuration.fieldContent
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
      configuration.fieldContent
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
        RoundedRectangle(cornerRadius: 1).strokeBorder(
          configuration.chrome.borderStyle,
          style: configuration.focusActive ? .heavy : .init(),
          background: configuration.chrome.borderBackgroundStyle
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
