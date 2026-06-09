import Foundation
import SwiftTUIAndroidHost
@_spi(Runners) import SwiftTUIRuntime
import Testing

@MainActor
@Test
func android_host_scene_host_resizes_surface_and_pointer_capabilities() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())

  host.resize(
    columns: 120,
    rows: 40,
    cellPixelWidth: 9,
    cellPixelHeight: 18
  )

  #expect(host.surfaceSize == CellSize(width: 120, height: 40))
  #expect(host.cellPixelSize == PixelSize(width: 9, height: 18))
  #expect(host.surface.surfaceSize == CellSize(width: 120, height: 40))
  #expect(host.surface.graphicsCapabilities.cellPixelSize == PixelSize(width: 9, height: 18))
  #expect(host.surface.pointerInputCapabilities.supportsSubCellLocation)
  #expect(host.surface.pointerInputCapabilities.supportsHover)
  #expect(host.surface.pointerInputCapabilities.supportsPreciseScroll)
}

@MainActor
@Test
func android_host_handle_registry_copies_latest_frame_bytes() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  _ = try host.surface.present(
    SemanticHostFrame(
      sequence: 7,
      raster: RasterSurface(size: CellSize(width: 2, height: 1), lines: ["OK"]),
      semantics: SemanticSnapshot(),
      focusedIdentity: nil
    )
  )
  await Task.yield()

  let required = swift_tui_android_copy_latest_frame(handle, nil, 0)
  #expect(required > 0)

  var bytes = [UInt8](repeating: 0, count: Int(required))
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, required)
  }

  #expect(copied == required)
  let snapshot = try JSONDecoder().decode(AndroidHostFrameSnapshot.self, from: Data(bytes))
  #expect(snapshot.sequence == 7)
  #expect(snapshot.rows == ["OK"])
}

private struct AndroidHostTestApp: App {
  var body: some Scene {
    WindowGroup("Android Test") {
      Text("Android")
    }
  }
}
