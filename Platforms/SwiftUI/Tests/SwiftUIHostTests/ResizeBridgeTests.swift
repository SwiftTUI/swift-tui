import CoreGraphics
import SwiftTUI
import Testing

@testable import SwiftUIHost

@MainActor
private final class FakeSceneSession: HostedSceneSessionHandling {
  var startCount = 0
  var stopCount = 0
  var refreshCount = 0
  var receivedEvents: [InputEvent] = []

  func start() async throws -> RunLoopExitReason {
    startCount += 1
    return .inputEnded
  }

  func send(_ event: InputEvent) {
    receivedEvents.append(event)
  }

  func requestSurfaceRefresh() {
    refreshCount += 1
  }

  func stop() {
    stopCount += 1
  }
}

@MainActor
@Test
func bridge_forwards_resize_and_style_updates() async throws {
  let style = SwiftUIHostTerminalStyle.default
  let bridge = NativeSceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: style
  )
  let session = FakeSceneSession()
  let surface = HostedRasterSurface(
    surfaceSize: .init(width: 80, height: 24),
    appearance: style.renderStyle.appearance,
    theme: style.renderStyle.theme,
    onFrame: { _ in }
  )

  bridge.attach(session: session, surface: surface)

  _ = try await bridge.startSession()
  #expect(session.startCount == 1)
  #expect(session.refreshCount == 1)

  bridge.resize(
    to: .init(width: 120, height: 40),
    cellPixelSize: .init(width: 8, height: 16)
  )
  #expect(surface.surfaceSize == .init(width: 120, height: 40))
  #expect(surface.graphicsCapabilities.cellPixelSize == .init(width: 8, height: 16))
  #expect(
    surface.pointerInputCapabilities
      == PointerInputCapabilities(
        precision: .subCell(
          source: .nativePixels,
          metrics: .init(width: 8, height: 16, source: .reported)
        ),
        supportsHover: true
      ))
  #expect(session.refreshCount == 2)

  bridge.send(.key(.init(.character("x"))))
  #expect(session.receivedEvents == [.key(.init(.character("x")))])

  #expect(surface.appearance == style.renderStyle.appearance)
  #expect(surface.theme == style.renderStyle.theme)

  let swappedStyle = SwiftUIHostTerminalStyle(
    palette: .init(
      foreground: try! .hex("#5A5B5C"),
      background: try! .hex("#6A6B6C"),
      cursor: try! .hex("#7A7B7C"),
      selectionBackground: try! .hex("#8A8B8C"),
      selectionForeground: try! .hex("#9A9B9C"),
      ansi: .default
    ),
    theme: Theme(
      foreground: try! .hex("#5A5B5C"),
      background: try! .hex("#6A6B6C"),
      tint: try! .hex("#7A7B7C")
    )
  )

  bridge.apply(style: swappedStyle)
  #expect(surface.appearance.foregroundColor == (try! .hex("#5A5B5C")))
  #expect(surface.appearance.backgroundColor == (try! .hex("#6A6B6C")))
  #expect(surface.theme == swappedStyle.theme)
  #expect(session.refreshCount == 3)

  bridge.stopSession()
  #expect(session.stopCount == 1)
}

@MainActor
@Test
func bridge_forwards_pointer_events_in_order() {
  let bridge = NativeSceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: .default
  )
  let session = FakeSceneSession()
  let surface = HostedRasterSurface(
    surfaceSize: .init(width: 80, height: 24),
    appearance: .fallback,
    onFrame: { _ in }
  )
  let location = Point(x: 4, y: 2)

  bridge.attach(session: session, surface: surface)
  bridge.send(.mouse(.init(kind: .down(.primary), location: location)))
  bridge.send(.mouse(.init(kind: .dragged(.primary), location: .init(x: 5, y: 2))))
  bridge.send(.mouse(.init(kind: .up(.primary), location: .init(x: 5, y: 2))))
  bridge.send(.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: location)))

  #expect(
    session.receivedEvents == [
      .mouse(.init(kind: .down(.primary), location: location)),
      .mouse(.init(kind: .dragged(.primary), location: .init(x: 5, y: 2))),
      .mouse(.init(kind: .up(.primary), location: .init(x: 5, y: 2))),
      .mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: location)),
    ])
}

