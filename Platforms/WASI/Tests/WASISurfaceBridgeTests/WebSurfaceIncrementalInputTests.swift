@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite struct WebSurfaceIncrementalInputTests {
  @Test func terminalSequencesCrossEveryChunkBoundary() {
    let bytes = Array("\u{1B}[A\u{1B}é\u{1B}[200~paste\u{1B}[201~".utf8)
    for split in 0...bytes.count {
      var parser = WebSurfaceInputParser()
      let records =
        parser.feedRecords(Array(bytes[..<split])) + parser.feedRecords(Array(bytes[split...]))
      #expect(
        records == [
          .input(.key(.init(.arrowUp))), .input(.key(.init(.character("é"), modifiers: .alt))),
          .input(.paste(.init(content: "paste"))),
        ])
    }
  }

  @Test func fixedCapabilitiesAndFirstAcceptedDeclarationOwnGeometry() throws {
    var fixed = WebSurfaceInputParser(fixedCapabilities: .init())
    _ = fixed.feedRecords(command("caps:{\"geometryRevisions\":true}"))
    _ = fixed.feedRecords(command("geometry:9:80:24:9:21"))
    _ = fixed.feedRecords(command("resize:80:24:10:22"))
    #expect(
      try mouse(fixed.feedRecords(command("mouse:moved:1:1:none:0:0:0"))).location.rawPixel
        == .init(x: 10, y: 22))

    var negotiated = WebSurfaceInputParser(requiresSharedViewport: true)
    _ = negotiated.feedRecords(command("caps:{\"geometryRevisions\":true}"))
    _ = negotiated.feedRecords(command("geometry:9:80:24:9:21"))
    _ = negotiated.feedRecords(command("caps:{\"geometryRevisions\":true,\"sharedViewport\":true}"))
    _ = negotiated.feedRecords(command("geometry:1:80:24:8:16"))
    _ = negotiated.feedRecords(command("caps:{}"))
    _ = negotiated.feedRecords(command("resize:80:24:10:22"))
    #expect(
      try mouse(negotiated.feedRecords(command("mouse:moved:1:1:none:0:0:0"))).location.rawPixel
        == .init(x: 8, y: 16))
  }

  private func command(_ text: String) -> [UInt8] { Array("\u{1E}\(text)\n".utf8) }
  private func mouse(_ records: [WebSurfaceInputRecord]) throws -> MouseEvent {
    let record = try #require(records.first)
    guard case .input(.mouse(let event)) = record else {
      throw MissingMouse.event
    }
    return event
  }
  private enum MissingMouse: Error { case event }
}
