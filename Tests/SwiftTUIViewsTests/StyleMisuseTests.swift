import Testing

@testable import SwiftTUIViews

@Suite("Style misuse channel")
struct StyleMisuseTests {
  @Test("A valid presentation passes through without reporting an issue")
  func validPresentationPassesThrough() {
    var reported: [RuntimeIssue] = []
    let resolved = StyleMisuse.validatedPresentation(
      "resolved",
      problems: [],
      family: "SpinnerStyle",
      styleLabel: "SpinnerStyle.moonPhase",
      identity: nil,
      report: { reported.append($0) },
      fallback: { "fallback" }
    )
    #expect(resolved == "resolved")
    #expect(reported.isEmpty)
  }

  @Test("An invalid presentation falls back to automatic and reports one issue")
  func invalidPresentationFallsBackAndReports() throws {
    var reported: [RuntimeIssue] = []
    let resolved = StyleMisuse.validatedPresentation(
      "resolved",
      problems: ["active frames are empty", "interval is not positive"],
      family: "SpinnerStyle",
      styleLabel: "MyApp.PulseSpinnerStyle",
      identity: nil,
      report: { reported.append($0) },
      fallback: { "fallback" }
    )
    #expect(resolved == "fallback")
    let issue = try #require(reported.first)
    #expect(reported.count == 1)
    #expect(issue.code == "style.invalidPresentation")
    #expect(issue.severity == .warning)
    #expect(issue.source == "SpinnerStyle")
    // The message names the offender, every problem, and the fix, so a
    // consumer can act on the issue without a debugger attached.
    #expect(issue.message.contains("MyApp.PulseSpinnerStyle"))
    #expect(issue.message.contains("active frames are empty"))
    #expect(issue.message.contains("interval is not positive"))
    #expect(issue.message.contains("automatic presentation"))
    #expect(issue.message.contains("valid presentation values"))
  }

  @Test("The issue carries the resolving surface's identity")
  func issueCarriesIdentity() {
    let identity = testIdentity("gallery", "spinner")
    let issue = StyleMisuse.invalidPresentationIssue(
      family: "SheetStyle",
      styleLabel: "SheetStyle.dropdown",
      problems: ["minimum width is negative"],
      identity: identity
    )
    #expect(issue.identity == identity)
    #expect(issue.code == StyleMisuse.invalidPresentationCode)
  }
}
