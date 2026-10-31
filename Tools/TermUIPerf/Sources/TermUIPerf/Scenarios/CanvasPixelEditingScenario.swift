@_spi(Runners) import SwiftTUI

/// Fixed-viewport pixel editing, with a separate cursor canvas as in a pixel editor.
/// Unlike canvas-partial-reuse, these events change the canvas itself.
public struct CanvasPixelEditingScenario: PerfScenario {
  public enum Edit: Sendable {
    case cursor, pixel, frame
  }

  public let edit: Edit

  public init(edit: Edit) {
    self.edit = edit
  }

  public var name: PerfScenarioName {
    switch edit {
    case .cursor: .canvasPixelCursor
    case .pixel: .canvasPixelStroke
    case .frame: .canvasPixelFrame
    }
  }
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 24)
  public let scriptedEvents = ["eight canvas edits, each followed by its numbered presentation"]
  public let visualMarkers = ["canvas edit 0"]
  public let settlingDescription = "the exact numbered frame after each canvas edit"

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(scenario: self, options: options) {
      PixelEditingView(edit: edit)
    } drive: { driver in
      var previous = try await driver.waitForFrame(containing: "canvas edit 0").frameNumber
      let button = try driver.cell(containing: "edit canvas")
      var events: [PerfEventRecord] = []
      for pass in 1...8 {
        let dispatched = monotonicSeconds()
        driver.sendClick(at: button)
        let marker = "canvas edit \(pass)"
        let frame = try await driver.waitForFrame(containing: marker, afterFrame: previous)
        previous = frame.frameNumber
        events.append(
          .init(
            eventID: "\(name.rawValue)-\(pass)", eventType: name.rawValue,
            dispatchTimeSeconds: dispatched, expectedVisualMarker: marker,
            firstMatchingFrame: frame.frameNumber, firstMatchingTimeSeconds: frame.timestampSeconds,
            finalSettledFrame: frame.frameNumber, finalSettledTimeSeconds: frame.timestampSeconds))
      }
      return events
    }
  }
}

private struct PixelEditingView: View {
  let edit: CanvasPixelEditingScenario.Edit
  private static let width = 76
  private static let height = 39
  @State private var pass = 0
  @State private var pixels: [Color?] = (0..<(76 * 39)).map {
    ($0 / 76).isMultiple(of: 2) ? .red : .blue
  }
  @State private var cursor = 1

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("edit canvas") {
        pass += 1
        switch edit {
        case .cursor:
          cursor = 1 + pass % (Self.width - 2)
        case .pixel:
          pixels[Self.width * 2 + cursor + 4] = pass.isMultiple(of: 2) ? .red : .green
        case .frame:
          pixels = pixels.map { $0 == .red ? .blue : .red }
        }
      }
      .buttonStyle(PixelEditingButtonStyle())
      Text("canvas edit \(pass)")
      ZStack(alignment: .topLeading) {
        Canvas.pixelGrid(
          width: Self.width, height: Self.height, pixels: pixels, mode: .verticalHalfBlock)
        Canvas(PixelCursorDrawing(x: cursor))
          .frame(width: Self.width, height: 20)
      }
      .frame(width: Self.width, height: 20)
    }
  }
}

private struct PixelCursorDrawing: CanvasDrawing, Equatable {
  var x: Int

  func draw(into context: inout CanvasContext) {
    context.setCell(at: .init(x: x, y: 1), character: "+", foreground: .white)
  }
}

private struct PixelEditingButtonStyle: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    configuration.label
  }
}
