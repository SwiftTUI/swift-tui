/// The operations a published semantic control accepts.
public enum AccessibilityActionKind: String, CaseIterable, Sendable, Hashable {
  case focus, activate, increment, decrement, setValue
}

/// A control value, independent of its localized display label.
public enum AccessibilityValue: Equatable, Sendable {
  case boolean(Bool)
  case number(Double)
  case text(String)
}

/// An assistive operation. Values are delivered to the owning control directly.
public enum AccessibilityAction: Equatable, Sendable {
  case focus, activate, increment, decrement
  case setValue(AccessibilityValue)

  public var kind: AccessibilityActionKind {
    switch self {
    case .focus: .focus
    case .activate: .activate
    case .increment: .increment
    case .decrement: .decrement
    case .setValue: .setValue
    }
  }
}

/// A request targeting the opaque token from a published accessibility node.
/// Tokens belong to one live scene; hosts must discard them when it closes.
public struct AccessibilityActionRequest: Equatable, Sendable {
  /// Optional host correlation ID. A frame acknowledges the last processed request.
  public var requestID: UInt64?
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

  public static func == (lhs: AccessibilityControlState, rhs: AccessibilityControlState) -> Bool {
    lhs === rhs
      || (lhs.actions == rhs.actions && lhs.value == rhs.value
        && lhs.minimum == rhs.minimum && lhs.maximum == rhs.maximum && lhs.step == rhs.step)
  }

  public init(
    actions: [AccessibilityActionKind], value: AccessibilityValue? = nil,
    minimum: Double? = nil, maximum: Double? = nil, step: Double? = nil
  ) {
    self.actions = actions
    self.value = value
    self.minimum = minimum
    self.maximum = maximum
    self.step = step
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
