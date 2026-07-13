import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite
struct WebSurfacePackageTests {
  @Test("package encoder keeps raster-only frames on web-surface version 1")
  func packageEncoderKeepsRasterOnlyFramesOnVersionOne() throws {
    let frame = try decodedSurfaceFrame(WebSurfaceFrameEncoder.encode(Self.basicSurface()))
    #expect(frame["version"] as? Int == 1)
    #expect(frame["accessibilityTree"] == nil)
  }

  @Test("package encoder emits version 2 when accessibility nodes are present")
  func packageEncoderEmitsVersionTwoWithAccessibilityNodes() throws {
    let root = Identity(components: ["root"])
    let child = root.child("button")
    let frame = try decodedSurfaceFrame(
      WebSurfaceFrameEncoder.encode(
        SemanticHostFrame(
          sequence: 7,
          raster: Self.basicSurface(),
          semantics: SemanticSnapshot(
            accessibilityNodes: [
              AccessibilityNode(
                identity: child,
                parentIdentity: root,
                rect: .init(origin: .zero, size: .init(width: 2, height: 1)),
                role: .button,
                label: "Save"
              )
            ]
          ),
          focusedIdentity: child
        )
      )
    )

    #expect(frame["version"] as? Int == 2)
    #expect(frame["sequence"] as? Int == 7)
    let tree = try #require(frame["accessibilityTree"] as? [[String: Any]])
    #expect(tree.count == 1)
    #expect(tree[0]["id"] as? String == "root/button")
    #expect(tree[0]["isFocused"] as? Bool == true)
  }

  @Test("package parser decodes resize, style, key, mouse, and paste records")
  func packageParserDecodesControlAndInputRecords() throws {
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

    let parsed = parser.feed(
      bytes(
        "\u{001E}resize:80:24:9:18\n"
          + "\u{001E}style:\(encodedStyle)\n"
          + "\u{001E}key:character:A:1\n"
          + "\u{001E}mouse:moved:3.5:4.25:none:0:0:2\n"
          + "\u{001E}paste:hello%20web\n"
      )
    )

    #expect(
      parsed.controlMessages == [
        .resize(.init(width: 80, height: 24), cellPixelSize: .init(width: 9, height: 18)),
        .style(style),
      ]
    )
    #expect(parsed.events.count == 3)
    #expect(parsed.events.first == .key(.init(.character("A"), modifiers: [.shift])))
    #expect(parsed.events.last == .paste(.init(content: "hello web")))
    guard case .mouse(let mouse) = parsed.events.dropFirst().first else {
      Issue.record("Expected mouse event.")
      return
    }
    #expect(mouse.kind == .moved)
    #expect(mouse.modifiers == [.alt])
    #expect(mouse.location.location == Point(x: 3.5, y: 4.25))
    #expect(mouse.location.rawPixel == PixelPoint(x: 31.5, y: 76.5))
  }

  @Test("package parser ignores malformed records")
  func packageParserIgnoresMalformedRecords() {
    var parser = WebSurfaceInputParser()
    let parsed = parser.feed(
      bytes(
        "\u{001E}resize:not-a-number:24\n"
          + "\u{001E}style:not-base64\n"
          + "\u{001E}key:unknown:0\n"
          + "\u{001E}mouse:down:1:2:none:0:0:0\n"
          + "\u{001E}paste:%ZZ\n"
      )
    )

    #expect(parsed.events.isEmpty)
    #expect(parsed.controlMessages.isEmpty)
  }

  private static func basicSurface() -> RasterSurface {
    RasterSurface(
      size: .init(width: 2, height: 1),
      lines: ["OK"]
    )
  }
}

private func decodedSurfaceFrame(
  _ output: String
) throws -> [String: Any] {
  let prefix = "\u{001E}surface:"
  let line = output.trimmingCharacters(in: .newlines)
  #expect(line.hasPrefix(prefix))
  let json = String(line.dropFirst(prefix.count))
  let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8))
  return try #require(decoded as? [String: Any])
}

private func bytes(
  _ string: String
) -> [UInt8] {
  Array(string.utf8)
}
