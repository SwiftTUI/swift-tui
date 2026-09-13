import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Tab-view presentations pass through the shared misuse channel: an invalid
/// value reports one `style.invalidPresentation` issue and the automatic
/// presentation drives that resolve, while the style's body still renders.
@MainActor
@Suite(.serialized)
struct TabViewStyleValidationTests {
  private struct InsetOverflowStyle: TabViewStyle {
    var inset: Int
    func presentation(for configuration: TabViewStyleConfiguration) -> TabViewStylePresentation {
      .init(
        stripHeight: 3, visibleOptionIndices: [0],
        overflowMenu: .init(
          triggerLeadingWidth: 9, overflowIndices: [1], isExpanded: true,
          selectedOverflowIndex: nil, focusedOverflowIndex: nil, triggerLabel: "▴",
          borderInset: inset))
    }
    func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
      LiteralTabsTabViewStyle().makeBody(configuration: configuration)
    }
  }

  @Test("custom overflow border clearance moves the rendered row inside the menu")
  func overflowInsetIsRendered() throws {
    func frame(_ inset: Int) -> RenderSnapshot {
      DefaultRenderer().render(
        TabView(selection: .constant(0)) {
          Tab("Alpha", value: 0) { Text("Content") }
          Tab("Beta", value: 1) { Text("Other") }
        }.tabViewStyle(InsetOverflowStyle(inset: inset)),
        context: .init(identity: testIdentity("OverflowClearance")),
        proposal: .init(width: 40, height: 14))
    }
    let baseline = frame(1)
    let inset = frame(2)
    let baselineRow = try #require(baseline.rasterSurface.lines.firstIndex { $0.contains("Beta") })
    let insetRow = try #require(inset.rasterSurface.lines.firstIndex { $0.contains("Beta") })
    #expect(insetRow == baselineRow + 1)
    #expect(styleIssues(in: inset).isEmpty)
  }

  /// Resolves a fixed presentation and renders it through the automatic
  /// body, so a fallback is visible as the automatic strip.
  private struct FixedPresentationTabViewStyle: TabViewStyle {
    let label: String
    let fixed: TabViewStylePresentation

    var snapshotLabel: String { label }

    @MainActor
    func presentation(
      for _: TabViewStyleConfiguration
    ) -> TabViewStylePresentation {
      fixed
    }

    @MainActor
    func makeBody(configuration: TabViewStyleBodyConfiguration) -> some View {
      AutomaticTabViewStyle().makeBody(configuration: configuration)
    }
  }

  private func render(style: AnyTabViewStyle, identity: String) -> RenderSnapshot {
    DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Tab("Alpha", value: "home") {
          Text("Home content")
        }

        Tab("Beta", value: "settings") {
          Text("Settings content")
        }
      }
      .tabViewStyle(style)
      .id(testIdentity("Tabs")),
      context: .init(identity: testIdentity(identity)),
      proposal: .init(width: 40, height: 4)
    )
  }

  private func surface(of artifacts: RenderSnapshot) -> String {
    artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  private func styleIssues(in artifacts: RenderSnapshot) -> [RuntimeIssue] {
    artifacts.diagnostics.runtime.issues.filter { $0.code == "style.invalidPresentation" }
  }

  @Test("an out-of-range visible index renders the automatic strip and reports one issue")
  func outOfRangeVisibleIndexFallsBack() throws {
    let style = FixedPresentationTabViewStyle(
      label: "OutOfRangeTabs",
      fixed: .init(stripHeight: 2, visibleOptionIndices: [0, 7], overflowMenu: nil)
    )
    let artifacts = render(style: AnyTabViewStyle(style), identity: "TabsOutOfRange")
    let automatic = render(style: .automatic, identity: "TabsOutOfRangeBaseline")
    let rendered = surface(of: artifacts)
    #expect(rendered.contains("Alpha"))
    #expect(rendered.contains("Beta"))
    #expect(rendered.contains("Home content"))
    #expect(artifacts.rasterSurface == automatic.rasterSurface)
    let issues = styleIssues(in: artifacts)
    let issue = try #require(issues.first)
    #expect(issues.count == 1)
    #expect(issue.message.contains("TabViewStyle OutOfRangeTabs"))
    #expect(issue.message.contains("visibleOptionIndices"))
    #expect(issue.identity == testIdentity("Tabs"))
  }

  @Test("a negative strip height renders the automatic strip and reports one issue")
  func negativeStripHeightFallsBack() throws {
    let style = FixedPresentationTabViewStyle(
      label: "NegativeStripTabs",
      fixed: .init(stripHeight: -1, visibleOptionIndices: [0, 1], overflowMenu: nil)
    )
    let artifacts = render(style: AnyTabViewStyle(style), identity: "TabsNegativeStrip")
    let automatic = render(style: .automatic, identity: "TabsNegativeStripBaseline")
    #expect(artifacts.rasterSurface == automatic.rasterSurface)
    let issues = styleIssues(in: artifacts)
    let issue = try #require(issues.first)
    #expect(issues.count == 1)
    #expect(issue.message.contains("stripHeight"))
  }

  @Test("a valid custom presentation is honored without an issue")
  func validCustomPresentationIsHonored() {
    let style = FixedPresentationTabViewStyle(
      label: "SecondOnlyTabs",
      fixed: .init(stripHeight: 2, visibleOptionIndices: [1], overflowMenu: nil)
    )
    let artifacts = render(style: AnyTabViewStyle(style), identity: "TabsSecondOnly")
    let rendered = surface(of: artifacts)
    #expect(rendered.contains("Beta"))
    #expect(!rendered.contains("Alpha"))
    #expect(styleIssues(in: artifacts).isEmpty)
  }

  @Test("validation names each rule the value breaks")
  func validationProblemsCoverEachRule() {
    func overflow(_ indices: [Int]) -> TabViewOverflowMenuPresentation {
      .init(
        triggerLeadingWidth: 0, overflowIndices: indices, isExpanded: false,
        selectedOverflowIndex: nil, focusedOverflowIndex: nil, triggerLabel: "…")
    }
    let valid = TabViewStylePresentation(
      stripHeight: 3, visibleOptionIndices: [0, 1], overflowMenu: overflow([2, 3]))
    #expect(valid.validationProblems(optionCount: 4).isEmpty)
    for inset in [-1, Int.max] {
      var invalidInset = valid
      invalidInset.overflowMenu?.borderInset = inset
      #expect(
        invalidInset.validationProblems(optionCount: 4)
          .contains { $0.contains("borderInset") })
    }
    #expect(valid.validationProblems(optionCount: 3).count == 1)
    let repeated = TabViewStylePresentation(
      stripHeight: 0, visibleOptionIndices: [1, 1], overflowMenu: nil)
    #expect(repeated.validationProblems(optionCount: 2).count == 1)
    let negative = TabViewStylePresentation(
      stripHeight: -1, visibleOptionIndices: [-1], overflowMenu: nil)
    #expect(negative.validationProblems(optionCount: 2).count == 2)
    let overlapping = TabViewStylePresentation(
      stripHeight: 1, visibleOptionIndices: [0, 1], overflowMenu: overflow([1, 1, 5]))
    #expect(overlapping.validationProblems(optionCount: 3).count == 3)
  }
}
