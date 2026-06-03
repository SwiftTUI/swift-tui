import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import WASISurfaceBridge

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

  @Test("host semantic present writes damage and incremental metrics")
  func hostSemanticPresentWritesDamageAndIncrementalMetrics() throws {
    let pipe = Pipe()
    let host = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 2),
      outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
      renderStyle: .init(appearance: .fallback)
    )
    let damage = PresentationDamage(
      textRows: [.init(row: 1, columnRanges: [0..<1])]
    )

    let metrics = try host.present(
      SemanticHostFrame(
        sequence: 31,
        raster: Self.basicSurface(),
        semantics: .init(),
        focusedIdentity: nil,
        rasterDamage: damage
      )
    )

    pipe.fileHandleForWriting.closeFile()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    pipe.fileHandleForReading.closeFile()
    let frame = try Self.decodedSurfaceFrame(output)
    let decodedDamage = try #require(frame["damage"] as? [String: Any])

    #expect(decodedDamage["requiresFullTextRepaint"] as? Bool == false)
    #expect(decodedDamage["requiresFullGraphicsReplay"] as? Bool == false)
    #expect(metrics.linesTouched == 1)
    #expect(metrics.cellsChanged == 1)
    #expect(metrics.strategy == .incremental)
  }

  @Test("encoder emits frame diagnostics as typed records")
  func encoderEmitsFrameDiagnosticRecords() throws {
    let output = WebSurfaceFrameEncoder.encodeFrameDiagnostic(
      Self.frameDiagnosticRecord(frameNumber: 42, causeSummary: "render \"tick\"")
    )
    let record = try Self.decodedTypedRecord(output, prefix: "\u{001E}frameDiagnostic:")

    #expect(record["format"] as? String == "swift-tui-frame-diagnostics-v1")
    let header = try #require(record["header"] as? [String])
    let fields = try #require(record["fields"] as? [String])
    #expect(header.first == "frame")
    #expect(fields.first == "42")
    #expect(header.contains("causes"))
    #expect(fields[header.firstIndex(of: "causes") ?? 0] == "render \"tick\"")
  }

  @Test("host writes frame diagnostic records")
  func hostWritesFrameDiagnosticRecords() throws {
    let pipe = Pipe()
    let host = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 2),
      outputFileDescriptor: pipe.fileHandleForWriting.fileDescriptor,
      renderStyle: .init(appearance: .fallback)
    )

    try host.notifyFrameDiagnostic(Self.frameDiagnosticRecord(frameNumber: 7))
    pipe.fileHandleForWriting.closeFile()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    pipe.fileHandleForReading.closeFile()
    let record = try Self.decodedTypedRecord(output, prefix: "\u{001E}frameDiagnostic:")
    let fields = try #require(record["fields"] as? [String])

    #expect(fields.first == "7")
  }

  @Test("delta-enabled encoder sends the first frame as a full frame")
  func deltaEnabledEncoderSendsFirstFrameFull() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.basicSurface(),
        damage: PresentationDamage(textRows: [.init(row: 1, columnRanges: [0..<1])]),
        state: &state
      )
    )

    #expect(frame["version"] as? Int == 1)
    #expect(frame["encoding"] == nil)
    #expect(frame["rows"] != nil)
    #expect(frame["deltaRows"] == nil)
  }

  @Test("delta-disabled encoder does not populate baseline state")
  func deltaDisabledEncoderDoesNotPopulateBaselineState() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: false)

    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.imageSurface(),
        damage: PresentationDamage(textRows: [.init(row: 0)]),
        state: &state
      )
    )

    #expect(frame["encoding"] == nil)
    #expect(frame["rows"] != nil)
    #expect(frame["deltaRows"] == nil)
    #expect(state.knownImageIDs.isEmpty == false)
    #expect(state.hasBaseline == false)
    #expect(state.baselineSize == nil)
  }

  @Test("delta-enabled encoder emits dirty rows after a baseline")
  func deltaEnabledEncoderEmitsDirtyRowsAfterBaseline() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(Self.basicSurface(), state: &state)

    let damage = PresentationDamage(textRows: [.init(row: 1, columnRanges: [1..<2])])
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.changedSurface(),
        sequence: 2,
        semanticSnapshot: .init(),
        focusedIdentity: nil,
        damage: damage,
        state: &state
      )
    )

    #expect(frame["version"] as? Int == 3)
    #expect(frame["encoding"] as? String == "delta")
    #expect(frame["sequence"] as? Int == 2)
    #expect(frame["rows"] == nil)
    let deltaRows = try #require(frame["deltaRows"] as? [[Any]])
    #expect(deltaRows.count == 1)
    #expect(deltaRows.first?.first as? Int == 1)
    let decodedDamage = try #require(frame["damage"] as? [String: Any])
    let textRows = try #require(decodedDamage["textRows"] as? [[Any]])
    #expect(textRows.first?.first as? Int == 1)
    #expect(textRows.first?.dropFirst().first as? [[Int]] == [[1, 2]])
  }

  @Test("delta-enabled encoder emits duplicate damaged rows once")
  func deltaEnabledEncoderEmitsDuplicateDamagedRowsOnce() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(Self.basicSurface(), state: &state)
    var damage = PresentationDamage(textRows: [.init(row: 1, columnRanges: [1..<2])])
    damage.textRows.append(.init(row: 1, columnRanges: [0..<1]))
    damage.textRows.append(.init(row: -1))
    damage.textRows.append(.init(row: 2))

    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.changedSurface(),
        damage: damage,
        state: &state
      )
    )

    let deltaRows = try #require(frame["deltaRows"] as? [[Any]])
    #expect(deltaRows.count == 1)
    #expect(deltaRows.first?.first as? Int == 1)
  }

  @Test("delta-enabled encoder falls back to full frames for full repaint damage")
  func deltaEnabledEncoderFallsBackForFullRepaintDamage() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(Self.basicSurface(), state: &state)

    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.changedSurface(),
        damage: PresentationDamage(
          textRows: [.init(row: 1, columnRanges: [1..<2])],
          requiresFullTextRepaint: true
        ),
        state: &state
      )
    )

    #expect(frame["encoding"] == nil)
    #expect(frame["rows"] != nil)
    #expect(frame["deltaRows"] == nil)
  }

  @Test("delta-enabled encoder falls back to full frames when surface size changes")
  func deltaEnabledEncoderFallsBackWhenSurfaceSizeChanges() throws {
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(Self.basicSurface(), state: &state)

    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        Self.wideSurface(),
        damage: PresentationDamage(textRows: [.init(row: 0)]),
        state: &state
      )
    )

    #expect(frame["width"] as? Int == 4)
    #expect(frame["encoding"] == nil)
    #expect(frame["rows"] != nil)
    #expect(frame["deltaRows"] == nil)
  }

  @Test("delta frame is smaller than an equivalent full frame for one dirty row")
  func deltaFrameIsSmallerThanEquivalentFullFrameForOneDirtyRow() throws {
    let base = Self.largeSurface(dirtyRowText: "unchanged")
    let changed = Self.largeSurface(dirtyRowText: "changed  ")
    let damage = PresentationDamage(textRows: [.init(row: 5, columnRanges: [0..<8])])
    var state = WebSurfaceFrameEncodingState(deltaEnabled: true)
    _ = WebSurfaceFrameEncoder.encode(base, state: &state)

    let delta = WebSurfaceFrameEncoder.encode(changed, damage: damage, state: &state)
    let full = WebSurfaceFrameEncoder.encode(changed, damage: damage)

    #expect(delta.utf8.count < full.utf8.count)
  }

  @Test("host exposes web sub-cell pointer capabilities before reported metrics arrive")
  func hostExposesWebSubCellPointerCapabilitiesBeforeMetrics() {
    let host = WebSurfaceTransport(
      surfaceSize: .init(width: 2, height: 2),
      renderStyle: .init(appearance: .fallback)
    )

    #expect(
      host.pointerInputCapabilities
        == PointerInputCapabilities(
          precision: .subCell(source: .webPixels, metrics: .estimated),
          supportsHover: true
        ))

    host.updateSurfaceSize(.init(width: 4, height: 2), cellPixelSize: nil)

    #expect(
      host.pointerInputCapabilities
        == PointerInputCapabilities(
          precision: .subCell(source: .webPixels, metrics: .estimated),
          supportsHover: true
        ))
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
        SemanticHostFrame(
          sequence: 11,
          raster: Self.basicSurface(),
          semantics: SemanticSnapshot(
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
    #expect(frame["sequence"] as? Int == 11)
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
        SemanticHostFrame(
          sequence: 12,
          raster: Self.basicSurface(),
          semantics: SemanticSnapshot(
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
    #expect(frame["sequence"] as? Int == 12)
    let announcements = try #require(frame["accessibilityAnnouncements"] as? [[String: Any]])
    #expect(announcements.count == 2)
    #expect(announcements[0]["message"] as? String == "Saved")
    #expect(announcements[0]["politeness"] as? String == "assertive")
    #expect(announcements[1]["message"] as? String == "Queued")
    #expect(announcements[1]["politeness"] as? String == "polite")
  }

  @Test("encoder emits per-region scroll extents for scroll-chaining")
  func encoderEmitsScrollRegions() throws {
    let root = Identity(components: ["root"])
    let list = root.child("list")
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticHostFrame(
          sequence: 13,
          raster: Self.basicSurface(),
          semantics: SemanticSnapshot(
            scrollRoutes: [
              ScrollRoute(
                identity: list,
                viewportRect: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 3)),
                contentBounds: .init(origin: .zero, size: .init(width: 4, height: 10)),
                contentOffset: .init(x: 0, y: 2)
              )
            ]
          ),
          focusedIdentity: nil
        )
      )
    )

    #expect(frame["version"] as? Int == 2)
    let regions = try #require(frame["scrollRegions"] as? [[String: Any]])
    #expect(regions.count == 1)
    let region = try #require(regions.first)
    #expect(region["id"] as? String == "root/list")
    #expect(region["rect"] as? [Int] == [0, 1, 4, 3])
    #expect(region["offset"] as? [Int] == [0, 2])
    #expect(region["content"] as? [Int] == [4, 10])
  }

  @Test("encoder omits scrollRegions when there are no scrollable regions")
  func encoderOmitsScrollRegionsWhenEmpty() throws {
    let frame = try Self.decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticHostFrame(
          sequence: 14,
          raster: Self.basicSurface(),
          semantics: SemanticSnapshot(),
          focusedIdentity: nil
        )
      )
    )

    #expect(frame["scrollRegions"] == nil)
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
        foregroundColor: try! .hex("#102030"),
        backgroundColor: try! .hex("#405060"),
        tintColor: try! .hex("#708090"),
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
            location: .subCell(
              location: Point(x: 2, y: 3),
              source: .webPixels,
              metrics: .estimated
            ),
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

  @Test("parser preserves fractional web coordinates before cell metrics are reported")
  func parserPreservesFractionalWebCoordinatesBeforeMetrics() throws {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes("\u{001E}mouse:moved:2.75:1.25:none:0:0:0\n")
    )

    guard case .mouse(let mouse) = try #require(parsed.events.first) else {
      Issue.record("expected mouse event")
      return
    }

    #expect(mouse.location.location == Point(x: 2.75, y: 1.25))
    #expect(mouse.location.cell == CellPoint(x: 2, y: 1))
    #expect(mouse.location.rawPixel == nil)
    #expect(
      mouse.location.precision
        == .subCell(source: .webPixels, metrics: .estimated))
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

  private static func changedSurface() -> RasterSurface {
    RasterSurface(
      size: .init(width: 2, height: 2),
      lines: [
        "OK",
        " !",
      ]
    )
  }

  private static func wideSurface() -> RasterSurface {
    RasterSurface(
      size: .init(width: 4, height: 2),
      lines: [
        "OK  ",
        " !  ",
      ]
    )
  }

  private static func largeSurface(dirtyRowText: String) -> RasterSurface {
    let paddedDirtyRow = String(dirtyRowText.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
    return RasterSurface(
      size: .init(width: 8, height: 10),
      lines: (0..<10).map { row in
        row == 5 ? paddedDirtyRow : "row\(row)    ".prefix(8).description
      }
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

  private static func decodedTypedRecord(
    _ output: String,
    prefix: String
  ) throws -> [String: Any] {
    let line = output.trimmingCharacters(in: .newlines)
    #expect(line.hasPrefix(prefix))
    let json = String(line.dropFirst(prefix.count))
    let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try #require(decoded as? [String: Any])
  }

  private static func frameDiagnosticRecord(
    frameNumber: Int,
    causeSummary: String = "render"
  ) -> FrameDiagnosticRecord {
    FrameDiagnosticRecord(
      frameNumber: frameNumber,
      causeSummary: causeSummary,
      renderGenerations: .init(render: .init(UInt64(frameNumber))),
      desiredGeneration: UInt64(frameNumber),
      presentationStrategy: "incremental",
      presentationDuration: .zero,
      totalFrameDuration: .zero
    )
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
