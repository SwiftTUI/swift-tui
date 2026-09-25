import Foundation
@_spi(Runners) import SwiftTUIRuntime
import Testing

@Suite struct HostWireBudgetTests {
  @Test func sharedLimitsAndGridBoundaries() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/Transport/wire-budget-boundaries.json")
    let fixture = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let limits = try #require(fixture["limits"] as? [String: Int])
    #expect(limits["recordBytes"] == HostWireBudget.recordBytes)
    #expect(limits["gridDimension"] == HostWireBudget.gridDimension)
    #expect(limits["gridCells"] == HostWireBudget.gridCells)
    #expect(limits["cellTextBytes"] == HostWireBudget.cellTextBytes)
    #expect(limits["styleBytes"] == HostWireBudget.styleBytes)
    #expect(limits["images"] == HostWireBudget.images)
    #expect(limits["metadataEntries"] == HostWireBudget.metadataEntries)
    for entry in try #require(fixture["cases"] as? [[String: Any]]) {
      let kind = entry["kind"] as? String
      if kind == "grid" || kind == "width" {
        let width = try #require(entry[kind == "grid" ? "width" : "value"] as? Int)
        let height = entry["height"] as? Int ?? 1
        #expect(
          HostWireBudget.admits(.init(width: width, height: height)) == (entry["accepted"] as? Bool)
        )
      }
    }
    #expect(!HostWireBudget.admits(.init(width: Int.max, height: Int.max)))
  }

  @Test func encodedByteBoundaryIncludesPrefixAndExcludesLF() throws {
    for size in [
      HostWireBudget.recordBytes - 1, HostWireBudget.recordBytes, HostWireBudget.recordBytes + 1,
    ] {
      var record = HostWireRecord("\u{1E}")
      record += String(repeating: "é", count: (size - 1) / 2)
      record += String(repeating: "x", count: (size - 1) % 2)
      record += "\n"
      if size <= HostWireBudget.recordBytes {
        #expect(try record.finish().utf8.count == size + 1)
      } else {
        #expect(throws: HostWireBudget.Exceeded.self) { try record.finish() }
      }
    }
  }

  @Test func rejectionDoesNotAdvanceDeliveryStateAndNextFrameIsFull() throws {
    var state = HostWireEncodingState(deltaEnabled: true, styleAppendEnabled: true, epochID: 7)
    let valid = RasterSurface(
      size: .init(width: 1, height: 1), cells: [[RasterCell(character: "a")]])
    _ = WebSurfaceFrameEncoder.encode(valid, state: &state)
    let generation = state.recordsEncoded
    let oversized = RasterSurface(size: .init(width: Int.max, height: 1), cells: [])
    #expect(
      WebSurfaceFrameEncoder.encode(oversized, state: &state) == HostWireBudget.rejectionRecord)
    #expect(state.recordsEncoded == generation)
    #expect(!state.hasBaseline)
    #expect(state.knownImageIDs.isEmpty)
    let output = WebSurfaceFrameEncoder.encode(valid, state: &state)
    #expect(output.contains("\"rows\":"))
    #expect(!output.contains("\"deltaRows\":"))
    #expect(state.recordsEncoded == generation + 1)
    #expect(output.utf8.count <= HostWireBudget.recordBytes + 1)
  }

  @Test func fullImageHistoryAdmitsANewImageWithoutResendingPlacedPayloads() throws {
    func image(_ name: String, _ bytes: [UInt8]) -> RasterImageAttachment {
      let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
      return RasterImageAttachment(
        identity: Identity(components: [name]), bounds: bounds, visibleBounds: bounds,
        source: .data(bytes), resolvedReference: .embeddedImage(bytes),
        pixelSize: .init(width: 1, height: 1), isResizable: false)
    }
    func surface(_ images: [RasterImageAttachment]) -> RasterSurface {
      RasterSurface(size: .init(width: 1, height: 1), lines: [" "], imageAttachments: images)
    }
    // Each large payload fits one record alone; all four together do not.
    let large = (0..<4).map { index in
      image("large\(index)", [0x89, 0x50] + Array(repeating: UInt8(index), count: 900 * 1024))
    }
    let history = (0..<(HostWireBudget.images - large.count)).map { index in
      image("history\(index)", [0x89, 0x51, UInt8(index >> 8), UInt8(index & 0xFF)])
    }
    var state = HostWireEncodingState(deltaEnabled: false, epochID: 9)
    for placement in large {
      #expect(
        WebSurfaceFrameEncoder.encode(surface([placement]), state: &state).contains("dataBase64"))
    }
    #expect(
      WebSurfaceFrameEncoder.encode(surface(history), state: &state).hasPrefix("\u{1E}surface:"))
    #expect(state.knownImageIDs.count == HostWireBudget.images)
    let largeIDs = Set(large.compactMap { ImageContentRepository.shared.content(for: $0)?.wireID })
    #expect(largeIDs.count == large.count)
    #expect(largeIDs.isSubset(of: state.knownImageIDs))

    // A static scene adds one new image in front of the large ones. Forgetting
    // the placed large IDs to admit it would re-send all four payloads in one
    // over-budget record, and a rejected record keeps the history, so every
    // frame of the scene would be rejected alike.
    let scene = surface([image("new", [0x89, 0x52])] + large)
    let first = WebSurfaceFrameEncoder.encode(scene, state: &state)
    #expect(first.hasPrefix("\u{1E}surface:"))
    #expect(first.components(separatedBy: "dataBase64").count == 2)
    #expect(state.knownImageIDs.count == HostWireBudget.images)
    #expect(largeIDs.isSubset(of: state.knownImageIDs))
    let second = WebSurfaceFrameEncoder.encode(scene, state: &state)
    #expect(second.hasPrefix("\u{1E}surface:"))
    #expect(!second.contains("dataBase64"))
  }

  @Test func cellTextBoundaryAndDenseLargeFrame() {
    for bytes in [255, 256, 257] {
      // One extended grapheme with repeated combining scalars.
      let lead = bytes % 2 == 0 ? "é" : "a"
      let text = lead + String(repeating: "\u{301}", count: (bytes - lead.utf8.count) / 2)
      #expect(text.utf8.count == bytes)
      let surface = RasterSurface(
        size: .init(width: 1, height: 1), cells: [[RasterCell(character: Character(text))]])
      let output = WebSurfaceFrameEncoder.encode(surface)
      #expect(
        output.hasPrefix("\u{1E}surface:") == (text.utf8.count <= HostWireBudget.cellTextBytes))
    }
    let surface = RasterSurface(
      size: .init(width: 256, height: 256),
      cells: Array(repeating: Array(repeating: RasterCell(character: "a"), count: 256), count: 256))
    let output = WebSurfaceFrameEncoder.encode(surface)
    #expect(output.hasPrefix("\u{1E}surface:"))
    #expect(output.utf8.count <= HostWireBudget.recordBytes + 1)
  }

  @Test func oversizedEscapingAndClipboardAreRefusedBeforeEncodingCopies() {
    let text = String(repeating: "\u{0}", count: HostWireBudget.recordBytes / 6 + 1)
    #expect(throws: HostWireBudget.Exceeded.self) { try HostWireBudget.jsonStringBytes(text) }
    #expect(WebSurfaceFrameEncoder.encodeClipboard(text) == HostWireBudget.rejectionRecord)
  }

  @Test func rendererDamageIsClippedAndDeduplicatedBeforeWireEncoding() throws {
    var damage = PresentationDamage(textRows: [.init(row: 0, columnRanges: [-10..<100])])
    damage.textRows.append(.init(row: 0, columnRanges: [0..<1]))
    damage.textRows.append(.init(row: 99))
    let normalized = try #require(
      HostWireBudget.clippedDamage(damage, in: .init(width: 2, height: 1)))
    #expect(normalized.textRows.count == 1)
    #expect(normalized.textRows[0].row == 0)
    #expect(normalized.textRows[0].columnRanges == [0..<2])
    let surface = RasterSurface(size: .init(width: 2, height: 1), lines: ["OK"])
    let record = WebSurfaceFrameEncoder.encode(surface, damage: damage)
    #expect(record.hasPrefix("\u{1E}surface:"))
    #expect(record.contains("\"textRows\":[[0,[[0,2]]]]"))
  }
}
