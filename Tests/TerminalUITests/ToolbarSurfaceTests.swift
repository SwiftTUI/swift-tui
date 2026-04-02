import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ToolbarSurfaceTests {
  @Test("direct renderer uses the full terminal canvas for small roots")
  func directRendererUsesFullTerminalCanvasForSmallRoots() {
    let lines = renderedLines(
      Text("Hello"),
      width: 20,
      height: 4
    )

    #expect(lines.count == 4)
    #expect(lines[0].contains("Hello"))
  }

  @Test("toolbar rows reserve real space above and below the body")
  func toolbarRowsReserveRealSpace() {
    let lines = renderedLines(
      VStack(alignment: .leading, spacing: 0) {
        Text("Body")
      }
      .toolbar(
        placement: .top,
        leading: {
          Text("TopLeft")
        },
        trailing: {
          Text("TopRight")
        }
      )
      .toolbar(
        placement: .bottom,
        leading: {
          Text("BottomLeft")
        },
        trailing: {
          Text("BottomRight")
        }
      ),
      width: 24,
      height: 3
    )

    #expect(lines.count == 3)
    #expect(lines[0].contains("TopLeft"))
    #expect(lines[0].contains("TopRight"))
    #expect(lines[1].contains("Body"))
    #expect(lines[2].contains("BottomLeft"))
    #expect(lines[2].contains("BottomRight"))
  }

  @Test("bottom toolbars anchor to the terminal bottom on tall canvases")
  func bottomToolbarsAnchorToTheTerminalBottomOnTallCanvases() {
    let lines = renderedLines(
      Text("Body")
        .toolbar(
          placement: .bottom,
          leading: {
            Text("BottomLeft")
          },
          trailing: {
            Text("BottomRight")
          }
        ),
      width: 24,
      height: 5
    )

    #expect(lines.count == 5)
    #expect(lines[0].contains("Body"))
    #expect(lines[1...3].allSatisfy { !$0.contains("BottomLeft") && !$0.contains("BottomRight") })
    #expect(lines[4].contains("BottomLeft"))
    #expect(lines[4].contains("BottomRight"))
  }

  @Test("focus-aware toolbar overflow prefers the closest contextual item")
  func focusAwareToolbarOverflowPrefersClosestContextualItem() throws {
    let nearFocused = try #require(
      renderedLines(
        overflowProbeView(),
        focusedIdentity: testIdentity("ToolbarOverflow", "Near")
      ).last
    )
    let farFocused = try #require(
      renderedLines(
        overflowProbeView(),
        focusedIdentity: testIdentity("ToolbarOverflow", "Farther")
      ).last
    )

    #expect(nearFocused.contains("Near"))
    #expect(!nearFocused.contains("Farther"))

    #expect(farFocused.contains("Farther"))
    #expect(!farFocused.contains("Near"))
  }
}

@MainActor
private func overflowProbeView() -> some View {
  VStack(alignment: .leading, spacing: 0) {
    Text("Root A")
    Text("Root B")
      .id(testIdentity("ToolbarOverflow", "Farther"))
      .toolbarItem(alignment: .leading) {
        Text("Farther")
      }
    Text("Root C")
      .id(testIdentity("ToolbarOverflow", "Near"))
      .toolbarItem(alignment: .leading) {
        Text("Near")
      }
  }
  .toolbar(
    placement: .bottom,
    leading: {
      Text("L")
    },
    trailing: {
      Text("R")
    }
  )
}

@MainActor
private func renderedLines<V: View>(
  _ view: V,
  width: Int = 13,
  height: Int = 4,
  focusedIdentity: Identity? = nil
) -> [String] {
  var environmentValues = EnvironmentValues()
  environmentValues.terminalSize = .init(width: width, height: height)
  environmentValues.focusedIdentity = focusedIdentity

  let artifacts = DefaultRenderer().render(
    view,
    context: .init(
      identity: testIdentity("ToolbarOverflow"),
      environmentValues: environmentValues
    ),
    proposal: .init(width: width, height: height)
  )
  return artifacts.rasterSurface.lines
}
