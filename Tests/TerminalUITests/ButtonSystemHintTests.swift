import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Coverage for `Button.systemHint(_:)`. The hint must:
///
/// 1. Render the supplied text alongside the button label.
/// 2. Sit at the trailing edge of the row when the row provides extra
///    width (so a menu of mixed-length items reads `Open       Ctrl+O`
///    rather than `Open Ctrl+O   `).
/// 3. Collapse to a single-cell gap when the row is intrinsically sized
///    (so a toolbar item reads `Save Ctrl+S` flush after the label).
/// 4. Suppress the trailing spacer entirely for nil/empty/whitespace
///    hints — no ghost trailing whitespace.
@MainActor
@Suite
struct ButtonSystemHintTests {
  private let surfaceWidth = 30
  private let surfaceHeight = 1

  private func render(_ view: some View) -> String {
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: surfaceWidth, height: surfaceHeight)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: env,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: surfaceWidth, height: surfaceHeight)
    )
    return artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  @Test("Hint renders alongside the label")
  func hintRendersAlongsideLabel() {
    let surface = render(
      Button("Save") {}
        .systemHint("Ctrl+S")
        .buttonStyle(.plain)
    )
    #expect(surface.contains("Save"))
    #expect(surface.contains("Ctrl+S"))
  }

  @Test("Hint sits at trailing edge when row has spare width")
  func hintRightAlignsWhenRowHasWidth() {
    // .frame(maxWidth: .infinity) gives the row the full surface width,
    // letting Spacer(minLength: 1) push the hint to the right.
    let surface = render(
      Button("Save") {}
        .systemHint("Ctrl+S")
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    )
    let line = surface.split(separator: "\n").first ?? ""
    let labelIndex = line.range(of: "Save")
    let hintIndex = line.range(of: "Ctrl+S")
    #expect(labelIndex != nil)
    #expect(hintIndex != nil)
    if let label = labelIndex, let hint = hintIndex {
      let labelEnd = line.distance(from: line.startIndex, to: label.upperBound)
      let hintStart = line.distance(from: line.startIndex, to: hint.lowerBound)
      // Multi-cell gap proves the spacer expanded against the row's
      // available width — a flush-rendered "Save Ctrl+S" would have
      // hintStart == labelEnd + 1.
      #expect(hintStart > labelEnd + 2)
    }
  }

  @Test("Hint sits flush after label when row is intrinsically sized")
  func hintFlushesWhenRowIsIntrinsic() {
    // .fixedSize() forces the button to its intrinsic width regardless
    // of the available proposal — the HStack's Spacer collapses to its
    // 1-cell minLength.
    let surface = render(
      Button("Save") {}
        .systemHint("Ctrl+S")
        .buttonStyle(.plain)
        .fixedSize()
    )
    let line = surface.split(separator: "\n").first ?? ""
    guard let labelRange = line.range(of: "Save"),
      let hintRange = line.range(of: "Ctrl+S")
    else {
      Issue.record("expected both 'Save' and 'Ctrl+S' on first line")
      return
    }
    let labelEnd = line.distance(from: line.startIndex, to: labelRange.upperBound)
    let hintStart = line.distance(from: line.startIndex, to: hintRange.lowerBound)
    // Single 1-cell spacer between label and hint when the row is
    // intrinsically sized. Allow the gap to be 1 or 2 cells (chrome
    // padding can add a single cell).
    #expect(hintStart - labelEnd >= 1)
    #expect(hintStart - labelEnd <= 2)
  }

  @Test("Nil, empty, and whitespace-only hints suppress the suffix entirely")
  func emptyHintsSuppressSuffix() {
    let nilHint = render(
      Button("Save") {}
        .systemHint(nil)
        .buttonStyle(.plain)
    )
    let emptyHint = render(
      Button("Save") {}
        .systemHint("")
        .buttonStyle(.plain)
    )
    let whitespaceHint = render(
      Button("Save") {}
        .systemHint("   \t \n")
        .buttonStyle(.plain)
    )
    let plain = render(
      Button("Save") {}
        .buttonStyle(.plain)
    )

    // Each suppressed-hint render trims to the same content as the
    // unmodified Button — the suffix is fully absent.
    #expect(nilHint.trimmingTrailingSpaces == plain.trimmingTrailingSpaces)
    #expect(emptyHint.trimmingTrailingSpaces == plain.trimmingTrailingSpaces)
    #expect(whitespaceHint.trimmingTrailingSpaces == plain.trimmingTrailingSpaces)
  }

  @Test("normalizeSystemHint trims whitespace and folds empty to nil")
  func normalizeSystemHintTrimsWhitespace() {
    #expect(Button<Text>.normalizeSystemHint(nil) == nil)
    #expect(Button<Text>.normalizeSystemHint("") == nil)
    #expect(Button<Text>.normalizeSystemHint("   ") == nil)
    #expect(Button<Text>.normalizeSystemHint("  Ctrl+S  ") == "Ctrl+S")
    #expect(Button<Text>.normalizeSystemHint("Ctrl+S") == "Ctrl+S")
    #expect(Button<Text>.normalizeSystemHint("\tCtrl+S\n") == "Ctrl+S")
  }

  @Test("Toolbar item carries the systemHint through to its rendered button")
  func toolbarItemPropagatesSystemHint() {
    let panel = Panel(id: "outer") {
      Text("body")
        .toolbarItem(
          ToolbarItemConfig(
            title: "Save",
            systemHint: "Ctrl+S",
            action: {}
          )
        )
    }
    .toolbar(style: DefaultTopToolbarStyle())

    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: surfaceWidth, height: 6)
    let surface = DefaultRenderer().render(
      panel,
      context: .init(
        identity: testIdentity("ToolbarRoot"),
        environmentValues: env,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: surfaceWidth, height: 6)
    )
    .rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Save"))
    #expect(surface.contains("Ctrl+S"))
  }

  @Test("ToolbarItemConfig normalizes its systemHint at construction")
  func toolbarItemConfigNormalizesHint() {
    let trimmed = ToolbarItemConfig(
      title: "Save",
      systemHint: "  Ctrl+S  ",
      action: {}
    )
    #expect(trimmed.systemHint == "Ctrl+S")

    let blank = ToolbarItemConfig(
      title: "Save",
      systemHint: "   ",
      action: {}
    )
    #expect(blank.systemHint == nil)

    let nilHint = ToolbarItemConfig(
      title: "Save",
      systemHint: nil,
      action: {}
    )
    #expect(nilHint.systemHint == nil)
  }
}

extension String {
  fileprivate var trimmingTrailingSpaces: String {
    split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        var end = line.endIndex
        while end > line.startIndex {
          let prior = line.index(before: end)
          if line[prior] != " " { break }
          end = prior
        }
        return String(line[line.startIndex..<end])
      }
      .joined(separator: "\n")
  }
}
