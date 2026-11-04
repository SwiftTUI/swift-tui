/// Severity for a runtime issue emitted while resolving or presenting a frame.
public enum RuntimeIssueSeverity: String, Sendable, Hashable {
  case warning
  case error
}

/// A host-facing runtime issue.
///
/// Runtime issues are narrower than frame diagnostics.
/// They describe actionable errors in authored or runtime state that a host must show.
/// Frame diagnostics can include performance counters that are not errors.
/// Each runtime issue for a frame is also part of the diagnostics for that frame.
public struct RuntimeIssue: Sendable, Hashable, CustomStringConvertible {
  public var severity: RuntimeIssueSeverity
  public var typedCode: Code

  /// The historical wire spelling of this issue, including host-defined codes.
  public var code: String {
    get { typedCode.wireValue }
    set { typedCode = Code(wireValue: newValue) }
  }
  public var message: String
  public var identity: Identity?
  public var source: String?

  public init(
    severity: RuntimeIssueSeverity,
    code: String,
    message: String,
    identity: Identity? = nil,
    source: String? = nil
  ) {
    self.init(
      severity: severity, code: Code(wireValue: code), message: message,
      identity: identity, source: source)
  }

  public init(
    severity: RuntimeIssueSeverity,
    code: Code,
    message: String,
    identity: Identity? = nil,
    source: String? = nil
  ) {
    self.severity = severity
    self.typedCode = code
    self.message = message
    self.identity = identity
    self.source = source
  }

  public var description: String {
    var parts = ["SwiftTUI runtime \(severity.rawValue)", "[\(code)]"]
    if let identity {
      parts.append("at \(identity.path.isEmpty ? "$root" : identity.path)")
    }
    if let source {
      parts.append("from \(source)")
    }
    parts.append(message)
    return parts.joined(separator: " ")
  }
}

/// A host-owned sink for runtime issue notifications.
public struct RuntimeIssueSink: Sendable {
  private let handler: @MainActor @Sendable (RuntimeIssue) -> Void

  public init(
    _ handler: @escaping @MainActor @Sendable (RuntimeIssue) -> Void
  ) {
    self.handler = handler
  }

  @MainActor
  public func report(_ issue: RuntimeIssue) {
    handler(issue)
  }
}
