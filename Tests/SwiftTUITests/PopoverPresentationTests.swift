import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PopoverPresentationTests {
  @Test("boolean popover renders as a source-relative trailing overlay")
  func booleanPopoverRendersTrailingOverlay() throws {
    let artifacts = DefaultRenderer().render(
      Text("Anchor")
        .popover(
          isPresented: .constant(true),
          arrowEdge: .trailing
        ) {
          Text("Details")
        }
        .frame(width: 36, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 36, height: 8)
    )

    let lines = artifacts.rasterSurface.lines
    let source = try #require(findSubstring("Anchor", in: lines))
    let popover = try #require(findSubstring("Details", in: lines))
    let kinds = viewKindNames(in: artifacts.resolvedTree)

    #expect(popover.x > source.x)
    #expect(kinds.contains("PopoverPresentation"))
  }

  @Test("preferred edge falls back when the popover would leave the terminal")
  func preferredEdgeFallsBackWhenPopoverWouldOverflow() throws {
    let artifacts = DefaultRenderer().render(
      HStack(spacing: 0) {
        Spacer()
          .frame(width: 32)
        Text("Anchor")
          .popover(
            isPresented: .constant(true),
            arrowEdge: .trailing
          ) {
            Text("Details")
          }
      }
      .frame(width: 40, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 8)
    )

    let lines = artifacts.rasterSurface.lines
    let source = try #require(findSubstring("Anchor", in: lines))
    let popover = try #require(findSubstring("Details", in: lines))

    #expect(popover.x < source.x)
  }

  @Test("popover chrome uses the standard rounded border")
  func popoverChromeUsesStandardRoundedBorder() {
    let artifacts = DefaultRenderer().render(
      Text("Anchor")
        .popover(
          isPresented: .constant(true),
          arrowEdge: .trailing
        ) {
          Text("Details")
        }
        .frame(width: 36, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 36, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("╭"))
    #expect(surface.contains("╮"))
    #expect(surface.contains("╰"))
    #expect(surface.contains("╯"))
    #expect(!surface.contains("▗"))
    #expect(!surface.contains("▖"))
    #expect(!surface.contains("▝"))
    #expect(!surface.contains("▘"))
  }

  @Test("interactive popover gates base focus while keeping popover focusable")
  func interactivePopoverGatesBaseFocus() {
    let baseIdentity = testIdentity("BaseButton")

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Text("Base")
          .focusable(true)
          .id(baseIdentity)
        Text("Anchor")
          .popover(isPresented: .constant(true)) {
            Button("Inside") {}
              .id(testIdentity("PopoverButton"))
          }
      }
      .frame(width: 40, height: 10, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 10)
    )

    let focusPaths = artifacts.semanticSnapshot.focusRegions.map(\.identity.path)

    #expect(!focusPaths.contains(baseIdentity.path))
    #expect(focusPaths.contains { $0.contains("PopoverButton") })
  }

  @Test("item popover resolves content for the active item only")
  func itemPopoverResolvesActiveItemOnly() {
    var resolvedTitles: [String] = []
    let item = PopoverTestItem(id: "settings", title: "Settings")

    let activeArtifacts = DefaultRenderer().render(
      Text("Anchor")
        .popover(item: .constant(item)) { item in
          resolvedTitles.append(item.title)
          return Text("Inspect \(item.title)")
        }
        .frame(width: 40, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 8)
    )
    let inactiveArtifacts = DefaultRenderer().render(
      Text("Anchor")
        .popover(item: .constant(Optional<PopoverTestItem>.none)) { item in
          resolvedTitles.append(item.title)
          return Text("Inspect \(item.title)")
        }
        .frame(width: 40, height: 8, alignment: .topLeading),
      context: .init(
        identity: testIdentity("Root"),
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 8)
    )

    let activeSurface = activeArtifacts.rasterSurface.lines.joined(separator: "\n")
    let inactiveSurface = inactiveArtifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(activeSurface.contains("Inspect Settings"))
    #expect(!inactiveSurface.contains("Inspect Settings"))
    #expect(resolvedTitles == ["Settings"])
  }

  @Test("read-only popover tips render without gating base focus")
  func readOnlyPopoverTipKeepsBaseFocus() {
    let baseIdentity = testIdentity("BaseButton")
    let tip = PopoverPresentationTestTip(
      id: "shortcut",
      title: "Press Return",
      message: "Run the selected command."
    )

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Text("Base")
          .focusable(true)
          .id(baseIdentity)
        Text("Anchor")
          .popoverTip(tip, arrowEdge: .bottom)
      }
      .frame(width: 44, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 44, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let baseNode = artifacts.resolvedTree.descendant(withIdentity: baseIdentity)

    #expect(surface.contains("Press Return"))
    #expect(surface.contains("Run the selected command."))
    #expect(baseNode?.semanticMetadata.interactionAvailability.isEnabled == true)
  }

  @Test("action popover tips gate base focus and render actions")
  func actionPopoverTipGatesBaseFocus() {
    let baseIdentity = testIdentity("BaseButton")
    let tip = PopoverPresentationTestTip(
      id: "filters",
      title: "Save this filter",
      message: "Keep the current query nearby.",
      actions: [
        PopoverTipAction(id: "save", title: "Save")
      ]
    )

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 1) {
        Text("Base")
          .focusable(true)
          .id(baseIdentity)
        Text("Anchor")
          .popoverTip(tip, arrowEdge: .bottom)
      }
      .frame(width: 44, height: 10, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 44, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    let focusPaths = artifacts.semanticSnapshot.focusRegions.map(\.identity.path)

    #expect(surface.contains("Save this filter"))
    #expect(surface.contains("Save"))
    #expect(!focusPaths.contains(baseIdentity.path))
  }

  @Test("ineligible tips do not render")
  func ineligibleTipsDoNotRender() {
    let tip = PopoverPresentationTestTip(
      id: "hidden",
      title: "Hidden tip",
      message: "This should not appear.",
      isEligible: false
    )

    let artifacts = DefaultRenderer().render(
      Text("Anchor")
        .popoverTip(tip)
        .frame(width: 40, height: 8, alignment: .topLeading),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 8)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(!surface.contains("Hidden tip"))
    #expect(!surface.contains("This should not appear."))
  }
}

