import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUICharts
@testable import SwiftTUICore
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

  @Test("default chart summaries provide image accessibility labels")
  func defaultChartSummariesProvideImageAccessibilityLabels() {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Sparkline("Trend", values: [1, 3, 2])
        BarChart(
          "Queues",
          entries: [
            .init("api", value: 8),
            .init("jobs", value: 4),
          ]
        )
      },
      context: ResolveContext(identity: testIdentity("ChartAccessibilityRoot")),
      proposal: .init(width: 40, height: 8)
    )

    let output = LinearAccessibilityRenderer().render(artifacts.semanticSnapshot)

    #expect(output.contains("image: Trend: lo 1 hi 3"))
    #expect(output.contains("image: Queues: max 8"))
    #expect(!output.contains("warning:"))
  }

  @Test("custom chart content without accessibility label emits a warning")
  func customChartWithoutAccessibilityLabelEmitsWarning() {
    let artifacts = DefaultRenderer().render(
      Sparkline(
        values: [1, 3, 2],
        label: { Text("Trend") },
        summary: { EmptyView() }
      ),
      context: ResolveContext(identity: testIdentity("CustomChartAccessibilityRoot")),
      proposal: .init(width: 40, height: 4)
    )

    let output = LinearAccessibilityRenderer().render(artifacts.semanticSnapshot)

    #expect(
      output.contains(
        "warning: Sparkline omitted from accessibility output; add accessibilityLabel(...) or accessibilityHidden(true)."
      )
    )
    #expect(!output.contains("image:"))
  }

  @Test("accessible runtime writes linear output instead of presenting raster frames")
  func accessibleRuntimeWritesLinearOutputInsteadOfRasterFrames() async throws {
    let terminalSize = CellSize(width: 30, height: 8)
    let surface = LinearAccessibilityTestSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("AccessibleRuntimeRoot")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: LinearAccessibilityInputReader(events: [
        .key(KeyPress(.character("d"), modifiers: .ctrl))
      ]),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      runtimeConfiguration: RuntimeConfiguration(
        glyphs: .ascii,
        motion: .reduced,
        output: .accessible,
        noProgress: true,
        linear: true
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: ScopedMapper { _ in
        Button("Save") {}
          .id(testIdentity("AccessibleRuntimeButton"))
          .accessibilityLabel("Save")
      }
    )

    let result = try await runLoop.run()
    let output = surface.writes.joined()

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(!surface.didEnableRawMode)
    #expect(!surface.didDisableRawMode)
    #expect(surface.presentedSurfaces.isEmpty)
    #expect(output.contains("button: Save"))
    #expect(!output.contains("\u{001B}[2J"))
  }
}

private final class LinearAccessibilityTestSurface: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var didEnableRawMode = false
  private(set) var didDisableRawMode = false
  private(set) var writes: [String] = []
  private(set) var presentedSurfaces: [RasterSurface] = []

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {
    didEnableRawMode = true
  }

  func disableRawMode() throws {
    didDisableRawMode = true
  }

  func write(_ output: String) throws {
    writes.append(output)
  }

  func clearScreen() throws {}

  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    presentedSurfaces.append(surface)
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: surface.lines.count,
      cellsChanged: 0
    )
  }
}

private final class LinearAccessibilityInputReader: TerminalInputReading {
  private let scriptedEvents: [InputEvent]

  init(events: [InputEvent]) {
    scriptedEvents = events
  }

  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
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
