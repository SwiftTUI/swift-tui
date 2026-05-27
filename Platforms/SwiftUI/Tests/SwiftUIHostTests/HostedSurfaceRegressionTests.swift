import SwiftTUI
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

@MainActor
@Suite(.serialized)
struct HostedSurfaceRegressionTests {
  @MainActor
  @Test
  func hosted_surface_publishes_pressed_button_frame_before_mouse_up() async throws {
    let surface = hostedSurface()
    let session = try HostedSceneSession(
      for: PressedButtonApp(),
      sceneID: "main",
      surface: surface
    )

    let runTask = Task { try await session.start() }
    defer {
      session.stop()
    }

    let initial = await surface.waitForSurface { surface in
      surface.renderedText.contains("Press")
    }

    session.send(.mouse(.init(kind: .down(.primary), location: .init(x: 1, y: 0))))

    let pressed = await surface.waitForSurface { surface in
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
    let surface = hostedSurface()
    let session = try HostedSceneSession(
      for: ScrollSurfaceApp(),
      sceneID: "main",
      surface: surface
    )

    let runTask = Task { try await session.start() }
    defer {
      session.stop()
    }

    let initial = await surface.waitForSurface { surface in
      surface.renderedText.contains("Row 0")
        && surface.renderedText.contains("Row 1")
    }

    session.send(.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: 3), location: .init(x: 1, y: 1))))

    let scrolled = await surface.waitForSurface { surface in
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
    let surface = hostedSurface()
    let session = try HostedSceneSession(
      for: AnimationSurfaceApp(),
      sceneID: "main",
      surface: surface
    )

    let runTask = Task { try await session.start() }
    defer {
      session.stop()
    }

    _ = await surface.waitForSurface { surface in
      surface.markerColumn == 0
    }

    session.send(.mouse(.init(kind: .down(.primary), location: .init(x: 1, y: 0))))
    session.send(.mouse(.init(kind: .up(.primary), location: .init(x: 1, y: 0))))

    let frames: [SemanticHostFrame] = await surface.waitForFrames { frames in
      let markerColumns = Set(frames.compactMap(\.raster.markerColumn))
      return markerColumns.count >= 3 && Set([0, 8]).isSubset(of: markerColumns)
    }
    let markerColumns = Set(frames.compactMap(\.raster.markerColumn))

    #expect(markerColumns.count >= 3)
    #expect(markerColumns.contains(0))
    #expect(markerColumns.contains(8))

    _ = try await session.stopAndWait()
    _ = await runTask.result
  }

  @MainActor
  @Test("hosted raster surface retains semantic frame damage")
  func hostedRasterSurfaceRetainsSemanticFrameDamage() async throws {
    let surface = hostedSurface()
    let damage = PresentationDamage(textRows: [.init(row: 0, columnRanges: [1..<2])])

    try surface.present(
      SemanticHostFrame(
        sequence: 2,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["ABC"]),
        semantics: .init(),
        focusedIdentity: nil
      )
    )
    try surface.present(
      SemanticHostFrame(
        sequence: 3,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["AXC"]),
        semantics: .init(),
        focusedIdentity: nil,
        rasterDamage: damage
      )
    )

    let frame = await surface.waitForFrame { $0.sequence == 3 }
    #expect(frame.rasterDamage == damage)
  }

  @MainActor
  @Test("semantic host frame reports measured window content size")
  func semanticHostFrameReportsMeasuredWindowContentSize() async throws {
    let surface = HostedRasterSurface(
      surfaceSize: .init(width: 40, height: 10),
      appearance: .fallback,
      onFrame: { _ in }
    )
    let session = try HostedSceneSession(
      for: NaturalSizeSurfaceApp(),
      sceneID: "main",
      surface: surface
    )

    let runTask = Task { try await session.start() }
    defer {
      session.stop()
    }

    let frame = await surface.waitForFrame { frame in
      frame.raster.renderedText.contains("Natural")
    }

    #expect(frame.raster.size == .init(width: 40, height: 10))
    #expect(frame.preferredLayoutSize == .init(width: 7, height: 1))

    _ = try await session.stopAndWait()
    _ = await runTask.result
  }

  @MainActor
  @Test
  func hosted_surface_drag_gesture_receives_fractional_location() async throws {
    let surface = hostedSurface()
    let session = try HostedSceneSession(
      for: FractionalDragSurfaceApp(),
      sceneID: "main",
      surface: surface
    )

    let runTask = Task { try await session.start() }
    defer {
      session.stop()
    }

    _ = await surface.waitForSurface { surface in
      surface.renderedText.contains("drag idle")
    }

    let metrics = CellPixelMetrics(width: 8, height: 16, source: .reported)
    session.send(
      .mouse(
        .init(
          kind: .down(.primary),
          location: .subCell(
            location: Point(x: 1.25, y: 0.50),
            source: .nativePixels,
            metrics: metrics
          )
        )
      )
    )
    session.send(
      .mouse(
        .init(
          kind: .dragged(.primary),
          location: .subCell(
            location: Point(x: 1.75, y: 0.50),
            source: .nativePixels,
            metrics: metrics
          )
        )
      )
    )

    _ = await surface.waitForSurface { surface in
      surface.renderedText.contains("drag 175:50")
    }

    _ = try await session.stopAndWait()
    _ = await runTask.result
  }

}

@MainActor
private func hostedSurface() -> HostedRasterSurface {
  HostedRasterSurface(
    surfaceSize: .init(width: 32, height: 8),
    appearance: .fallback,
    onFrame: { _ in }
  )
}

@MainActor
private struct PressedButtonApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      Button("Press") {}
        .buttonStyle(.borderedProminent)
        .frame(width: 12, height: 1, alignment: .leading)
    }
  }
}

@MainActor
private struct ScrollSurfaceApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
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
private struct AnimationSurfaceApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      AnimationSurfaceView()
    }
  }
}

@MainActor
private struct FractionalDragSurfaceApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      FractionalDragSurfaceView()
    }
  }
}

@MainActor
private struct NaturalSizeSurfaceApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      Text("Natural")
    }
  }
}

@MainActor
private struct AnimationSurfaceView: SwiftTUIRuntime.View {
  @State private var shifted = false

  var body: some SwiftTUIRuntime.View {
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
private struct FractionalDragSurfaceView: SwiftTUIRuntime.View {
  @State private var label = "drag idle"

  var body: some SwiftTUIRuntime.View {
    Text(label)
      .frame(width: 24, height: 1, alignment: .leading)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let x = Int((value.location.x * 100).rounded())
            let y = Int((value.location.y * 100).rounded())
            label = "drag \(x):\(y)"
          }
      )
  }
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