@MainActor
@Suite
struct PopoverPresentationEscapeDismissTests {
  @Test("an active popover exposes its dismiss closure as the Escape action")
  func activePopoverExposesDismissAction() {
    let registry = PresentationCoordinatorRegistry()
    let handle = registry.popover.handle(
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )

    var dismissed = 0
    handle.present(
      PopoverPresentationItem(
        id: "popover#1",
        sourceIdentity: testIdentity("Source"),
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .trailing,
        modalPolicy: .disablesBaseInteraction,
        surfaceItem: PromptPresentationItem(
          id: "popover#1",
          title: "",
          descriptor: sheetPromptPresentationSpec().descriptor,
          actionPayloads: [],
          messagePayloads: [],
          contentPayloads: [],
          dismiss: { dismissed += 1 }
        )
      )
    )

    let action = registry.dismissStack().topmostEscapeDismissAction()
    #expect(action != nil)
    action?()
    #expect(dismissed == 1)
  }
}

private struct PopoverTestItem: Identifiable, Sendable {
  var id: String
  var title: String
}

private struct PopoverPresentationTestTip: PopoverTip {
  var id: String
  var titleText: String
  var messageText: String?
  var actions: [PopoverTipAction]
  var isEligible: Bool

  init(
    id: String,
    title: String,
    message: String? = nil,
    actions: [PopoverTipAction] = [],
    isEligible: Bool = true
  ) {
    self.id = id
    titleText = title
    messageText = message
    self.actions = actions
    self.isEligible = isEligible
  }

  @MainActor
  var title: Text {
    Text(titleText)
  }

  @MainActor
  var message: Text? {
    messageText.map { Text($0) }
  }
}

private func viewKindNames(
  in node: ResolvedNode
) -> [String] {
  var kinds: [String] = []
  collectViewKindNames(in: node, into: &kinds)
  return kinds
}

private func collectViewKindNames(
  in node: ResolvedNode,
  into kinds: inout [String]
) {
  if case .view(let name) = node.kind {
    kinds.append(name)
  }

  for child in node.children {
    collectViewKindNames(in: child, into: &kinds)
  }
}

private func findSubstring(
  _ substring: String,
  in lines: [String]
) -> (x: Int, y: Int)? {
  let needle = Array(substring)
  guard !needle.isEmpty else {
    return nil
  }

  for (y, line) in lines.enumerated() {
    let haystack = Array(line)
    guard haystack.count >= needle.count else {
      continue
    }
    let maxStart = haystack.count - needle.count
    for start in 0...maxStart {
      let end = start + needle.count
      if Array(haystack[start..<end]) == needle {
        return (x: start, y: y)
      }
    }
  }
  return nil
}

extension ResolvedNode {
  fileprivate func descendant(withIdentity identity: Identity) -> ResolvedNode? {
    if self.identity == identity {
      return self
    }

    for child in children {
      if let match = child.descendant(withIdentity: identity) {
        return match
      }
    }
    return nil
  }
}
