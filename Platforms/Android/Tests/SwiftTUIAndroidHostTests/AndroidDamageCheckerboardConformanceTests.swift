// Excluded from Windows builds (Windows plan, Stage 6 item 3): the cross-host
// wire-conformance suite drives the Android and WebHost adapters, whose
// modules build empty on Windows (whole-file-guarded).
#if !os(Windows)

  import Foundation
  import SwiftTUIAndroidHost
  @_spi(Runners) import SwiftTUIRuntime
  import Testing

  @MainActor
  @Test("D15 legitimate in-grid checkerboard damage is grid-bounded across commit counts")
  func android_legitimate_checkerboard_damage_is_grid_bounded_across_commit_counts() async throws {
    let width = 9
    let height = 4
    let expectedMaximumRangesPerRow = (width + 1) / 2
    let checkerboardRanges = stride(from: 0, to: width, by: 2).map { $0..<($0 + 1) }
    let checkerboardDamage = PresentationDamage(
      textRows: (0..<height).map {
        .init(row: $0, columnRanges: checkerboardRanges)
      }
    )

    for commitCount in [1, 10, 100, 10_000] {
      let host = try AndroidHostSceneHost(app: AndroidCheckerboardTestApp())
      let handle = AndroidHostHandleRegistry.register(host)
      defer {
        swift_tui_android_destroy(handle)
      }
      #expect(host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}"))

      try presentCheckerboardFrame(
        on: host,
        sequence: 1,
        width: width,
        height: height,
        character: "A",
        damage: nil
      )
      await Task.yield()
      _ = try copyCheckerboardRecord(handle)

      for offset in 0..<commitCount {
        try presentCheckerboardFrame(
          on: host,
          sequence: UInt64(offset + 2),
          width: width,
          height: height,
          character: offset.isMultiple(of: 2) ? "B" : "C",
          damage: checkerboardDamage
        )
      }
      await Task.yield()
      let record = try copyCheckerboardRecord(handle)
      #expect(record["encoding"] as? String == "delta")
      let damage = try #require(record["damage"] as? [String: Any])
      let rows = try #require(damage["textRows"] as? [[Any]])
      #expect(rows.count <= height)
      #expect(rows.count == height)

      var decodedRowIndices: [Int] = []
      for rowValue in rows {
        #expect(rowValue.count == 2)
        let row = try #require(rowValue[0] as? Int)
        decodedRowIndices.append(row)
        let ranges = try #require(rowValue[1] as? [[Int]])
        #expect((0..<height).contains(row))
        #expect(ranges.count <= expectedMaximumRangesPerRow)
        #expect(ranges.count == expectedMaximumRangesPerRow)
        var previousEnd = -1
        for range in ranges {
          #expect(range.count == 2)
          let start = range[0]
          let end = range[1]
          #expect(start >= 0)
          #expect(start < end)
          #expect(end <= width)
          #expect(start > previousEnd)
          previousEnd = end
        }
      }
      #expect(decodedRowIndices == Array(0..<height))
    }
  }

  private struct AndroidCheckerboardTestApp: App {
    var body: some Scene {
      WindowGroup("Checkerboard") {
        Text("checkerboard")
      }
    }
  }

  @MainActor
  private func presentCheckerboardFrame(
    on host: AndroidHostSceneHost,
    sequence: UInt64,
    width: Int,
    height: Int,
    character: Character,
    damage: PresentationDamage?
  ) throws {
    let cells = Array(
      repeating: Array(repeating: RasterCell(character: character), count: width),
      count: height
    )
    _ = try host.surface.present(
      SemanticHostFrame(
        sequence: sequence,
        raster: RasterSurface(
          size: .init(width: width, height: height),
          cells: cells
        ),
        semantics: .init(),
        focusedIdentity: nil,
        rasterDamage: damage
      )
    )
  }

  private func copyCheckerboardRecord(
    _ handle: Int64
  ) throws -> [String: Any] {
    let required = swift_tui_android_copy_latest_frame(handle, nil, 0)
    guard required > 0 else {
      throw HostWireConformanceError.invalid("D15 checkerboard size query returned no record")
    }
    var bytes = [UInt8](repeating: 0, count: Int(required))
    let copied = unsafe bytes.withUnsafeMutableBufferPointer { buffer in
      unsafe swift_tui_android_copy_latest_frame(handle, buffer.baseAddress, required)
    }
    guard copied == required else {
      throw HostWireConformanceError.invalid(
        "D15 checkerboard copy returned \(copied), expected \(required)")
    }
    let prefix = Array("\u{001E}surface:".utf8)
    guard bytes.starts(with: prefix), bytes.last == 0x0A else {
      throw HostWireConformanceError.invalid("D15 checkerboard copy was not a surface record")
    }
    let payload = Data(bytes[prefix.count..<(bytes.count - 1)])
    guard let record = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
      throw HostWireConformanceError.invalid("D15 checkerboard surface payload was not an object")
    }
    return record
  }

#endif
