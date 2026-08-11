import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct LinearAccessibilityRendererTests {
  @Test("renderer emits layout reading order with labels and hints")
  func rendererEmitsReadingOrderWithLabelsAndHints() {
    let rootID = testIdentity("Dashboard")
    let rightID = testIdentity("Dashboard", "Right")
    let leftID = testIdentity("Dashboard", "Left")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: rootID,
          rect: rect(x: 0, y: 0, width: 20, height: 4),
          role: .group,
          label: "Dashboard"
        ),
        AccessibilityNode(
          identity: rightID,
          parentIdentity: rootID,
          rect: rect(x: 10, y: 1, width: 8, height: 1),
          role: .button,
          label: "Right"
        ),
        AccessibilityNode(
          identity: leftID,
          parentIdentity: rootID,
          rect: rect(x: 0, y: 1, width: 8, height: 1),
          role: .link,
          label: "Left",
          hint: "Opens docs"
        ),
      ]
    )

    let output = LinearAccessibilityRenderer().render(snapshot)

    #expect(
      output == """
        group: Dashboard
          button: Right
          link: Left - Opens docs

        """
    )
  }

  @Test("renderer skips structural unlabeled groups but preserves parent depth")
  func rendererSkipsStructuralGroupsButPreservesDepth() {
    let rootID = testIdentity("Root")
    let sectionID = testIdentity("Root", "Section")
    let buttonID = testIdentity("Root", "Section", "Button")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: rootID,
          rect: rect(x: 0, y: 0, width: 30, height: 8),
          role: .group
        ),
        AccessibilityNode(
          identity: sectionID,
          parentIdentity: rootID,
          rect: rect(x: 0, y: 1, width: 30, height: 4),
          role: .region,
          label: "Settings"
        ),
        AccessibilityNode(
          identity: buttonID,
          parentIdentity: sectionID,
          rect: rect(x: 2, y: 2, width: 8, height: 1),
          role: .button,
          label: "Apply"
        ),
      ]
    )

    let output = LinearAccessibilityRenderer().render(snapshot)

    #expect(
      output == """
          region: Settings
            button: Apply

        """
    )
  }

  @Test("renderer emits relevant controls without labels as role-only lines")
  func rendererEmitsRoleOnlyLinesForUnlabeledControls() {
    let buttonID = testIdentity("Button")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: buttonID,
          rect: rect(x: 0, y: 0, width: 8, height: 1),
          role: .button
        )
      ]
    )

    let output = LinearAccessibilityRenderer().render(snapshot)

    #expect(output == "button\n")
  }

  @Test("renderer keeps visible nodes and omits accessibility-hidden subtrees")
  func rendererOmitsAccessibilityHiddenSubtrees() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Secret")
          .accessibilityRole(.button)
          .accessibilityHidden()
        Text("Visible")
          .accessibilityRole(.button)
      },
      context: ResolveContext(identity: testIdentity("HiddenSubtreeRoot")),
      proposal: .init(width: 20, height: 4)
    )

    let output = LinearAccessibilityRenderer().render(artifacts.semanticSnapshot)

    #expect(output.contains("button: Visible"))
    #expect(!output.contains("Secret"))
  }

  @Test("renderer normalizes output to plain ASCII")
  func rendererNormalizesOutputToASCII() {
    let buttonID = testIdentity("Button")
    let snapshot = SemanticSnapshot(
      accessibilityNodes: [
        AccessibilityNode(
          identity: buttonID,
          rect: rect(x: 0, y: 0, width: 12, height: 1),
          role: .button,
          label: "Café\nSave",
          hint: "Uses ✓"
        )
      ]
    )

    let output = LinearAccessibilityRenderer().render(snapshot)

    #expect(output == "button: Caf? Save - Uses ?\n")
  }

  @Test("renderer includes accessibility warnings")
  func rendererIncludesAccessibilityWarnings() {
    let snapshot = SemanticSnapshot(
      accessibilityWarnings: [
        AccessibilityWarning(
          identity: testIdentity("Canvas"),
          kind: "Canvas",
          message:
            "Canvas omitted from accessibility output; add accessibilityLabel(...) or accessibilityHidden(true)."
        )
      ]
    )

    let output = LinearAccessibilityRenderer().render(snapshot)

    #expect(
      output
        == "warning: Canvas omitted from accessibility output; add accessibilityLabel(...) or accessibilityHidden(true).\n"
    )
  }

}

private func rect(
  x: Int,
  y: Int,
  width: Int,
  height: Int
) -> CellRect {
  CellRect(
    origin: CellPoint(x: x, y: y),
    size: CellSize(width: width, height: height)
  )
}
