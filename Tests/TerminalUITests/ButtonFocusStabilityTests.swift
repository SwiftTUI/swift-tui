import Foundation
import Testing

@_spi(Testing) @testable import Core
@testable import TerminalUI
@testable import View

// Regression tests for calculator-driven framework bugs:
//   1. Plain Button bounds must not shift when focus arrives — otherwise
//      a mouseDown-followed-by-mouseUp on the same pointer location
//      misses the armed route and the action never dispatches.
//   2. `.fixedSize()` on a VStack must still reconcile inner flexible
//      rows (Spacer, frame(maxWidth:.infinity)) against the widest
//      sibling's ideal cross, so right-aligned display text and
//      bottom-row spacer distribution work.
//   3. An action closure that captures `self` from an outer view (e.g.
//      a CalculatorTab whose buttons live inside a custom
//      `CalculatorButton` wrapper) must mutate that outer view's @State
//      when the button is clicked — not the wrapper view's state slot.

@MainActor
@Suite
struct ButtonFocusStabilityTests {
  @Test("plain Button bounds stay stable across focus transitions")
  func plainButtonFocusDoesNotShiftBounds() throws {
    let size = CellSize(width: 20, height: 3)
    let rootIdentity = testIdentity("PlainButtonFocus")

    func render(focus: Identity?) -> FrameArtifacts {
      var env = EnvironmentValues()
      env.terminalSize = size
      env.focusedIdentity = focus
      return DefaultRenderer().render(
        HStack(spacing: 1) {
          Button(action: {}) {
            Text("AC").frame(minWidth: 5, maxWidth: 5)
          }
          .buttonStyle(.plain)
          Button(action: {}) {
            Text("OK").frame(minWidth: 5, maxWidth: 5)
          }
          .buttonStyle(.plain)
        },
        context: .init(identity: rootIdentity, environmentValues: env),
        proposal: .init(width: size.width, height: size.height)
      )
    }

    let unfocused = render(focus: nil)
    let firstButtonIdentity = try #require(
      unfocused.semanticSnapshot.interactionRegions.first?.identity
    )
    let firstButtonRect = try #require(
      unfocused.semanticSnapshot.interactionRegions.first?.rect
    )

    let focused = render(focus: firstButtonIdentity)
    let focusedFirstButtonRect =
      focused.semanticSnapshot.interactionRegions.first {
        $0.identity == firstButtonIdentity
      }?.rect

    #expect(firstButtonRect == focusedFirstButtonRect)
  }

  @Test("click on a plain Button wrapped by a custom view updates the outer view's @State")
  func plainButtonInsideWrapperMutatesOwnerState() async throws {
    let terminalSize = CellSize(width: 20, height: 3)
    let rootIdentity = testIdentity("WrappedButtonStateRepro")
    let tapCount = LockedBox<Int>(0)

    // Button lives inside a custom View wrapper (`WrapperButton`) and
    // its action closure captures `self` from the outer `Fixture`
    // view. If the framework routes the @State mutation through the
    // wrapper's authoring scope instead of the owning view's, the
    // setter writes to the wrapper's state slot and the display stays
    // at "A". With the fix the display must flip to "B" after the
    // click and the tap count must reach 1.
    struct WrapperButton: View {
      let action: @MainActor @Sendable () -> Void
      var body: some View {
        Button(action: action) {
          Text("Go")
            .frame(minWidth: 5, maxWidth: 5)
            .background { Rectangle().fill(Color.gray) }
        }
        .buttonStyle(.plain)
      }
    }

    struct Fixture: View {
      let tapCount: LockedBox<Int>
      @State private var value: String = "A"
      var body: some View {
        VStack {
          Text("v=\(value)")
          WrapperButton(action: { setValue() })
        }
      }
      private func setValue() {
        tapCount.value += 1
        value = "B"
      }
    }

    let view = Fixture(tapCount: tapCount)

    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let initial = DefaultRenderer().render(
      view,
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )
    let goNode = try #require(
      initial.placedTree.flattenedDescendants.first { node in
        if case .text("Go") = node.drawPayload { return true }
        return false
      }
    )
    let center = Point(CellPoint(x: goNode.bounds.origin.x, y: goNode.bounds.origin.y))

    let host = RecordingTerminalHostLocal(size: terminalSize)
    _ = try await Self.runHarness(
      host: host,
      events: [
        .mouse(.init(kind: .down(.primary), location: center)),
        .mouse(.init(kind: .up(.primary), location: center)),
      ],
      rootIdentity: rootIdentity,
      terminalSize: terminalSize
    ) {
      view
    }

    let finalSurface = try #require(host.lastPresentedSurface)
    #expect(tapCount.value == 1, "action closure should have fired")
    #expect(finalSurface.lines.contains(where: { $0.contains("v=B") }), "display should show v=B")
    #expect(
      !finalSurface.lines.contains(where: { $0.contains("v=A") }),
      "display should not still show v=A")
  }

  @Test("fixedSize VStack reconciles inner row Spacer against widest sibling")
  func fixedSizeReconcilesInnerRowSpacer() throws {
    let size = CellSize(width: 40, height: 10)
    let rootIdentity = testIdentity("FixedSizeSpacer")
    var env = EnvironmentValues()
    env.terminalSize = size

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("abcdefghij")  // 10 wide
        HStack(spacing: 0) {
          Text("L")
          Spacer()
          Text("R")
        }
      }
      .fixedSize(),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: size.width, height: size.height)
    )

    let placed = artifacts.placedTree
    let rows = placed.flattenedDescendants
      .filter { $0.kind == .view("HStack") }
    let innerRow = try #require(rows.first)
    #expect(innerRow.bounds.size.width == 10)

    let texts = innerRow.flattenedDescendants.filter {
      if case .text = $0.drawPayload { return true }
      return false
    }
    let leftText = try #require(
      texts.first { node in
        if case .text(let content) = node.drawPayload { return content == "L" }
        return false
      })
    let rightText = try #require(
      texts.first { node in
        if case .text(let content) = node.drawPayload { return content == "R" }
        return false
      })
    #expect(leftText.bounds.origin.x == innerRow.bounds.origin.x)
    #expect(
      rightText.bounds.origin.x + rightText.bounds.size.width
        == innerRow.bounds.origin.x + innerRow.bounds.size.width
    )
  }

  @Test("horizontally fixed VStack reconciles cross width under finite height proposal")
  func horizontallyFixedVStackReconcilesCrossWidthWithFiniteMainProposal() throws {
    let size = CellSize(width: 40, height: 10)
    let rootIdentity = testIdentity("HorizontallyFixedSpacer")
    var env = EnvironmentValues()
    env.terminalSize = size

    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("abcdefghij")  // 10 wide
        HStack(spacing: 0) {
          Text("L")
          Spacer()
          Text("R")
        }
      }
      .fixedSize(horizontal: true, vertical: false),
      context: .init(identity: rootIdentity, environmentValues: env),
      proposal: .init(width: size.width, height: size.height)
    )

    let innerRow = try #require(
      artifacts.placedTree.flattenedDescendants.first { $0.kind == .view("HStack") }
    )
    #expect(innerRow.bounds.size.width == 10)

    let texts = innerRow.flattenedDescendants.filter {
      if case .text = $0.drawPayload { return true }
      return false
    }
    let rightText = try #require(
      texts.first { node in
        if case .text(let content) = node.drawPayload { return content == "R" }
        return false
      })
    #expect(
      rightText.bounds.origin.x + rightText.bounds.size.width
        == innerRow.bounds.origin.x + innerRow.bounds.size.width
    )
  }

  // MARK: - Harness plumbing

  @MainActor
  private static func runHarness<V: View>(
    host: RecordingTerminalHostLocal,
    events: [InputEvent],
    rootIdentity: Identity,
    terminalSize: CellSize,
    viewBuilder: @escaping () -> V
  ) async throws -> RunLoopResult<Int> {
    var env = EnvironmentValues()
    env.terminalSize = terminalSize
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      terminalHost: host,
      terminalInputReader: LocalScriptedInput(events: events),
      signalReader: LocalEmptySignals(),
      scheduler: FrameScheduler(),
      stateContainer: StateContainer(
        initialState: 0,
        invalidationIdentities: [rootIdentity]
      ),
      focusTracker: FocusTracker(
        invalidationIdentities: [rootIdentity]
      ),
      environmentValues: env,
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: { _, _ in viewBuilder() }
    )
    return try await runLoop.run()
  }
}

private final class LocalScriptedInput: TerminalInputReading {
  private let scriptedEvents: [InputEvent]
  init(events: [InputEvent]) { self.scriptedEvents = events }
  func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      for event in scriptedEvents {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private final class LocalEmptySignals: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}

private final class RecordingTerminalHostLocal: TerminalHosting {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: CellSize) { self.surfaceSize = size }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    lastPresentedSurface = surface
    return .init(bytesWritten: 0, linesTouched: 0, cellsChanged: 0, strategy: .fullRepaint)
  }
}

extension PlacedNode {
  fileprivate var flattenedDescendants: [PlacedNode] {
    var result: [PlacedNode] = []
    collectDescendants(into: &result)
    return result
  }

  private func collectDescendants(into result: inout [PlacedNode]) {
    result.append(self)
    for child in children {
      child.collectDescendants(into: &result)
    }
  }
}
