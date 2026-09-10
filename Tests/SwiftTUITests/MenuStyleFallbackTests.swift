import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A presented menu whose style omitted both the portal wrapper and inline
/// content resolves the custom body, discards it, and resolves the automatic
/// body under the same `MenuBody` identity. These pins hold that the
/// discarded resolve leaves nothing behind: one issue per resolve, one body
/// subtree and one trigger route in the tree, one trigger region, one trigger
/// pointer handler in the run loop's registry, and a trigger that keeps
/// working across open, dismiss, and reopen.
@MainActor
struct MenuStyleFallbackTests {
  @Test("a presented body without content or a portal falls back exactly once per resolve")
  func fallbackResolvesOnce() throws {
    let actions = LocalActionRegistry()
    let renderer = DefaultRenderer()
    let id = testIdentity("Menu")
    let trigger = menuTriggerIdentity(for: id)
    let body = id.child(.named("MenuBody"))
    let view = Menu("Commands") { Text("Presented child") }
      .menuStyle(OmittingMenuStyle()).id(id)
    let context = ResolveContext(
      identity: testIdentity("Root"), localActionRegistry: actions, applyEnvironmentValues: true)
    let closed = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
    #expect(missingRouteIssues(in: closed).isEmpty)
    // Collapsed, the custom body is the trigger route alone.
    #expect(menuStateChildCounts(closed.resolvedTree) == [1])
    #expect(routeCount(closed.resolvedTree, identity: trigger) == 1)

    let overwrites = SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount
    #expect(actions.dispatch(identity: id))
    for _ in 0..<2 {
      let frame = renderer.render(view, context: context, proposal: .init(width: 40, height: 12))
      #expect(frame.rasterSurface.lines.joined().contains("Presented child"))
      let issues = missingRouteIssues(in: frame)
      #expect(issues.count == 1)
      #expect(issues.first?.message.contains("OmittingMenuStyle") == true)
      #expect(
        frame.diagnostics.runtime.issues.filter { $0.code != "style.missingRequiredRoute" }.isEmpty)
      #expect(menuStateChildCounts(frame.resolvedTree) == [1])
      #expect(subtreeRootCount(frame.resolvedTree, under: body) == 1)
      #expect(routeCount(frame.resolvedTree, identity: trigger) == 1)
      #expect(
        frame.semanticSnapshot.interactionRegions.filter { $0.identity == trigger }.count == 1)
    }
    #expect(SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount == overwrites)
  }

  @Test(
    "the fallback body keeps the trigger live across open, dismiss, and reopen",
    arguments: [false, true])
  func fallbackKeepsTriggerLiveThroughRunLoop(selective: Bool) throws {
    let id = testIdentity("Menu")
    let trigger = menuTriggerIdentity(for: id)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 40, height: 12),
      selectiveEvaluation: selective
    ) {
      Menu("Commands") { Text("Presented child") }.menuStyle(OmittingMenuStyle()).id(id)
    }
    defer { harness.shutdown() }
    for _ in 0..<2 {
      _ = try harness.clickText("Commands")
      #expect(harness.frame.contains("Presented child"))
      let routes = harness.runLoop.localPointerHandlerRegistry.snapshot().keys
      #expect(routes.filter { $0.identity == trigger }.count == 1)
      _ = try harness.pressKey(KeyPress(.escape))
      #expect(!harness.frame.contains("Presented child"))
    }
  }
}

private func missingRouteIssues(in frame: RenderSnapshot) -> [RuntimeIssue] {
  frame.diagnostics.runtime.issues.filter { $0.code == "style.missingRequiredRoute" }
}

/// The number of disjoint subtrees rooted at or beneath `identity`. A composed
/// body with a single child is flattened out of the resolved tree, so the
/// style body's descendants stand in for the body node itself.
private func subtreeRootCount(_ node: ResolvedNode, under identity: Identity) -> Int {
  if node.identity == identity || node.identity.isDescendant(of: identity) {
    return 1
  }
  return node.children.reduce(0) { $0 + subtreeRootCount($1, under: identity) }
}

/// The child count of every `MenuState` node: the menu's dedicated state host
/// carries exactly one style body, never the discarded resolve beside it.
private func menuStateChildCounts(_ node: ResolvedNode) -> [Int] {
  let own = node.kind == .view("MenuState") ? [node.children.count] : []
  return own + node.children.flatMap(menuStateChildCounts)
}

private func routeCount(_ node: ResolvedNode, identity: Identity) -> Int {
  let own = node.kind == .view("PointerRoute") && node.identity == identity ? 1 : 0
  return own + node.children.reduce(0) { $0 + routeCount($1, identity: identity) }
}

private struct OmittingMenuStyle: MenuStyle {
  func makeBody(configuration: MenuStyleConfiguration) -> some View {
    OmittingMenuBody(configuration: configuration)
  }
}

private struct OmittingMenuBody: View {
  let configuration: MenuStyleConfiguration
  var body: some View { configuration.trigger { configuration.label } }
}
