import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

// Regression: CounterTab in the gallery demo crashed on tap of its
// `-` / `+` buttons after `.command { }` + `.toolbar { }` were added
// to the body.  Commit 112d98f introduced the chrome, the demo was
// reverted in 076d3e3, and this suite was added when re-landing so
// the fix can never silently regress.

@MainActor
@Suite
struct ToolbarHostButtonCrashTests {
  @Test("tapping a Button inside a .toolbar + .command host mutates the owner @State")
  func tapMathButtonInsideToolbarHost() async throws {
    let terminalSize = Size(width: 60, height: 10)
    let rootIdentity = testIdentity("ToolbarHostButtonCrash")
    let tapCount = LockedBox<Int>(0)

    // Mirrors the gallery CounterTab exactly: a TabView wrapper (so
    // there's a TabView/ResolvedContentView layer above the tab
    // content), plus a scene-level `.help()` + `.helpSheet()` on the
    // outer view just like `GalleryDemoApp`. The tab body itself uses
    // `.command { }` and `.toolbar { }`, same as CounterTab.
    struct Counter: View {
      let tapCount: LockedBox<Int>
      @State private var count: Int = 0
      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text("n=\(count)")
          Button("plus") {
            withAnimation(.default) {
              tapCount.value += 1
              count += 1
            }
          }
          .buttonStyle(.plain)
        }
        .command(
          id: "increment",
          title: "Increment",
          key: KeyPress(.character("+")),
          group: "Counter"
        ) {
          withAnimation(.default) {
            tapCount.value += 1
            count += 1
          }
        }
        .command(
          id: "reset-counter",
          title: "Reset",
          key: .ctrl("r"),
          group: "Counter"
        ) {
          count = 0
        }
        .toolbar {
          ToolbarItem(placement: .status) {
            Text("Count: \(count)")
          }
          ToolbarItem(.primaryAction, command: "reset-counter")
        }
      }
    }

    struct Fixture: View {
      let tapCount: LockedBox<Int>
      @State private var selection: Int = 0
      var body: some View {
        TabView(selection: $selection) {
          Counter(tapCount: tapCount)
            .tabItem("Counter")
            .tag(0)
        }
        .tabViewStyle(.literalTabs)
        .help()
        .helpSheet()
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
    let plusNode = try #require(
      initial.placedTree.flattenedDescendants.first { node in
        if case .text("plus") = node.drawPayload { return true }
        return false
      },
      "Fixture should have rendered a Button labeled 'plus'"
    )
    let center = Point(x: plusNode.bounds.origin.x, y: plusNode.bounds.origin.y)

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
    #expect(
      finalSurface.lines.contains(where: { $0.contains("n=1") }),
      "display should show n=1 after tap")
  }

  // MARK: - Harness plumbing (mirrors ButtonFocusStabilityTests)

  @MainActor
  private static func runHarness<V: View>(
    host: RecordingTerminalHostLocal,
    events: [InputEvent],
    rootIdentity: Identity,
    terminalSize: Size,
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
  let surfaceSize: Size
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var lastPresentedSurface: RasterSurface?

  init(size: Size) { self.surfaceSize = size }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: Point) throws {}

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
