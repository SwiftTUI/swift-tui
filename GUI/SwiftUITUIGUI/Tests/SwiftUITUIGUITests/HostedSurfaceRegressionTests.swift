import Dispatch
import TerminalUI
import Testing

@testable import SwiftUITUIGUI

@MainActor
@Test
func hosted_surface_publishes_pressed_button_frame_before_mouse_up() async throws {
  let recorder = SurfaceRecorder()
  let session = try HostedSceneSession(
    for: PressedButtonApp(),
    sceneID: "main",
    initialSize: .init(width: 32, height: 8),
    appearance: .fallback,
    onSurface: { surface in
      recorder.record(surface)
    }
  )

  let runTask = Task { try await session.start() }
  defer {
    session.stop()
  }

  let initial = try await recorder.waitForSurface(
    "initial button frame"
  ) { surface in
    surface.renderedText.contains("Press")
  }

  session.send(.mouse(.init(kind: .down(.primary), location: .init(x: 1, y: 0))))

  let pressed = try await recorder.waitForSurface(
    "pressed button frame"
  ) { surface in
    surface != initial && surface.renderedText.contains("Press")
  }

  #expect(pressed.lines == initial.lines)
  #expect(pressed != initial)

  session.send(.mouse(.init(kind: .up(.primary), location: .init(x: 1, y: 0))))
  _ = try await session.stopAndWait()
  _ = await runTask.result
}

@MainActor
@Test
func hosted_surface_scroll_wheel_updates_visible_scroll_view() async throws {
  let recorder = SurfaceRecorder()
  let session = try HostedSceneSession(
    for: ScrollSurfaceApp(),
    sceneID: "main",
    initialSize: .init(width: 32, height: 8),
    appearance: .fallback,
    onSurface: { surface in
      recorder.record(surface)
    }
  )

  let runTask = Task { try await session.start() }
  defer {
    session.stop()
  }

  let initial = try await recorder.waitForSurface(
    "initial scroll frame"
  ) { surface in
    surface.renderedText.contains("Row 0")
      && surface.renderedText.contains("Row 1")
  }

  session.send(.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 1, y: 1))))

  let scrolled = try await recorder.waitForSurface(
    "scrolled frame"
  ) { surface in
    surface != initial
      && !surface.renderedText.contains("Row 0")
      && surface.renderedText.contains("Row 3")
  }

  #expect(scrolled != initial)

  _ = try await session.stopAndWait()
  _ = await runTask.result
}

@MainActor
@Test
func hosted_surface_animation_publishes_intermediate_frames() async throws {
  let recorder = SurfaceRecorder()
  let session = try HostedSceneSession(
    for: AnimationSurfaceApp(),
    sceneID: "main",
    initialSize: .init(width: 32, height: 8),
    appearance: .fallback,
    onSurface: { surface in
      recorder.record(surface)
    }
  )

  let runTask = Task { try await session.start() }
  defer {
    session.stop()
  }

  _ = try await recorder.waitForSurface(
    "initial animation frame"
  ) { surface in
    surface.markerColumn == 0
  }

  session.send(.mouse(.init(kind: .down(.primary), location: .init(x: 1, y: 0))))
  session.send(.mouse(.init(kind: .up(.primary), location: .init(x: 1, y: 0))))

  let markerColumns = try await recorder.waitForMarkerColumns(
    "animated marker positions",
    minimumCount: 3,
    requiredColumns: [0, 8]
  )

  #expect(markerColumns.count >= 3)
  #expect(markerColumns.contains(0))
  #expect(markerColumns.contains(8))

  _ = try await session.stopAndWait()
  _ = await runTask.result
}

@MainActor
private struct PressedButtonApp: TerminalUI.App {
  var body: some TerminalUI.Scene {
    WindowGroup("Main", id: "main") {
      Button("Press") {}
        .buttonStyle(.borderedProminent)
        .frame(width: 12, height: 1, alignment: .leading)
    }
  }
}

@MainActor
private struct ScrollSurfaceApp: TerminalUI.App {
  var body: some TerminalUI.Scene {
    WindowGroup("Main", id: "main") {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<12) { index in
            Text("Row \(index)")
          }
        }
      }
      .frame(width: 12, height: 4, alignment: .topLeading)
    }
  }
}

@MainActor
private struct AnimationSurfaceApp: TerminalUI.App {
  var body: some TerminalUI.Scene {
    WindowGroup("Main", id: "main") {
      AnimationSurfaceView()
    }
  }
}

@MainActor
private struct AnimationSurfaceView: TerminalUI.View {
  @State private var shifted = false

  var body: some TerminalUI.View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Animate") {
        withAnimation(.linear(duration: .milliseconds(600))) {
          shifted.toggle()
        }
      }
      Text("Marker")
        .offset(x: shifted ? 8 : 0)
    }
  }
}

@MainActor
private final class SurfaceRecorder {
  private var surfaces: [RasterSurface] = []

  func record(
    _ surface: RasterSurface
  ) {
    surfaces.append(surface)
  }

  func waitForSurface(
    _ label: String,
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    matching predicate: (RasterSurface) -> Bool
  ) async throws -> RasterSurface {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if let surface = surfaces.last(where: predicate) {
        return surface
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    let rendered = surfaces.last?.renderedText ?? "<no surfaces>"
    Issue.record("Timed out waiting for \(label). Last surface:\n\(rendered)")
    if let surface = surfaces.last(where: predicate) {
      return surface
    }
    throw SurfaceRecorderError.timedOut
  }

  func waitForMarkerColumns(
    _ label: String,
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    minimumCount: Int,
    requiredColumns: Set<Int>
  ) async throws -> Set<Int> {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      let columns = Set(surfaces.compactMap(\.markerColumn))
      if columns.count >= minimumCount, requiredColumns.isSubset(of: columns) {
        return columns
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    let observedColumns = surfaces.compactMap(\.markerColumn)
    let rendered = surfaces.last?.renderedText ?? "<no surfaces>"
    Issue.record(
      "Timed out waiting for \(label). Observed marker columns: \(observedColumns). Last surface:\n\(rendered)"
    )
    throw SurfaceRecorderError.timedOut
  }
}

private enum SurfaceRecorderError: Error {
  case timedOut
}

extension RasterSurface {
  fileprivate var renderedText: String {
    lines.joined(separator: "\n")
  }

  fileprivate var markerColumn: Int? {
    for row in cells {
      for (x, cell) in row.enumerated()
      where !cell.isContinuation && cell.character == "M" {
        return x
      }
    }
    return nil
  }
}
