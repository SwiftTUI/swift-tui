import Foundation
import Testing

/// Keeps an unmarked reproduction path (`SWIFTTUI_SETH_UNMARKED=1`) while
/// limiting each guard to its exact reproduced assertion.
func setHKnown(_ comment: Comment, _ body: () throws -> Void) rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
    try body()
  } else {
    withKnownIssue(comment) { try body() }
  }
}

/// The asynchronous form, for exit-test expectations.
func setHKnown(_ comment: Comment, _ body: () async throws -> Void) async rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETH_UNMARKED"] == "1" {
    try await body()
  } else {
    await withKnownIssue(comment) { try await body() }
  }
}