@MainActor
@Test
func bridge_tracks_keyboard_policy_from_focus_presentation() {
  let style = SwiftUIHostTerminalStyle.default
  let bridge = NativeSceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: style
  )

  bridge.updateKeyboardPresentation(
    focusPresentation: .init(
      focusedIdentity: Identity(components: ["activate"]),
      semantics: .activate
    ),
    manualKeyboardPresentationRequested: false
  )
  #expect(bridge.focusPresentationForTesting.semantics == .activate)
  #expect(bridge.allowsExpandedKeyboardPresentationForTesting == false)

  bridge.updateKeyboardPresentation(
    focusPresentation: .init(
      focusedIdentity: Identity(components: ["activate"]),
      semantics: .activate
    ),
    manualKeyboardPresentationRequested: true
  )
  #expect(bridge.allowsExpandedKeyboardPresentationForTesting)

  bridge.updateKeyboardPresentation(
    focusPresentation: .init(
      focusedIdentity: Identity(components: ["field"]),
      semantics: .edit
    ),
    manualKeyboardPresentationRequested: false
  )
  #expect(bridge.focusPresentationForTesting.semantics == .edit)
  #expect(bridge.allowsExpandedKeyboardPresentationForTesting)
}

@MainActor
@Test
func native_surface_sizing_prefers_measured_grid_over_available_space() {
  let metrics = NativeTerminalMetrics(style: .default)
  let negotiator = NativeTerminalSurfaceSizeNegotiator(
    cellSize: metrics.cellSize,
    preferredGridSize: .init(width: 12, height: 3),
    renderedGridSize: .init(width: 80, height: 24)
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: metrics.cellSize.width * 80,
    proposedHeight: metrics.cellSize.height * 24
  )

  #expect(negotiated.width == metrics.cellSize.width * 12)
  #expect(negotiated.height == metrics.cellSize.height * 3)
}

@MainActor
@Test
func native_surface_sizing_snaps_finite_proposals_to_cell_blocks() {
  let metrics = NativeTerminalMetrics(style: .default)
  let negotiator = NativeTerminalSurfaceSizeNegotiator(
    cellSize: metrics.cellSize,
    preferredGridSize: .init(width: 12, height: 3),
    renderedGridSize: .init(width: 80, height: 24)
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: metrics.cellSize.width * 5.75,
    proposedHeight: nil
  )

  #expect(negotiated.width == metrics.cellSize.width * 5)
  #expect(negotiated.height == metrics.cellSize.height * 3)
}

@MainActor
@Test
func native_surface_sizing_probes_growth_without_returning_full_parent_proposal() {
  let metrics = NativeTerminalMetrics(style: .default)
  let negotiator = NativeTerminalSurfaceSizeNegotiator(
    cellSize: metrics.cellSize,
    preferredGridSize: .init(width: 5, height: 3),
    renderedGridSize: .init(width: 5, height: 3)
  )

  let negotiated = negotiator.negotiate(
    proposedWidth: metrics.cellSize.width * 12,
    proposedHeight: metrics.cellSize.height * 6
  )

  #expect(negotiated.size.width == metrics.cellSize.width * 5)
  #expect(negotiated.size.height == metrics.cellSize.height * 3)
  #expect(negotiated.probeGridSize == .init(width: 12, height: 6))
}

@MainActor
@Test
func native_surface_sizing_remembers_confirmed_slack_after_growth_probe() {
  let metrics = NativeTerminalMetrics(style: .default)
  var confirmedSlack = NativeTerminalSurfaceConfirmedSlack()
  confirmedSlack.update(
    preferredGridSize: .init(width: 7, height: 1),
    renderedGridSize: .init(width: 12, height: 6)
  )
  let negotiator = NativeTerminalSurfaceSizeNegotiator(
    cellSize: metrics.cellSize,
    preferredGridSize: .init(width: 7, height: 1),
    renderedGridSize: .init(width: 7, height: 1),
    confirmedSlack: confirmedSlack
  )

  let negotiated = negotiator.sizeThatFits(
    proposedWidth: metrics.cellSize.width * 12,
    proposedHeight: metrics.cellSize.height * 6
  )

  #expect(negotiated.width == metrics.cellSize.width * 7)
  #expect(negotiated.height == metrics.cellSize.height * 1)
}
