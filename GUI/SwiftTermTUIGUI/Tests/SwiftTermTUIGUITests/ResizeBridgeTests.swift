import TerminalUI
import Testing

@testable import SwiftTermTUIGUI

@MainActor
private final class FakeSceneSession: HostedSceneSessionHandling {
  var startCount = 0
  var stopCount = 0
  var receivedResizes: [Size] = []
  var receivedStyles: [TerminalRenderStyle] = []

  func start() async throws -> RunLoopExitReason {
    startCount += 1
    return .inputEnded
  }

  func sendInput(_ bytes: [UInt8]) {
    _ = bytes
  }

  func resize(to size: Size) {
    receivedResizes.append(size)
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
  let style = SwiftTermTUITerminalStyle.default
  let bridge = SwiftTermSceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: style
  )
  let session = FakeSceneSession()

  bridge.attach(session: session)

  _ = try await bridge.startSession()
  #expect(session.startCount == 1)

  bridge.handleSurfaceResize(columns: 120, rows: 40)
  #expect(session.receivedResizes == [.init(width: 120, height: 40)])
  #expect(session.receivedStyles.last == style.renderStyle)

  let swappedStyle = SwiftTermTUITerminalStyle(
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
func bridge_tracks_keyboard_policy_from_focus_presentation() {
  let style = SwiftTermTUITerminalStyle.default
  let bridge = SwiftTermSceneBridge(
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
