import Testing
import TerminalUI
@testable import SwiftUITUIGUI

@MainActor
private final class FakeSceneSession: HostedSceneSessionHandling {
  var startCount = 0
  var stopCount = 0
  var receivedResizes: [Size] = []
  var receivedAppearances: [TerminalAppearance] = []

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

  func updateAppearance(_ appearance: TerminalAppearance) {
    receivedAppearances.append(appearance)
  }

  func stop() {
    stopCount += 1
  }
}

@MainActor
@Test
func bridge_forwards_resize_and_appearance_updates() async throws {
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
  #expect(session.receivedAppearances.last?.colorScheme == .dark)

  bridge.stopSession()
  #expect(session.stopCount == 1)
}
