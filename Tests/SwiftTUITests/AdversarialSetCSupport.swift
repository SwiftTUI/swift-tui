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

/// The exit-test twin of `setCKnown` (F1 pass 3): the guard wraps only the
/// child-process expectation, and `SWIFTTUI_SETC_UNMARKED=1` bypasses it.
@MainActor
func setCKnownAsync(_ comment: Comment, _ body: () async -> Void) async {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETC_UNMARKED"] == "1" {
    await body()
  } else {
    await withKnownIssue(comment) { await body() }
  }
}
