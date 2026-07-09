/// Severity for a runtime issue emitted while resolving or presenting a frame.
public enum RuntimeIssueSeverity: String, Sendable, Hashable {
  case warning
  case error
}

/// A host-facing runtime issue.
///
/// Runtime issues are narrower than frame diagnostics: they represent actionable
/// problems in authored or runtime state that a host should surface. Frame
/// diagnostics may include many non-issue performance counters, but every
/// runtime issue recorded for a frame is also attached to that frame's
/// diagnostics.
public struct RuntimeIssue: Sendable, Hashable, CustomStringConvertible {
  public var severity: RuntimeIssueSeverity
  public var code: String
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
    self.severity = severity
    self.code = code
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
