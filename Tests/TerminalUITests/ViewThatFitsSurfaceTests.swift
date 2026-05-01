import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ViewThatFitsSurfaceTests {
  @Test("unselected candidates do not realize layout-dependent GeometryReader content")
  func unselectedCandidatesDoNotRealizeLayoutDependentGeometryContent() {
    var realizationCount = 0

    let artifacts = DefaultRenderer().render(
      ViewThatFits {
        GeometryReader { proxy in
          countedViewThatFitsGeometryText(
            "wide \(proxy.size.width)x\(proxy.size.height)",
            count: &realizationCount
          )
        }
        .frame(width: 20, height: 1)

        Text("fit")
      }
      .frame(width: 3, height: 1),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 3, height: 1)
    )

    #expect(realizationCount == 0)
    #expect(artifacts.diagnostics.layoutDependentRealizations == 0)
    #expect(artifacts.rasterSurface.lines.contains("fit"))
  }
}

@MainActor
private func countedViewThatFitsGeometryText(
  _ text: String,
  count: inout Int
) -> Text {
  count += 1
  return Text(text)
}
