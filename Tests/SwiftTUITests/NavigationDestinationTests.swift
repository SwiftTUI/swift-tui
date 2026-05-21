import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct NavigationDestinationTests {
  @Test("NavigationStack renders root content when no destination is active")
  func rendersRootWhenInactive() {
    let surface = renderSurface(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(isPresented: .constant(false)) {
            Text("Destination")
          }
      }
    )

    #expect(surface.contains("Root"))
    #expect(!surface.contains("Destination"))
  }

  @Test("navigationDestination(isPresented:) renders the active destination")
  func booleanDestinationRendersWhenActive() {
    let surface = renderSurface(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(isPresented: .constant(true)) {
            Text("Destination")
          }
      }
    )

    #expect(!surface.contains("Root"))
    #expect(surface.contains("Destination"))
  }

  @Test("navigationDestination(item:) renders the active item destination")
  func itemDestinationRendersWhenActive() {
    let item = NavigationDestinationTestItem(id: "track-1", title: "Track 1")
    let surface = renderSurface(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(item: .constant(item)) { item in
            Text("Detail \(item.title)")
          }
      }
    )

    #expect(!surface.contains("Root"))
    #expect(surface.contains("Detail Track 1"))
  }

  @Test("multiple active destinations at one level render deterministically with last wins")
  func multipleActiveDestinationsUseLastWins() {
    let surface = renderSurface(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(isPresented: .constant(true)) {
            Text("First")
          }
          .navigationDestination(isPresented: .constant(true)) {
            Text("Second")
          }
      }
    )

    #expect(!surface.contains("Root"))
    #expect(!surface.contains("First"))
    #expect(surface.contains("Second"))
  }

  @Test("nested active destinations render the topmost destination")
  func nestedDestinationsRenderTopmost() {
    let surface = renderSurface(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(isPresented: .constant(true)) {
            Text("First")
              .navigationDestination(isPresented: .constant(true)) {
                Text("Second")
              }
          }
      }
    )

    #expect(!surface.contains("Root"))
    #expect(!surface.contains("First"))
    #expect(surface.contains("Second"))
  }

  @Test("destination pop action writes through the controlling binding")
  func popActionWritesBinding() throws {
    final class Box {
      var isPresented = true
    }

    let box = Box()
    let renderer = DefaultRenderer()
    let destinationButton = testIdentity("DestinationButton")
    let artifacts = renderer.render(
      NavigationStack(id: "stack") {
        Text("Root")
          .navigationDestination(
            isPresented: Binding(
              get: { box.isPresented },
              set: { box.isPresented = $0 }
            )
          ) {
            Button("Destination") {}
              .id(destinationButton)
          }
      },
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 6)
    )

    let scopePath = try #require(
      artifacts.semanticSnapshot.focusRegions.first { $0.identity == destinationButton }?
        .scopePath
    )
    let pop = try #require(
      renderer.topmostNavigationDestinationPopAction(along: scopePath)
    )

    pop()

    #expect(!box.isPresented)
  }

  @Test("Escape pops the active destination after modal presentations")
  func escapePopsAfterModalDismissal() throws {
    let (runLoop, host) = makeNavigationRunLoop {
      NavigationEscapeFixture()
    }

    try renderInitial(runLoop)
    #expect(surfaceText(host).contains("Sheet body"))
    #expect(surfaceText(host).contains("Destination"))

    _ = runLoop.handleKeyPress(KeyPress(.escape))
    try renderPending(runLoop)
    #expect(!surfaceText(host).contains("Sheet body"))
    #expect(surfaceText(host).contains("Destination"))
    #expect(!surfaceText(host).contains("Root"))

    _ = runLoop.handleKeyPress(KeyPress(.escape))
    try renderPending(runLoop)
    #expect(surfaceText(host).contains("Root"))
    #expect(!surfaceText(host).contains("Destination"))
  }
}

private struct NavigationDestinationTestItem: Identifiable, Sendable {
  var id: String
  var title: String
}

private struct NavigationEscapeFixture: View {
  @State private var isPresented = true
  @State private var isSheetPresented = true

  var body: some View {
    NavigationStack(id: "stack") {
      Text("Root")
        .navigationDestination(isPresented: $isPresented) {
          Button("Destination") {}
            .id(testIdentity("DestinationButton"))
            .sheet("Sheet", isPresented: $isSheetPresented) {
              Text("Sheet body")
            }
        }
    }
  }
}

@MainActor
private func renderSurface<V: View>(_ view: V) -> String {
  DefaultRenderer().render(
    view,
    context: .init(identity: testIdentity("Root")),
    proposal: .init(width: 40, height: 6)
  ).rasterSurface.lines.joined(separator: "\n")
}

@MainActor
private func makeNavigationRunLoop<V: View>(
  terminalSize: CellSize = .init(width: 40, height: 8),
  @ViewBuilder content: @escaping () -> V
) -> (runLoop: RunLoop<Int, V>, host: NavigationDestinationTerminalHost) {
  let host = NavigationDestinationTerminalHost(surfaceSizeProvider: { terminalSize })
  let rootIdentity = testIdentity("NavigationRuntimeRoot")
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: host,
    terminalInputReader: InjectedTerminalInputReader(),
    scheduler: FrameScheduler(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    environmentValues: .init(),
    proposal: .init(width: terminalSize.width, height: terminalSize.height),
    viewBuilder: { _, _ in content() }
  )
  runLoop.focusTracker.invalidator = runLoop.scheduler
  return (runLoop, host)
}

@MainActor
private func renderInitial<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  runLoop.scheduler.requestInvalidation(of: [runLoop.rootIdentity])
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  runLoop.renderer.enableSelectiveEvaluation()
}

@MainActor
private func renderPending<State, V: View>(_ runLoop: RunLoop<State, V>) throws {
  var renderedFrames = 0
  try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
}

@MainActor
private func surfaceText(_ host: NavigationDestinationTerminalHost) -> String {
  host.latestSurface?.lines.joined(separator: "\n") ?? ""
}

private final class NavigationDestinationTerminalHost: PresentationSurface {
  var surfaceSize: CellSize { surfaceSizeProvider() }
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  var graphicsCapabilities: TerminalGraphicsCapabilities { .init() }
  var theme: Theme? { nil }
  private(set) var latestSurface: RasterSurface?
  private let surfaceSizeProvider: () -> CellSize

  init(
    surfaceSizeProvider: @escaping () -> CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSizeProvider = surfaceSizeProvider
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func write(_: String) throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}
  func setPointerHoverEnabled(_: Bool) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    latestSurface = surface
    return TerminalPresentationMetrics(
      bytesWritten: surface.size.width * surface.size.height,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }
}

extension NavigationDestinationTerminalHost: DamageAwarePresentationSurface {
  @discardableResult
  func present(
    _ surface: RasterSurface,
    damage _: PresentationDamage?
  ) throws -> TerminalPresentationMetrics {
    try present(surface)
  }
}
