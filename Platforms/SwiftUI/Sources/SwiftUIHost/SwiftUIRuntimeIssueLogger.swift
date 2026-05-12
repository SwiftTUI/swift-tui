import OSLog
import SwiftTUIRuntime

enum SwiftUIRuntimeIssueLogger {
  private static let logger = Logger(
    subsystem: "SwiftTUI",
    category: "RuntimeIssue"
  )

  static var sink: RuntimeIssueSink {
    RuntimeIssueSink { issue in
      let message = issue.description
      switch issue.severity {
      case .warning:
        logger.warning("\(message, privacy: .public)")
      case .error:
        logger.error("\(message, privacy: .public)")
      }
    }
  }
}
