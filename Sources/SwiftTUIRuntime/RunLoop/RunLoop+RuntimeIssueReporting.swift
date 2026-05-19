import SwiftTUICore

extension RunLoop {
  @MainActor
  package func reportRuntimeIssue(_ issue: RuntimeIssue) {
    guard reportedRuntimeIssues.insert(issue).inserted else {
      return
    }
    runtimeIssueSink?.report(issue)
  }

  package func reportRuntimeIssues(_ issues: [RuntimeIssue]) {
    for issue in issues {
      reportRuntimeIssue(issue)
    }
  }
}
