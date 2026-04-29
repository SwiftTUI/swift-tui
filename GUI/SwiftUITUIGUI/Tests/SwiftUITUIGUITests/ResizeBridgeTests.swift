import TerminalUI
import Testing

@testable import SwiftUITUIGUI

@MainActor
private final class FakeSceneSession: HostedSceneSessionHandling {
  var startCount = 0
  var stopCount = 0
  var receivedResizes: [(size: CellSize, cellPixelSize: PixelSize?)] = []
  var receivedStyles: [TerminalRenderStyle] = []
  var receivedEvents: [InputEvent] = []

  func start() async throws -> RunLoopExitReason {
    startCount += 1
    return .inputEnded
  }

  func send(_ event: InputEvent) {
    receivedEvents.append(event)
  }

  func resize(to size: CellSize, cellPixelSize: PixelSize?) {
    receivedResizes.append((size, cellPixelSize))
  }

  func updateStyle(_ style: TerminalRenderStyle) {
    receivedStyles.append(style)
  }

  func stop() {
    stopCount += 1
  }
}

@MainActor
@Test
func bridge_forwards_resize_and_style_updates() async throws {
  let style = SwiftUITUITerminalStyle.default
  let bridge = NativeSceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: style
  )
  let session = FakeSceneSession()

  bridge.attach(session: session)

  _ = try await bridge.startSession()
  #expect(session.startCount == 1)

  bridge.resize(
    to: .init(width: 120, height: 40),
    cellPixelSize: .init(width: 8, height: 16)
  )
  #expect(session.receivedResizes.map(\.size) == [.init(width: 120, height: 40)])
  #expect(session.receivedResizes.map(\.cellPixelSize) == [.init(width: 8, height: 16)])

  bridge.send(.key(.init(.character("x"))))
  #expect(session.receivedEvents == [.key(.init(.character("x")))])

  #expect(session.receivedStyles.last == style.renderStyle)

  let swappedStyle = SwiftUITUITerminalStyle(
    palette: .init(
      foreground: .hex("#5A5B5C"),
      background: .hex("#6A6B6C"),
      cursor: .hex("#7A7B7C"),
      selectionBackground: .hex("#8A8B8C"),
      selectionForeground: .hex("#9A9B9C"),
      ansi: .default
    ),
    theme: Theme(
      foreground: .hex("#5A5B5C"),
      background: .hex("#6A6B6C"),
      tint: .hex("#7A7B7C")
    )
  )

  bridge.apply(style: swappedStyle)
  #expect(session.receivedStyles.last?.appearance.foregroundColor == .hex("#5A5B5C"))
  #expect(session.receivedStyles.last?.appearance.backgroundColor == .hex("#6A6B6C"))
  #expect(session.receivedStyles.last?.theme == swappedStyle.theme)

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
  let location = Point(x: 4, y: 2)

  bridge.attach(session: session)
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
  let style = SwiftUITUITerminalStyle.default
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
