/// The operations a published semantic control accepts.
public enum AccessibilityActionKind: String, CaseIterable, Sendable, Hashable {
  case focus, activate, increment, decrement, setValue, custom, editText, selectText
  case accessibilityFocus, accessibilityBlur
}

/// A control value, independent of its localized display label.
public enum AccessibilityValue: Equatable, Sendable {
  case boolean(Bool)
  case number(Double)
  case text(String)
}

/// The native selection pattern used by an assistive presenter.
public enum AccessibilitySelectionPresentation: String, Sendable {
  case menu, list, radioGroup, segmented
}

/// An opaque choice owned by one live control. Hosts return its ID as a text
/// value; labels and array positions are never selection commands.
public struct AccessibilitySelectionOption: Equatable, Sendable {
  public let id: String
  public let label: String
  public let isEnabled: Bool

  public init(id: String, label: String, isEnabled: Bool) {
    self.id = id
    self.label = label
    self.isEnabled = isEnabled
  }
}

/// All choices, including choices outside the visual picker viewport.
public struct AccessibilitySelection: Equatable, Sendable {
  public let presentation: AccessibilitySelectionPresentation
  public let options: [AccessibilitySelectionOption]

  public init(
    presentation: AccessibilitySelectionPresentation, options: [AccessibilitySelectionOption]
  ) {
    self.presentation = presentation
    self.options = options
  }
}

/// A native editor's text and directed selection, measured in UTF-16 code units.
/// Selection-only requests include the expected text so an obsolete range cannot
/// select unrelated content after an application update.
public struct AccessibilityTextEdit: Equatable, Sendable {
  /// The replacement text, or expected current text for a selection-only request.
  public let text: String
  /// The fixed end of the selection in UTF-16 code units.
  public let anchor: Int
  /// The moving end of the selection in UTF-16 code units.
  public let head: Int

  /// Creates an edit. Controls reject out-of-range and split-grapheme offsets.
  public init(text: String, anchor: Int, head: Int) {
    self.text = text
    self.anchor = anchor
    self.head = head
  }
}

/// An assistive operation. Values are delivered to the owning control directly.
public enum AccessibilityAction: Equatable, Sendable {
  case focus, activate, increment, decrement
  case accessibilityFocus, accessibilityBlur
  case setValue(AccessibilityValue)
  /// Replaces text and updates its directed selection as one operation.
  case editText(AccessibilityTextEdit)
  /// Reviews a range without writing the application's text binding.
  case selectText(AccessibilityTextEdit)
  case custom(String)

  public var kind: AccessibilityActionKind {
    switch self {
    case .accessibilityFocus: .accessibilityFocus
    case .accessibilityBlur: .accessibilityBlur
    case .focus: .focus
    case .activate: .activate
    case .increment: .increment
    case .decrement: .decrement
    case .setValue: .setValue
    case .editText: .editText
    case .selectText: .selectText
    case .custom: .custom
    }
  }
}

/// A request targeting the opaque token from a published accessibility node.
/// Tokens belong to one live scene; hosts must discard them when it closes.
public struct AccessibilityActionRequest: Equatable, Sendable {
  /// Optional host correlation ID. A frame acknowledges the last processed request.
  public var requestID: UInt64?
  /// In-process ingress provenance; never supplied by the browser wire payload.
  package var hostSession: UInt64?
  public var target: String
  public var action: AccessibilityAction

  public init(target: String, action: AccessibilityAction, requestID: UInt64? = nil) {
    self.requestID = requestID
    self.target = target
    self.action = action
  }
}

/// Typed presentation supplied by a primitive control. Secure controls never
/// publish their text value, including in debug or wire snapshots.
public final class AccessibilityControlState: Equatable, Sendable {
  public let actions: [AccessibilityActionKind]
  public let value: AccessibilityValue?
  public let minimum: Double?
  public let maximum: Double?
  public let step: Double?
  public let selection: AccessibilitySelection?
  public let customActions: [String]
  /// A default link may be opened by the presentation host. Custom Swift
  /// activation handlers leave this false and remain authoritative.
  public let opensLink: Bool

  public static func == (lhs: AccessibilityControlState, rhs: AccessibilityControlState) -> Bool {
    lhs === rhs
      || (lhs.actions == rhs.actions && lhs.value == rhs.value
        && lhs.minimum == rhs.minimum && lhs.maximum == rhs.maximum && lhs.step == rhs.step
        && lhs.selection == rhs.selection && lhs.customActions == rhs.customActions
        && lhs.opensLink == rhs.opensLink)
  }

  public init(
    actions: [AccessibilityActionKind], value: AccessibilityValue? = nil,
    minimum: Double? = nil, maximum: Double? = nil, step: Double? = nil,
    selection: AccessibilitySelection? = nil, customActions: [String] = [], opensLink: Bool = false
  ) {
    self.actions = actions
    self.value = value
    self.minimum = minimum
    self.maximum = maximum
    self.step = step
    self.selection = selection
    self.customActions = customActions
    self.opensLink = opensLink
  }
}

/// Deterministic runtime disposition; rejected requests perform no operation.
public enum AccessibilityActionResult: String, Equatable, Sendable {
  case accepted, staleTarget, disabled, outOfScope, unsupported, invalidValue
}

package enum AccessibilityActionOutcome {
  case changed, unchanged, invalidValue, unsupported
}

/// The last processed assistive request, carried with authoritative frame state.
/// It contains no submitted values, so secure input cannot leak into responses.
public struct AccessibilityActionResponse: Equatable, Sendable {
  public let requestID: UInt64
  public let target: String
  public let result: AccessibilityActionResult

  public init(requestID: UInt64, target: String, result: AccessibilityActionResult) {
    self.requestID = requestID
    self.target = target
    self.result = result
  }
}
