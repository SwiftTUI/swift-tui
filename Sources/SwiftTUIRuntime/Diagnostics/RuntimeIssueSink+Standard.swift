import SwiftTUICore

extension RuntimeIssueSink {
  /// Reports runtime issues to standard error.
  public static var standardError: RuntimeIssueSink {
    RuntimeIssueSink { issue in
      Standard.Error().write(issue.description + "\n")
    }
  }
}
