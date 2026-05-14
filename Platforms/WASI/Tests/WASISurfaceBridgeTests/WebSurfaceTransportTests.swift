import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@_spi(WebHost) @testable import WASISurfaceBridge

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
    let host = WebSurfaceTransport(
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

  @MainActor
  @Test("host writes typed clipboard records")
  func hostWritesTypedClipboardRecords() throws {
    let pipe = Pipe()
    let host = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 2),
      outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
      renderStyle: .init(appearance: .fallback)
    )

    try host.writeClipboard("copy \"this\"")
    pipe.fileHandleForWriting.closeFile()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    pipe.fileHandleForReading.closeFile()

    #expect(output == "\u{001E}clipboard:{\"text\":\"copy \\\"this\\\"\"}\n")
  }

  @Test("encoder emits typed runtime issue records")
  func encoderEmitsRuntimeIssueRecords() throws {
    let issue = RuntimeIssue(
      severity: .warning,
      code: "toolbar.unhostedItems",
      message: "Toolbar item was not rendered",
      identity: Identity(components: ["root", "body"]),
      source: ".toolbarItem(...)"
    )
    let output = WebSurfaceFrameEncoder.encodeRuntimeIssue(issue)
    let prefix = "\u{001E}runtimeIssue:"
    let line = output.trimmingCharacters(in: .newlines)
    #expect(line.hasPrefix(prefix))
    let decoded = try JSONSerialization.jsonObject(
      with: Data(String(line.dropFirst(prefix.count)).utf8)
    )
    let record = try #require(decoded as? [String: Any])
    #expect(record["severity"] as? String == "warning")
    #expect(record["code"] as? String == "toolbar.unhostedItems")
    #expect(record["message"] as? String == "Toolbar item was not rendered")
    #expect(record["identity"] as? String == "root/body")
    #expect(record["source"] as? String == ".toolbarItem(...)")
  }

  @Test("encoder emits v2 accessibility tree with focus and live-region fields")
  func encoderEmitsAccessibilityTree() throws {
    let root = Identity(components: ["root"])
    let group = root.child("group")
    let button = group.child("button")
    let live = group.child("live")
    let mixed = group.child("mixed")
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticPresentationFrame(
          surface: Self.basicSurface(),
          semanticSnapshot: SemanticSnapshot(
            accessibilityNodes: [
              AccessibilityNode(
                identity: group,
                parentIdentity: root,
                rect: .init(origin: .zero, size: .init(width: 2, height: 2)),
                role: .group,
                label: "Actions"
              ),
              AccessibilityNode(
                identity: button,
                parentIdentity: group,
                rect: .init(origin: .zero, size: .init(width: 2, height: 1)),
                role: .button,
                label: "Save",
                hint: "Writes the file",
                cursorAnchor: .init(x: 1, y: 0)
              ),
              AccessibilityNode(
                identity: live,
                parentIdentity: group,
                rect: .init(origin: .init(x: 0, y: 1), size: .init(width: 2, height: 1)),
                role: .status,
                label: "Saved",
                liveRegion: .polite
              ),
              AccessibilityNode(
                identity: mixed,
                parentIdentity: group,
                rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
                role: .group,
                label: "Mixed",
                hidden: true
              ),
            ]
          ),
          focusedIdentity: button
        )
      )
    )

    #expect(frame["version"] as? Int == 2)
    let tree = try #require(frame["accessibilityTree"] as? [[String: Any]])
    #expect(tree.count == 4)

    let groupNode = try #require(tree.first)
    #expect(groupNode["id"] as? String == "root/group")
    #expect(groupNode["parentId"] as? String == "root")
    #expect(groupNode["rect"] as? [Int] == [0, 0, 2, 2])
    #expect(groupNode["role"] as? String == "group")
    #expect(groupNode["label"] as? String == "Actions")
    #expect(groupNode["isFocused"] as? Bool == false)

    let buttonNode = try #require(tree.dropFirst().first)
    #expect(buttonNode["id"] as? String == "root/group/button")
    #expect(buttonNode["parentId"] as? String == "root/group")
    #expect(buttonNode["role"] as? String == "button")
    #expect(buttonNode["label"] as? String == "Save")
    #expect(buttonNode["hint"] as? String == "Writes the file")
    #expect(buttonNode["cursorAnchor"] as? [Int] == [1, 0])
    #expect(buttonNode["isFocused"] as? Bool == true)

    let liveNode = try #require(tree.dropFirst(2).first)
    #expect(liveNode["id"] as? String == "root/group/live")
    #expect(liveNode["role"] as? String == "status")
    #expect(liveNode["liveRegion"] as? String == "polite")
    #expect(liveNode["isFocused"] as? Bool == false)

    let mixedNode = try #require(tree.dropFirst(3).first)
    #expect(mixedNode["id"] as? String == "root/group/mixed")
    #expect(mixedNode["role"] as? String == "group")
    #expect(mixedNode["hidden"] == nil)
  }

  @Test("encoder emits v2 imperative accessibility announcements")
  func encoderEmitsAccessibilityAnnouncements() throws {
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticPresentationFrame(
          surface: Self.basicSurface(),
          semanticSnapshot: SemanticSnapshot(
            accessibilityAnnouncements: [
              AccessibilityAnnouncement(message: "Saved", politeness: .assertive),
              AccessibilityAnnouncement(message: "Queued", politeness: .polite),
            ]
          ),
          focusedIdentity: nil
        )
      )
    )

    #expect(frame["version"] as? Int == 2)
    let announcements = try #require(frame["accessibilityAnnouncements"] as? [[String: Any]])
    #expect(announcements.count == 2)
    #expect(announcements[0]["message"] as? String == "Saved")
    #expect(announcements[0]["politeness"] as? String == "assertive")
    #expect(announcements[1]["message"] as? String == "Queued")
    #expect(announcements[1]["politeness"] as? String == "polite")
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

  @Test("encoder emits presentation damage for browser partial redraws")
  func encoderEmitsPresentationDamage() throws {
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.basicSurface(),
        damage: PresentationDamage(
          textRows: [
            .init(row: 1, columnRanges: [0..<1, 1..<2])
          ]
        )
      )
    )

    let damage = try #require(frame["damage"] as? [String: Any])
    #expect(damage["requiresFullTextRepaint"] as? Bool == false)
    #expect(damage["requiresFullGraphicsReplay"] as? Bool == false)
    let textRows = try #require(damage["textRows"] as? [[Any]])
    let textRow = try #require(textRows.first)
    #expect(textRow.first as? Int == 1)
    #expect(textRow.dropFirst().first as? [[Int]] == [[0, 2]])
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

  @Test("parser maps fractional mouse coordinates to web sub-cell pointer locations")
  func parserMapsFractionalMouseToSubCellPointerLocation() throws {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes(
        "\u{001E}resize:12:3:10:20\n"
          + "\u{001E}mouse:dragged:2.75:1.25:primary:0:0:0\n"
      )
    )

    #expect(
      parsed.controlMessages == [
        .resize(.init(width: 12, height: 3), cellPixelSize: .init(width: 10, height: 20))
      ])

    guard case .mouse(let mouse) = try #require(parsed.events.first) else {
      Issue.record("expected mouse event")
      return
    }

    #expect(mouse.kind == .dragged(.primary))
    #expect(mouse.location.location == Point(x: 2.75, y: 1.25))
    #expect(mouse.location.cell == CellPoint(x: 2, y: 1))
    #expect(mouse.location.rawPixel == PixelPoint(x: 27.5, y: 25))
    #expect(
      mouse.location.precision
        == .subCell(
          source: .webPixels,
          metrics: .init(width: 10, height: 20, source: .reported)
        ))
  }

  @Test("parser preserves out-of-grid fractional coordinates for hit-test rejection")
  func parserPreservesOutOfGridFractionalCoordinates() throws {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes(
        "\u{001E}resize:12:3:10:20\n"
          + "\u{001E}mouse:moved:-0.25:3.10:none:0:0:0\n"
      )
    )

    guard case .mouse(let mouse) = try #require(parsed.events.first) else {
      Issue.record("expected mouse event")
      return
    }

    #expect(mouse.location.location == Point(x: -0.25, y: 3.10))
    #expect(mouse.location.cell == CellPoint(x: -1, y: 3))
    #expect(mouse.location.precision.isSubCell)
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
