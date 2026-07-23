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
func android_host_capability_declaration_is_pre_start_only() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())

  #expect(host.wireCapabilities == HostWireCapabilities())
  #expect(!host.declareCapabilities(json: "not json"))
  #expect(host.wireCapabilities == HostWireCapabilities())

  #expect(
    host.declareCapabilities(
      json: "{\"acceptsDeltaFrames\":true,\"maxAndroidSchemaVersion\":3}"
    )
  )
  #expect(
    host.wireCapabilities
      == HostWireCapabilities(acceptsDeltaFrames: true, maxAndroidSchemaVersion: 3)
  )

  // Capability-gated emission must never change shape mid-session: once the
  // scene starts, further declarations are rejected and the accepted one
  // stays.
  host.start()
  defer { host.stop() }
  #expect(!host.declareCapabilities(json: "{\"maxAndroidSchemaVersion\":2}"))
  #expect(
    host.wireCapabilities
      == HostWireCapabilities(acceptsDeltaFrames: true, maxAndroidSchemaVersion: 3)
  )
}

@MainActor
@Test
func android_host_abi_declare_capabilities_round_trips() throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  let declaration = Array("{\"acceptsDeltaFrames\":true}".utf8)
  let accepted = unsafe declaration.withUnsafeBufferPointer { buffer in
    unsafe swift_tui_android_declare_capabilities(
      handle, buffer.baseAddress, Int32(buffer.count))
  }

  #expect(accepted == 1)
  #expect(host.wireCapabilities == HostWireCapabilities(acceptsDeltaFrames: true))
}

@MainActor
@Test
func android_host_encodes_frames_only_at_consumption() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  swift_tui_android_start(handle)
  _ = await host.surface.waitForFrame { frame in
    rasterText(in: frame).contains("Android")
  }
  await Task.yield()

  // Encode-at-copy: a committed-but-unconsumed frame is never serialized —
  // the poll model deliberately skips frames, and skipped frames must not
  // pay encoding (convergence proposal 2026-07-22-002, Stage C0).
  #expect(host.consumedFrameEncodeCount == 0)
  #expect(host.latestFrameBytes == nil)

  // The two-phase ABI handshake (size query, then copy) encodes exactly
  // once for the consumed frame.
  let required = swift_tui_android_copy_latest_frame(handle, nil, 0)
  #expect(required > 0)
  #expect(host.consumedFrameEncodeCount == 1)

  var bytes = [UInt8](repeating: 0, count: Int(required))
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, required)
  }
  #expect(copied == required)
  #expect(host.consumedFrameEncodeCount == 1)

  let snapshot = try JSONDecoder().decode(AndroidHostFrameSnapshot.self, from: Data(bytes))
  #expect(snapshot.rows.joined(separator: "\n").contains("Android"))

  swift_tui_android_stop(handle)
}

@MainActor
@Test
func android_host_declared_web_surface_emits_converged_records() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  // The Kotlin host's declaration selects the converged web-surface wire
  // (convergence proposal 2026-07-22-002 Stage C1).
  #expect(host.declareCapabilities(json: "{\"maxWebSurfaceVersion\":2}"))

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

  let record = String(decoding: bytes, as: UTF8.self)
  #expect(record.hasPrefix("\u{001E}surface:"))
  let json = try #require(
    try JSONSerialization.jsonObject(
      with: Data(record.dropFirst("\u{001E}surface:".count).utf8)
    ) as? [String: Any]
  )
  #expect(json["version"] as? Int == 2)
  #expect(json["sequence"] as? Int == 7)
  // The additive terminalStyle key carries the runtime-owned appearance the
  // Compose renderer consumes.
  let terminalStyle = try #require(json["terminalStyle"] as? [String: Any])
  #expect((terminalStyle["backgroundColor"] as? [String: Any])?["hex"] != nil)
  let rows = try #require(json["rows"] as? [[Any]])
  #expect(rows.count == 1)
}

