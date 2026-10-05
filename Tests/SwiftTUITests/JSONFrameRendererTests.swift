import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
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

  @Test("JSON escapes terminal control scalars without changing decoded strings")
  func terminalControlsRoundTrip() throws {
    let text = "before\u{7F}\u{85}\u{9B}\u{9C}\u{9D}after界"
    let identity = testIdentity("Controls")
    let output = JSONFrameRenderer().render(
      surface: RasterSurface(size: .init(width: 80, height: 1), lines: [text]),
      semanticSnapshot: SemanticSnapshot(
        accessibilityNodes: [
          AccessibilityNode(
            identity: identity, rect: rect(x: 0, y: 0, width: 10, height: 1),
            role: .group, label: text, hint: text)
        ],
        accessibilityAnnouncements: [.init(message: text, politeness: .polite)],
        accessibilityWarnings: [.init(identity: identity, kind: text, message: text)]),
      focusedIdentity: nil)
    #expect(!output.unicodeScalars.contains { (0x7F...0x9F).contains($0.value) })
    for escape in ["\\u007F", "\\u0085", "\\u009B", "\\u009C", "\\u009D"] {
      #expect(output.contains(escape))
    }
    let object = try decodeJSONObject(output)
    #expect(object["rows"] as? [String] == [text])
    let node = try #require((object["accessibilityNodes"] as? [[String: Any]])?.first)
    #expect(node["label"] as? String == text)
    #expect(node["hint"] as? String == text)
    let announcement = try #require(
      (object["accessibilityAnnouncements"] as? [[String: Any]])?.first)
    #expect(announcement["message"] as? String == text)
    let warning = try #require((object["accessibilityWarnings"] as? [[String: Any]])?.first)
    #expect(warning["kind"] as? String == text)
    #expect(warning["message"] as? String == text)
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
        .key(KeyPress(.character("c"), modifiers: .ctrl))
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

    #expect(result.exitReason == .userExit(KeyPress(.character("c"), modifiers: .ctrl)))
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
