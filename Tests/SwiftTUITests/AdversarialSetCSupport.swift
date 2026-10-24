import Foundation
import Testing

/// Keep an unmarked reproduction path while limiting each guard to its exact assertion.
@MainActor
func setCKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETC_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}