@MainActor
@Test
func android_host_delta_accumulates_damage_across_skipped_polls() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  #expect(
    host.declareCapabilities(
      json: "{\"maxWebSurfaceVersion\":3,\"acceptsDeltaFrames\":true}"
    )
  )

  func present(
    _ sequence: UInt64,
    lines: [String],
    damageRow: Int?
  ) throws {
    _ = try host.surface.present(
      SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(size: CellSize(width: 2, height: 2), lines: lines),
        semantics: SemanticSnapshot(),
        focusedIdentity: nil,
        rasterDamage: damageRow.map { row in
          PresentationDamage(
            textRows: [PresentationDamage.TextRow(row: row, columnRanges: [0..<2])]
          )
        }
      )
    )
  }

  func copyRecord() throws -> [String: Any] {
    let required = swift_tui_android_copy_latest_frame(handle, nil, 0)
    #expect(required > 0)
    var bytes = [UInt8](repeating: 0, count: Int(required))
    let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
      unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, required)
    }
    #expect(copied == required)
    let record = String(decoding: bytes, as: UTF8.self)
    return try #require(
      try JSONSerialization.jsonObject(
        with: Data(record.dropFirst("\u{001E}surface:".count).utf8)
      ) as? [String: Any]
    )
  }

  // Keyframe: first consumed frame after the declaration.
  try present(1, lines: ["ab", "cd"], damageRow: nil)
  await Task.yield()
  let keyframe = try copyRecord()
  #expect(keyframe["version"] as? Int == 2)
  #expect(keyframe["encoding"] == nil)

  // Two commits land between polls; the consumed record's delta must cover
  // BOTH damaged rows — the accumulated, consumption-relative diff that
  // keeps delta sound under the skipping poll (Stage C3).
  try present(2, lines: ["xb", "cd"], damageRow: 0)
  try present(3, lines: ["xb", "cy"], damageRow: 1)
  await Task.yield()
  let delta = try copyRecord()
  #expect(delta["version"] as? Int == 3)
  #expect(delta["encoding"] as? String == "delta")
  let deltaRows = try #require(delta["deltaRows"] as? [[Any]])
  #expect(deltaRows.compactMap { $0.first as? Int }.sorted() == [0, 1])
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

  let initial = await host.surface.waitForFrame { frame in
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

  _ = await host.surface.waitForFrame { frame in
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
  #expect((unsafe host.copyPendingClipboardText(to: nil, capacity: 0)) == 0)

  // The running app asks the host to place text on the clipboard.
  _ = try host.surface.writeClipboard("hello clipboard")

  let expected = Array("hello clipboard".utf8)
  let required = unsafe host.copyPendingClipboardText(to: nil, capacity: 0)
  #expect(required == expected.count)

  var bytes = [UInt8](repeating: 0, count: required)
  let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
    unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: required)
  }
  #expect(copied == required)
  #expect(bytes == expected)

  // Drained: a second copy delivers nothing until the next write.
  #expect((unsafe host.copyPendingClipboardText(to: nil, capacity: 0)) == 0)
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
  #expect((unsafe host.copyPendingClipboardText(to: nil, capacity: 0)) == expected.count)
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

@MainActor
@Test
func android_host_tick_abi_is_safe_and_does_not_disturb_frames() async throws {
  let host = try AndroidHostSceneHost(app: AndroidHostTestApp())
  let handle = AndroidHostHandleRegistry.register(host)
  defer {
    swift_tui_android_destroy(handle)
  }

  // The executor-drive ABIs back the Android main-actor pump (which resumes
  // `.task` loops and animation on a platform with no OS run loop). They must
  // always be safe to call: installing the executor and ticking an unknown
  // handle never crash, and `diag` is non-negative. Off-Android the tick is a
  // no-op; on Android it returns the count of drained main-actor jobs.
  swift_tui_android_install_executor()
  #expect(swift_tui_android_tick(0) == 0)
  #expect(swift_tui_android_diag() >= 0)

  swift_tui_android_start(handle)

  // Interleaving a tick must not disturb normal frame production.
  _ = swift_tui_android_tick(handle)
  let frame = await host.surface.waitForFrame { frame in
    rasterText(in: frame).contains("Android")
  }
  #expect(frame.sequence == 0)
  #expect(swift_tui_android_tick(handle) >= 0)

  swift_tui_android_stop(handle)
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
