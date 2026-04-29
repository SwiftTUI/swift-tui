import Foundation
@_spi(Runners) import TerminalUI
import Testing

@testable import TerminalUIWASI

@Suite
struct WebSurfaceTransportTests {
  @Test("encoder emits the shared basic web-surface fixture")
  func encoderEmitsBasicFixture() throws {
    let fixture = try Self.fixture("web-surface-basic")
    #expect(WebSurfaceFrameEncoder.encode(Self.basicSurface()) == fixture)
  }

  @Test("encoder preserves styles, spans, escaping, and skips continuation cells")
  func encoderEmitsStyledFixture() throws {
    let fixture = try Self.fixture("web-surface-styled")
    #expect(WebSurfaceFrameEncoder.encode(Self.styledSurface()) == fixture)
  }

  @Test("host writes one complete surface record and reports full repaint metrics")
  func hostPresentWritesSurfaceRecord() throws {
    let pipe = Pipe()
    let host = WebSurfaceTransportHost(
      surfaceSize: .init(width: 2, height: 2),
      outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
      renderStyle: .init(appearance: .fallback)
    )

    let metrics = try host.present(Self.basicSurface())
    pipe.fileHandleForWriting.closeFile()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    pipe.fileHandleForReading.closeFile()

    let fixture = try Self.fixture("web-surface-basic")
    #expect(output == fixture)
    #expect(metrics.bytesWritten == output.utf8.count)
    #expect(metrics.linesTouched == 2)
    #expect(metrics.cellsChanged == 4)
    #expect(metrics.strategy == .fullRepaint)
  }

