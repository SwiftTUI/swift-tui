import Foundation
import SwiftTUI
import SwiftTUIArguments
import Testing

@testable import SwiftTUITerminalCLI

// The README's "The counter" sample, mirrored line for line (minus the `@main`
// scene wrapper). If the README's Swift block changes, update this copy — the
// tests below compare this view's `RenderOnce` output against the README's
// fenced frame so the two cannot drift apart.
private struct READMECounterView: View {
  @State private var count = 0

  var body: some View {
    VStack(spacing: 1) {
      TextFigure("\(count)", font: .future)
        .frame(minWidth: 14, alignment: .center)
      Button("Increment") { count += 1 }
        .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
struct READMECounterFixtureTests {
  @Test("The README's fenced frame is what its counter sample renders")
  func readmeFrameMatchesRender() throws {
    let readme = try readmeText()
    let expected = try fencedBlock(
      afterMarker: "RenderOnce.print(CounterView(), width: 40)",
      fence: "text",
      in: readme
    )
    let rendered = RenderOnce.render(
      READMECounterView(),
      width: 40,
      options: try SwiftTUIOptions.parse([]),
      environment: ["LANG": "en_US.UTF-8", "NO_COLOR": "1"],
      isStdoutTTY: false
    )
    #expect(withoutTrailingNewlines(rendered) == withoutTrailingNewlines(expected))
  }

  @Test("The README's Swift sample still contains the lines the fixture mirrors")
  func readmeSampleAnchorsPresent() throws {
    let readme = try readmeText()
    let sample = try fencedBlock(afterMarker: "## The counter", fence: "swift", in: readme)
    // Anchor lines that determine the rendered frame. If one goes missing the
    // README sample changed; update `READMECounterView` and the fenced frame.
    #expect(sample.contains("VStack(spacing: 1)"))
    #expect(sample.contains(#"TextFigure("\(count)", font: .future)"#))
    #expect(sample.contains(".frame(minWidth: 14, alignment: .center)"))
    #expect(sample.contains(".buttonStyle(.bordered)"))
    #expect(sample.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
  }

  private func readmeText() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // READMECounterFixtureTests.swift
      .deletingLastPathComponent()  // SwiftTUICLITests/
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // CLI/
      .deletingLastPathComponent()  // Platforms/
    return try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
  }

  private func fencedBlock(afterMarker marker: String, fence: String, in text: String) throws
    -> String
  {
    let markerRange = try #require(
      text.range(of: marker),
      "README marker not found: \(marker)"
    )
    let openRange = try #require(
      text.range(of: "```\(fence)\n", range: markerRange.upperBound..<text.endIndex),
      "no ```\(fence) fence after marker: \(marker)"
    )
    let closeRange = try #require(
      text.range(of: "\n```", range: openRange.upperBound..<text.endIndex),
      "unterminated ```\(fence) fence after marker: \(marker)"
    )
    return String(text[openRange.upperBound..<closeRange.lowerBound])
  }

  private func withoutTrailingNewlines(_ frame: String) -> String {
    var trimmed = Substring(frame)
    while trimmed.last == "\n" { trimmed.removeLast() }
    return String(trimmed)
  }
}
