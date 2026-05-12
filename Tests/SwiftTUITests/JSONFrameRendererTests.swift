import Foundation
import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite
struct JSONFrameRendererTests {
  @Test("renderer emits machine-readable frame JSON")
  func rendererEmitsMachineReadableFrameJSON() throws {
    let buttonID = testIdentity("JSONButton")
    let output = JSONFrameRenderer().render(
      surface: RasterSurface(
        size: CellSize(width: 12, height: 2),
        lines: ["Save"]
      ),
      semanticSnapshot: SemanticSnapshot(
        accessibilityNodes: [
          AccessibilityNode(
            identity: buttonID,
            rect: rect(x: 0, y: 0, width: 4, height: 1),
            role: .button,
            label: "Save",
            cursorAnchor: CellPoint(x: 0, y: 0)
          )
        ],
        accessibilityAnnouncements: [
          AccessibilityAnnouncement(message: "Saved", politeness: .polite)
        ]
      ),
      focusedIdentity: buttonID
    )

    let object = try decodeJSONObject(output)
    #expect(object["type"] as? String == "frame")
    #expect((object["rows"] as? [String]) == ["Save", ""])

    let nodes = try #require(object["accessibilityNodes"] as? [[String: Any]])
    let node = try #require(nodes.first)
    #expect(node["id"] as? String == buttonID.path)
    #expect(node["role"] as? String == "button")
    #expect(node["label"] as? String == "Save")
    #expect(node["focused"] as? Bool == true)

    let announcements = try #require(object["accessibilityAnnouncements"] as? [[String: Any]])
    #expect(announcements.first?["message"] as? String == "Saved")
    #expect(announcements.first?["politeness"] as? String == "polite")
  }

  @Test("JSON runtime writes JSON output instead of presenting raster frames")
  func jsonRuntimeWritesJSONOutputInsteadOfRasterFrames() async throws {
    let terminalSize = CellSize(width: 30, height: 8)
    let surface = JSONRuntimeTestSurface(surfaceSize: terminalSize)
    let rootIdentity = testIdentity("JSONRuntimeRoot")
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: surface,
      terminalInputReader: JSONRuntimeInputReader(events: [
        .key(KeyPress(.character("d"), modifiers: .ctrl))
      ]),
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      runtimeConfiguration: RuntimeConfiguration(output: .json),
      proposal: .init(width: terminalSize.width, height: terminalSize.height),
      viewBuilder: ScopedMapper { _ in
        Button("Save") {}
          .id(testIdentity("JSONRuntimeButton"))
          .accessibilityLabel("Save")
      }
    )

    let result = try await runLoop.run()
    let output = surface.writes.joined()
    let object = try decodeJSONObject(output)

    #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
    #expect(!surface.didEnableRawMode)
    #expect(!surface.didDisableRawMode)
    #expect(surface.presentedSurfaces.isEmpty)
    #expect(object["type"] as? String == "frame")
    #expect(
      (object["accessibilityNodes"] as? [[String: Any]])?.first?["role"] as? String == "button")
    #expect(output.contains("\"rows\""))
    #expect(!output.contains("button: Save"))
    #expect(!output.contains("\u{001B}[2J"))
  }
}

private final class JSONRuntimeTestSurface: PresentationSurface {
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

private final class JSONRuntimeInputReader: TerminalInputReading {
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

private func decodeJSONObject(
  _ output: String
) throws -> [String: Any] {
  let data = Data(output.utf8)
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
