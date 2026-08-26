import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Plan 2026-08-25-003 P3: the gallery's Animations tab trips the DEBUG
/// resolved-tree skip oracle (`noteSkippedResolvedTreeProcessing`) under a
/// Tab press or a press-and-drag on its Transitions and Transactions pages
/// (plan 002 §12.1 #1). The oracle names `PickerOption[0]` in the last
/// processed tree against its `Group[0]` wrapper in the fully reused tree.
/// This fixture mirrors the tab's shape at the gallery's 96x96 repro size so
/// the tree can be shrunk until the oracle stops firing.
@MainActor
@Suite(.serialized)
struct SkipOraclePagedWorkbenchTests {
  @Test("Tab, Tab, then a press-and-drag on the transitions page keeps the skip oracle quiet")
  func transitionsPageDragSurvivesSkipOracle() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PagedWorkbenchRoot"),
      size: .init(width: 96, height: 96)
    ) {
      PagedWorkbenchFixture(initialPage: .transitions)
    }
    defer { harness.shutdown() }
    let start = MonotonicInstant.now()
    var now = start
    harness.runLoop.frameClock = { now }

    _ = try harness.pressKey(KeyPress(.tab))
    _ = try harness.renderAfterExternalMutation()
    _ = try harness.pressKey(KeyPress(.tab))
    _ = try harness.renderAfterExternalMutation()

    let origins = try [
      #require(harness.point(forText: "fade out")),
      #require(harness.point(forText: "Transitions")),
      #require(harness.point(forText: "expect:")),
    ]
    for origin in origins {
      _ = try harness.sendMouse(.down(.primary), at: origin)
      for step in 1...2 {
        now = now.advanced(by: .milliseconds(40))
        _ = try harness.sendMouse(
          .dragged(.primary), at: Point(x: origin.x + Double(step), y: origin.y))
      }
      _ = try harness.sendMouse(.up(.primary), at: Point(x: origin.x + 2, y: origin.y))
      _ = try harness.renderAfterExternalMutation()
    }
    #expect(harness.frame.contains("state:"))
  }
}

// MARK: - Fixture (the gallery's paged Animations tab, reduced)

private enum WorkbenchPage: String, CaseIterable, Hashable, Sendable {
  case basics, transitions, matched, keyframes, transactions

  var title: String {
    switch self {
    case .basics: "Basics"
    case .transitions: "Transitions"
    case .matched: "Matched"
    case .keyframes: "Keyframes"
    case .transactions: "Transactions"
    }
  }
}

@MainActor
private struct PagedWorkbenchFixture: View {
  @State private var page: WorkbenchPage
  @State private var showOpacityFigure = true
  @State private var showSlideFigure = true

  init(initialPage: WorkbenchPage) {
    _page = State(initialValue: initialPage)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Animations").foregroundStyle(.foreground)
        Text("Pick a page.").foregroundStyle(.separator)
      }
      Picker("Page", selection: $page) {
        ForEach(WorkbenchPage.allCases, id: \.self) { page in
          Text(page.title).tag(page)
        }
      }
      .pickerStyle(.segmented)
      .frame(height: 4)
      Divider()
      pageContent
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private var pageContent: some View {
    switch page {
    case .transitions:
      pageScroll { transitionSection }
    default:
      pageScroll { Text("\(page.title) page") }
    }
  }

  private var transitionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("2. .transition(...) insertion and removal").foregroundStyle(.muted)
      Text("expect: FADE dissolves in place; SLIDE moves").foregroundStyle(.separator)
      HStack(spacing: 2) {
        Button(showOpacityFigure ? "fade out" : "fade in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showOpacityFigure.toggle()
          }
        }
        Button(showSlideFigure ? "slide out" : "slide in") {
          withAnimation(.easeInOut(duration: .milliseconds(1200))) {
            showSlideFigure.toggle()
          }
        }
      }
      .focusSection()
      HStack(spacing: 2) {
        TextFigure("FADE", font: .smBlock)
          .opacity(0)
          .overlay {
            if showOpacityFigure {
              TextFigure("FADE", font: .smBlock)
                .foregroundStyle(Color.cyan)
                .transition(.opacity)
            }
          }
          .padding(1)
          .clipped()
          .border(set: .double)
        TextFigure("SLIDE", font: .smBlock)
          .opacity(0)
          .overlay {
            if showSlideFigure {
              TextFigure("SLIDE", font: .smBlock)
                .foregroundStyle(Color.yellow)
                .transition(.slide)
            }
          }
          .padding(1)
          .clipped()
          .border(set: .double)
      }
      Text("state: showFade=\(showOpacityFigure) showSlide=\(showSlideFigure)")
        .foregroundStyle(.separator)
    }
  }

  private func pageScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        content()
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
