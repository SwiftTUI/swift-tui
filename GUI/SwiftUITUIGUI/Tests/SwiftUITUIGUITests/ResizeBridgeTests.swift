import TerminalUI
import Testing

@testable import SwiftUITUIGUI

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
  let style = SwiftUITUITerminalStyle.default
  let bridge = GhosttySceneBridge(
    descriptor: .init(id: "dashboard", title: "Dashboard", isDefault: true),
    style: style
  )
  let session = FakeSceneSession()

  bridge.attach(session: session)

  _ = try await bridge.startSession()
  #expect(session.startCount == 1)

  bridge.handleSurfaceResize(
    .init(
      columns: 120,
      rows: 40,
      widthPixels: 960,
      heightPixels: 640,
      cellWidthPixels: 8,
      cellHeightPixels: 16
    )
  )
  #expect(session.receivedResizes == [.init(width: 120, height: 40)])

  bridge.updateAppearance(.dark)
  #expect(session.receivedStyles.last?.appearance.colorScheme == .dark)
  #expect(session.receivedStyles.last?.theme == style.theme(for: .dark))

  let swappedStyle = SwiftUITUITerminalStyle(
    lightVariant: .init(
      palette: .init(
        foreground: "#0A0B0C",
        background: "#1A1B1C",
        cursor: "#2A2B2C",
        selectionBackground: "#3A3B3C",
        selectionForeground: "#4A4B4C",
        ansiColors: SwiftUITUITerminalPalette.defaultLight.ansiColors
      ),
      theme: ThemeColors(
        foreground: .hex("#0A0B0C"),
        background: .hex("#1A1B1C"),
        tint: .hex("#2A2B2C")
      )
    ),
    darkVariant: .init(
      palette: .init(
        foreground: "#5A5B5C",
        background: "#6A6B6C",
        cursor: "#7A7B7C",
        selectionBackground: "#8A8B8C",
        selectionForeground: "#9A9B9C",
        ansiColors: SwiftUITUITerminalPalette.defaultDark.ansiColors
      ),
      theme: ThemeColors(
        foreground: .hex("#5A5B5C"),
        background: .hex("#6A6B6C"),
        tint: .hex("#7A7B7C")
      )
    )
  )

  bridge.apply(style: swappedStyle)
  #expect(session.receivedStyles.last?.appearance.foregroundColor == .hex("#5A5B5C"))
  #expect(session.receivedStyles.last?.appearance.backgroundColor == .hex("#6A6B6C"))
  #expect(session.receivedStyles.last?.theme == swappedStyle.theme(for: .dark))

  bridge.stopSession()
  #expect(session.stopCount == 1)
}
