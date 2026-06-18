import Foundation
@_spi(Testing) import SwiftTUICore
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
func android_host_abi_start_publishes_first_frame_bytes() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  swift_tui_android_start(handle)

  let frame = await host.surface.waitForFrame { frame in
    rasterText(in: frame).contains("Android")
  }
  #expect(frame.sequence == 0)

  await Task.yield()
  let required = swift_tui_android_copy_latest_frame(handle, nil, 0)
  #expect(required > 0)

  var bytes = [UInt8](repeating: 0, count: Int(required))
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, required)
  }

  #expect(copied == required)
  let snapshot = try JSONDecoder().decode(AndroidHostFrameSnapshot.self, from: Data(bytes))
  #expect(snapshot.sequence == 0)
  #expect(snapshot.rows.joined(separator: "\n").contains("Android"))

  swift_tui_android_stop(handle)
}

@MainActor
@Test
func android_host_sgr_mouse_tap_activates_tab_view_selection() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTabTestApp())
  defer {
    host.stop()
  }

  host.start()
  host.resize(
    columns: 80,
    rows: 24,
    cellPixelWidth: 9,
    cellPixelHeight: 18
  )

  let initial = try await waitForAndroidHostFrame(on: host.surface) { frame in
    rasterText(in: frame).contains("LOGO pane")
  }
  let counterRegion = try #require(
    initial.semantics.interactionRegions.first { region in
      region.identity.path.contains("TabItem[1]")
    },
    "expected Counter tab interaction region; semantics:\n\(SnapshotRenderer().semanticSnapshot(initial.semantics))"
  )
  let tapCell = CellPoint(
    x: counterRegion.rect.origin.x + max(0, counterRegion.rect.size.width / 2),
    y: counterRegion.rect.origin.y
  )

  host.sendInput(sgrPrimaryTapBytes(at: tapCell))

  _ = try await waitForAndroidHostFrame(on: host.surface) { frame in
    frame.sequence > initial.sequence && rasterText(in: frame).contains("COUNTER pane")
  }
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

@MainActor
@Test
func android_host_surfaces_clipboard_write_and_drains_once() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())

  // No copy requested yet.
  #expect(host.copyPendingClipboardText(to: nil, capacity: 0) == 0)

  // The running app asks the host to place text on the clipboard.
  _ = try host.surface.writeClipboard("hello clipboard")

  let expected = Array("hello clipboard".utf8)
  let required = host.copyPendingClipboardText(to: nil, capacity: 0)
  #expect(required == expected.count)

  var bytes = [UInt8](repeating: 0, count: required)
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: required)
  }
  #expect(copied == required)
  #expect(bytes == expected)

  // Drained: a second copy delivers nothing until the next write.
  #expect(host.copyPendingClipboardText(to: nil, capacity: 0) == 0)
}

@MainActor
@Test
func android_host_clipboard_size_query_does_not_drain() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  _ = try host.surface.writeClipboard("keep me")
  let expected = Array("keep me".utf8)

  // An undersized buffer is a size query and must not drain.
  var tooSmall = [UInt8](repeating: 0, count: 1)
  let stillNeeded = unsafe tooSmall.withUnsafeMutableBufferPointer { buffer in
    unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: 1)
  }
  #expect(stillNeeded == expected.count)
  #expect(host.copyPendingClipboardText(to: nil, capacity: 0) == expected.count)
}

@MainActor
@Test
func android_host_abi_copies_pending_clipboard_text() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  _ = try host.surface.writeClipboard("via abi")
  let expected = Array("via abi".utf8)

  let required = swift_tui_android_copy_clipboard_text(handle, nil, 0)
  #expect(required == Int32(expected.count))

  var bytes = [UInt8](repeating: 0, count: Int(required))
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe swift_tui_android_copy_clipboard_text(handle, buffer.baseAddress, required)
  }
  #expect(copied == required)
  #expect(bytes == expected)
  #expect(swift_tui_android_copy_clipboard_text(handle, nil, 0) == 0)
}

private struct AndroidHostTestApp: App {
  var body: some Scene {
    WindowGroup("Android Test") {
      Text("Android")
    }
  }
}

private struct AndroidHostTabTestApp: App {
  var body: some Scene {
    WindowGroup("Android Tabs") {
      AndroidHostTabTestView()
    }
  }
}

private struct AndroidHostTabTestView: View {
  @State private var selection = "logo"

  var body: some View {
    TabView(selection: $selection) {
      Tab("Logo", value: "logo") {
        Text("LOGO pane")
      }

      Tab("Counter", value: "counter") {
        Text("COUNTER pane")
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

private enum AndroidHostFrameTimeout: Error {
  case timedOut
}

private func waitForAndroidHostFrame(
  on surface: HostedRasterSurface,
  timeoutNanoseconds: UInt64 = 1_000_000_000,
  matching predicate: @escaping @Sendable (SemanticHostFrame) -> Bool
) async throws -> SemanticHostFrame {
  try await withThrowingTaskGroup(of: SemanticHostFrame.self) { group in
    group.addTask {
      await surface.waitForFrame(matching: predicate)
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw AndroidHostFrameTimeout.timedOut
    }

    let frame = try await group.next() ?? {
      throw AndroidHostFrameTimeout.timedOut
    }()
    group.cancelAll()
    return frame
  }
}

private func sgrPrimaryTapBytes(
  at cell: CellPoint
) -> [UInt8] {
  let column = cell.x + 1
  let row = cell.y + 1
  return Array("\u{1B}[<0;\(column);\(row)M\u{1B}[<0;\(column);\(row)m".utf8)
}

private func rasterText(
  in frame: SemanticHostFrame
) -> String {
  frame.raster.lines.joined(separator: "\n")
}
