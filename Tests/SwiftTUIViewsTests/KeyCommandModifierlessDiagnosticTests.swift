import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// The modifier-less `.keyCommand` guard drops the registration because bare
/// keys are framework-reserved (typing, arrows, Tab, Enter, Escape) — but it
/// must say so: a silently inert binding reads as a broken app. These pin the
/// `keyCommand.modifierlessIgnored` runtime issue and its absence for
/// registrable bindings.
@MainActor
struct KeyCommandModifierlessDiagnosticTests {
  private func resolveHost(
    @ViewBuilder content: @MainActor () -> some View
  ) -> ViewGraph {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("KeyCommandDiagnosticRoot"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    _ = Resolver().resolve(content(), in: context)
    return graph
  }

  @Test("a reserved modifier-less binding records keyCommand.modifierlessIgnored")
  func modifierlessBindingRecordsIssue() {
    let graph = resolveHost {
      Panel(id: "host") { Text("host") }
        .keyCommand("Save", key: .character("s"), modifiers: []) {}
    }

    let issue = graph.frameRuntimeIssues.first { issue in
      issue.code == "keyCommand.modifierlessIgnored"
    }
    #expect(issue != nil, "issues: \(graph.frameRuntimeIssues)")
    #expect(issue?.severity == .warning)
    #expect(issue?.message.contains("Save") == true)
  }

  @Test("a modifier-bearing binding registers without recording an issue")
  func modifierBearingBindingStaysSilent() {
    let graph = resolveHost {
      Panel(id: "host") { Text("host") }
        .keyCommand("Save", key: .character("s"), modifiers: .ctrl) {}
    }

    #expect(
      !graph.frameRuntimeIssues.contains { issue in
        issue.code == "keyCommand.modifierlessIgnored"
      },
      "issues: \(graph.frameRuntimeIssues)"
    )
  }

  @Test("a modifier-less function key stays registrable and silent")
  func modifierlessFunctionKeyStaysSilent() {
    let graph = resolveHost {
      Panel(id: "host") { Text("host") }
        .keyCommand("Help", key: .functionKey(1), modifiers: []) {}
    }

    #expect(
      !graph.frameRuntimeIssues.contains { issue in
        issue.code == "keyCommand.modifierlessIgnored"
      },
      "issues: \(graph.frameRuntimeIssues)"
    )
  }
}