  @Test("encoder emits image data once and then reuses the cached image id")
  func encoderEmitsImageDataOnceAndThenReusesCachedImageID() throws {
    var knownImageIDs: Set<String> = []
    let firstFrame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.imageSurface(),
        knownImageIDs: &knownImageIDs
      )
    )
    let secondFrame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.imageSurface(),
        knownImageIDs: &knownImageIDs
      )
    )

    let firstImage = try #require((firstFrame["images"] as? [[String: Any]])?.first)
    let secondImage = try #require((secondFrame["images"] as? [[String: Any]])?.first)

    #expect(firstImage["format"] as? String == "png")
    #expect(firstImage["bounds"] as? [Int] == [1, 0, 3, 2])
    #expect(firstImage["visibleBounds"] as? [Int] == [2, 0, 2, 2])
    #expect(firstImage["pixelSize"] as? [Int] == [3, 2])
    #expect(firstImage["scalingMode"] as? String == "stretch")
    #expect(firstImage["dataBase64"] as? String == "iVBORw==")

    #expect(secondImage["id"] as? String == firstImage["id"] as? String)
    #expect(secondImage["dataBase64"] == nil)
  }

  @Test("encoder advertises gif format and ships dataBase64 for animated GIF inputs")
  func encoderAdvertisesGIFFormatAndShipsDataBase64() throws {
    // GIF89a header followed by a few palette/data bytes — short, but
    // long enough to trip the 6-byte magic check so the encoder picks
    // .gif over the .png default.
    let gifBytes: [UInt8] = [
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61,  // GIF89a
      0x01, 0x00, 0x01, 0x00,  // 1x1 logical screen
      0x80, 0x00, 0x00,
    ]
    let surface = RasterSurface(
      size: .init(width: 4, height: 2),
      lines: ["    ", "    "],
      imageAttachments: [
        RasterImageAttachment(
          identity: .init(components: [.named("gif")]),
          bounds: .init(origin: .zero, size: .init(width: 3, height: 2)),
          visibleBounds: nil,
          source: .data(gifBytes),
          resolvedReference: .embeddedImage(gifBytes),
          pixelSize: .init(width: 1, height: 1),
          isResizable: false
        )
      ]
    )

    var knownImageIDs: Set<String> = []
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        surface,
        knownImageIDs: &knownImageIDs
      )
    )
    let image = try #require((frame["images"] as? [[String: Any]])?.first)

    #expect(image["format"] as? String == "gif")
    let id = try #require(image["id"] as? String)
    #expect(id.hasPrefix("gif:"))
    #expect(image["dataBase64"] as? String == "R0lGODlhAQABAIAAAA==")
  }

  @Test("parser handles resize and style commands split across chunks")
  func parserHandlesChunkedControlCommands() throws {
    var parser = WebSurfaceInputParser()
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .hex("#102030"),
        backgroundColor: .hex("#405060"),
        tintColor: .hex("#708090"),
        source: .override
      )
    )
    let encodedStyle = try #require(TerminalRenderStyleCodec.encodeBase64(style))

    let first = parser.feed(bytes("\u{001E}resize:12"))
    #expect(first.events.isEmpty)
    #expect(first.controlMessages.isEmpty)

    let second = parser.feed(bytes(":3:8:16\n\u{001E}style:\(encodedStyle)\n"))

    #expect(
      second.controlMessages == [
        .resize(.init(width: 12, height: 3), cellPixelSize: .init(width: 8, height: 16)),
        .style(style),
      ]
    )
    #expect(second.events.isEmpty)
  }

  @Test("parser emits key, paste, mouse, and ordinary terminal input")
  func parserEmitsInputEvents() throws {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes(
        "a\u{001E}key:character:%E2%9C%93:5\n"
          + "\u{001E}paste:hello%20world\n"
          + "\u{001E}mouse:scrolled:2:3:none:0:-1:2\n"
      )
    )

    #expect(parsed.controlMessages.isEmpty)
    #expect(
      parsed.events == [
        .key(.init(.character("a"))),
        .key(.init(.character("✓"), modifiers: [.shift, .ctrl])),
        .paste(.init(content: "hello world")),
        .mouse(
          .init(
            kind: .scrolled(deltaX: 0, deltaY: -1),
            location: .cellFallback(CellPoint(x: 2, y: 3)),
            modifiers: [.alt]
          )
        ),
      ]
    )
  }

  @Test("parser ignores malformed web-surface commands")
  func parserIgnoresMalformedCommands() {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes(
        "\u{001E}resize:not-a-number:4\n"
          + "\u{001E}key:unknown:0\n"
          + "\u{001E}paste:%ZZ\n"
          + "\u{001E}mouse:down:1:2:none:0:0:0\n"
      )
    )

    #expect(parsed.events.isEmpty)
    #expect(parsed.controlMessages.isEmpty)
  }

  @Test("transport mode defaults to surface and keeps ANSI aliases explicit")
  func transportModeResolution() {
    #expect(resolveWASITransportMode(environmentValue: { _ in nil }) == .surface)
    #expect(resolveWASITransportMode(environmentValue: { _ in "surface" }) == .surface)
    #expect(resolveWASITransportMode(environmentValue: { _ in "ansi" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "terminal" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "xterm" }) == .ansi)
    #expect(resolveWASITransportMode(environmentValue: { _ in "ghostty-web" }) == .ansi)
  }

  private static func basicSurface() -> RasterSurface {
    RasterSurface(
      size: .init(width: 2, height: 2),
      lines: [
        "OK",
        " ✓",
      ]
    )
  }

  private static func styledSurface() -> RasterSurface {
    let primary = ResolvedTextStyle(
      foregroundColor: .red,
      backgroundColor: .black,
      emphasis: [.bold, .italic, .reverse],
      underlineStyle: .init(pattern: .dash, color: .yellow),
      strikethroughStyle: .init(pattern: .dot, color: .red),
      opacity: 0.75
    )
    let wide = ResolvedTextStyle(
      foregroundColor: .blue,
      backgroundColor: .green,
      emphasis: [.faint],
      underlineStyle: .init(pattern: .curly),
      opacity: 0.5
    )
    let escaped = ResolvedTextStyle(
      foregroundColor: .cyan,
      strikethroughStyle: .init(pattern: .double, color: .magenta)
    )

    return RasterSurface(
      size: .init(width: 4, height: 2),
      cells: [
        [
          .init(character: "A", style: primary),
          .init(character: "界", spanWidth: 2, style: wide),
          .init(character: " ", spanWidth: 0, continuationLeadX: 1, style: wide),
          .init(character: "\"", style: primary),
        ],
        [
          .init(character: "\\", style: escaped),
          .init(character: "\n", style: escaped),
          .init(character: "B"),
          .init(character: " "),
        ],
      ]
    )
  }

  private static func imageSurface() -> RasterSurface {
    let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    return RasterSurface(
      size: .init(width: 4, height: 2),
      lines: [
        "    ",
        "    ",
      ],
      imageAttachments: [
        RasterImageAttachment(
          identity: .init(components: [.named("image")]),
          bounds: .init(origin: .init(x: 1, y: 0), size: .init(width: 3, height: 2)),
          visibleBounds: .init(origin: .init(x: 2, y: 0), size: .init(width: 2, height: 2)),
          source: .data(bytes),
          resolvedReference: .embeddedImage(bytes),
          pixelSize: .init(width: 3, height: 2),
          isResizable: true
        )
      ]
    )
  }

  private static func decodedSurfaceFrame(
    _ output: String
  ) throws -> [String: Any] {
    let prefix = "\u{001E}surface:"
    let line = output.trimmingCharacters(in: .newlines)
    #expect(line.hasPrefix(prefix))
    let json = String(line.dropFirst(prefix.count))
    let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try #require(decoded as? [String: Any])
  }

  private static func fixture(
    _ basename: String
  ) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures")
      .appendingPathComponent("Transport")
      .appendingPathComponent("\(basename).txt")
    return try String(contentsOf: url, encoding: .utf8)
      .replacingOccurrences(of: "\\u001E", with: "\u{001E}")
  }
}

private func bytes(
  _ string: String
) -> [UInt8] {
  Array(string.utf8)
}
