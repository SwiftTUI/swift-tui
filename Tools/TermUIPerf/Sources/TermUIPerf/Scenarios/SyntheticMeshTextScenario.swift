import Foundation
@_spi(Runners) import SwiftTUI

/// Measures mesh-styled text across first render, retained reuse, and a
/// same-topology point-and-color animation.
public struct SyntheticMeshTextScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticMeshText
  public let defaultTerminalSize = PerfTerminalSize(columns: 80, rows: 24)
  public let scriptedEvents = [
    "capture mesh-styled text first render",
    "advance six frames with unchanged mesh-styled text",
    "animate mesh text points and colors to a settled target",
  ]
  public let visualMarkers = ["mesh text phase static"]
  public let settlingDescription = "first settled frame after the mesh text animation"

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfMeshTextProbeView()
    } drive: { driver in
      let first = try await driver.waitForFrame(containing: "mesh text phase static")
      var events = [
        PerfEventRecord(
          eventID: "mesh-text-first-render",
          eventType: "initial_frame",
          dispatchTimeSeconds: first.timestampSeconds,
          expectedVisualMarker: "mesh text phase static",
          firstMatchingFrame: first.frameNumber,
          firstMatchingTimeSeconds: first.timestampSeconds,
          finalSettledFrame: first.frameNumber,
          finalSettledTimeSeconds: first.timestampSeconds
        )
      ]

      let retainedDispatch = monotonicSeconds()
      var retainedFrame = first
      for pass in 1...6 {
        let cell = try driver.cell(containing: "retain mesh text")
        driver.sendClick(at: cell)
        retainedFrame = try await driver.waitForFrame(
          containing: "retained text pass \(pass)",
          afterFrame: retainedFrame.frameNumber
        )
      }
      events.append(
        PerfEventRecord(
          eventID: "mesh-text-unchanged-retained-frames",
          eventType: "mouse_click",
          dispatchTimeSeconds: retainedDispatch,
          expectedVisualMarker: "retained text pass 6",
          firstMatchingFrame: retainedFrame.frameNumber,
          firstMatchingTimeSeconds: retainedFrame.timestampSeconds,
          finalSettledFrame: retainedFrame.frameNumber,
          finalSettledTimeSeconds: retainedFrame.timestampSeconds
        )
      )

      let animationDispatch = monotonicSeconds()
      let animationCell = try driver.cell(containing: "animate mesh text")
      driver.sendClick(at: animationCell)
      let settled = try await driver.waitForFrame(
        containing: "mesh text phase settled",
        afterFrame: retainedFrame.frameNumber,
        timeout: .seconds(3)
      )
      events.append(
        PerfEventRecord(
          eventID: "mesh-text-same-topology-animation",
          eventType: "mouse_click",
          dispatchTimeSeconds: animationDispatch,
          expectedVisualMarker: "mesh text phase settled",
          firstMatchingFrame: settled.frameNumber,
          firstMatchingTimeSeconds: settled.timestampSeconds,
          finalSettledFrame: settled.frameNumber,
          finalSettledTimeSeconds: settled.timestampSeconds
        )
      )
      return events
    }
  }
}

private struct PerfMeshTextProbeView: View {
  @State private var retainedPass = 0
  @State private var animated = false
  @State private var animationSettled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Button("retain mesh text") {
          retainedPass += 1
        }
        Button("animate mesh text") {
          animationSettled = false
          withAnimation(.linear(duration: .milliseconds(1200))) {
            animated.toggle()
          }
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            animationSettled = true
          }
        }
      }
      Text("retained text pass \(retainedPass)")
      Text("mesh text phase \(phaseLabel)")
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<20, id: \.self) { _ in
          Text(Self.textLine)
        }
      }
      .foregroundStyle(fillStyle)
    }
  }

  private var phaseLabel: String {
    if animationSettled {
      return "settled"
    }
    return animated ? "animating" : "static"
  }

  private var mesh: MeshGradient {
    MeshGradient(
      width: 3,
      height: 3,
      points: animated ? Self.targetPoints : Self.sourcePoints,
      colors: animated ? Self.targetColors : Self.sourceColors,
      background: .black,
      smoothsColors: true,
      colorSpace: .perceptual
    )
  }

  private var fillStyle: AnyShapeStyle {
    if ProcessInfo.processInfo.environment["SWIFTTUI_PERF_MESH_REFERENCE_LINEAR"] == "1" {
      return LinearGradient(
        colors: animated ? [.red, .cyan, .blue] : [.blue, .white, .red],
        startPoint: animated ? .topTrailing : .topLeading,
        endPoint: animated ? .bottomLeading : .bottomTrailing
      ).eraseToAnyShapeStyle()
    }
    return mesh.eraseToAnyShapeStyle()
  }

  private static let textLine = String(repeating: "mesh-text ", count: 7)

  private static let sourcePoints: [SIMD2<Float>] = [
    .init(0, 0), .init(0.5, 0), .init(1, 0),
    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
    .init(0, 1), .init(0.5, 1), .init(1, 1),
  ]

  private static let targetPoints: [SIMD2<Float>] = [
    .init(0, 0), .init(0.44, 0.08), .init(1, 0),
    .init(0.08, 0.45), .init(0.64, 0.35), .init(0.94, 0.58),
    .init(0, 1), .init(0.56, 0.92), .init(1, 1),
  ]

  private static let sourceColors: [Color] = [
    .blue, .cyan, .green,
    .magenta, .white, .yellow,
    .red, .magenta, .blue,
  ]

  private static let targetColors: [Color] = [
    .red, .yellow, .magenta,
    .blue, .cyan, .white,
    .green, .blue, .red,
  ]
}
