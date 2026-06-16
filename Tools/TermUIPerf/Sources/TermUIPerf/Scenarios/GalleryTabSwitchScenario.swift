@_spi(Runners) import SwiftTUI

/// Reconstructs the gallery's tab / sidebar switch flow without depending on
/// `swift-tui-examples`.
///
/// A stable tab bar of buttons sits above a content pane that is swapped
/// wholesale on each switch. Clicking a tab changes the `@State` selection, so
/// every switch frame carries both a focus/press change (the click target) and a
/// structural content swap (a different per-tab subtree resolves while the tab
/// bar and chrome stay reuse-eligible). This is the committed framework-only
/// stand-in for the missing "real gallery tab-switch path" called out in the
/// 2026-06-16 perf signal representativeness pass — the most common
/// chrome-driven focus-navigation interaction in the example apps.
///
/// The switch sequence revisits earlier tabs so reuse of an already-built tab
/// body can be observed (`resolved_reused`). The per-tab content row count is
/// fixed by default (smoke-test friendly) but can be overridden with
/// `TERMUI_PERF_TAB_SWITCH_CONTENT_ROWS` to sweep content size, and the tab
/// count with `TERMUI_PERF_TAB_SWITCH_TABS`.
public struct GalleryTabSwitchScenario: PerfScenario {
  public let name: PerfScenarioName = .galleryTabSwitch
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 36)
  public let scriptedEvents = [
    "click across tab-bar entries; swap a per-tab content pane while chrome stays stable"
  ]
  public let visualMarkers = ["tab 0 body"]
  public let settlingDescription = "first frame that shows tab 0 body"

  private static let defaultTabCount = 6
  private static let defaultContentRows = 24
  /// Tabs visited in order, including revisits so reuse of an already-built tab
  /// body is exercised. Filtered to the resolved tab count at run time.
  private static let switchSequence = [1, 2, 3, 4, 5, 2, 0, 3]

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let tabCount = Self.resolvedTabCount()
    let contentRows = Self.resolvedContentRows()
    let sequence = Self.switchSequence.filter { $0 < tabCount }
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfGalleryTabSwitchView(tabCount: tabCount, contentRows: contentRows)
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "tab 0 body")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      for target in sequence {
        let cell = try driver.cell(containing: "[T\(target)]")
        driver.sendClick(at: cell)
        let switched = try await driver.waitForFrame(
          containing: "tab \(target) body",
          afterFrame: lastFrame
        )
        lastFrame = switched.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      let finalTab = sequence.last ?? 0
      return [
        PerfEventRecord(
          eventID: "gallery-tab-switch",
          eventType: "tab_switch",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "tab \(finalTab) body",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedTabCount() -> Int {
    resolvedPositiveInt("TERMUI_PERF_TAB_SWITCH_TABS", default: defaultTabCount)
  }

  private static func resolvedContentRows() -> Int {
    resolvedPositiveInt("TERMUI_PERF_TAB_SWITCH_CONTENT_ROWS", default: defaultContentRows)
  }

  private static func resolvedPositiveInt(_ key: String, default fallback: Int) -> Int {
    guard let raw = environmentValue(key), let parsed = Int(raw), parsed > 0 else {
      return fallback
    }
    return parsed
  }
}

private struct PerfGalleryTabSwitchView: View {
  let tabCount: Int
  let contentRows: Int

  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Gallery tab switch workload")
        .foregroundStyle(.tint)
      tabBar
      Divider()
      // Swapped wholesale on each selection: the per-tab body is a distinct
      // subtree, so a switch re-resolves the content while the tab bar above
      // stays reuse-eligible.
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(1)
    .panel(id: "perf-tab-switch")
  }

  private var tabBar: some View {
    HStack(spacing: 1) {
      ForEach(0..<tabCount, id: \.self) { index in
        Button("[T\(index)]\(index == selectedTab ? "*" : "")") {
          selectedTab = index
        }
      }
      Spacer(minLength: 1)
      Text("on \(selectedTab)")
        .foregroundStyle(.muted)
    }
  }

  private var tabContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("tab \(selectedTab) body")
        .foregroundStyle(.tint)
      ForEach(0..<contentRows, id: \.self) { row in
        HStack(spacing: 1) {
          Text("t\(selectedTab) row \(row)")
          Spacer(minLength: 1)
          Text("v\(selectedTab * 1000 + row)")
            .foregroundStyle(.separator)
        }
        .border(.separator)
      }
    }
  }
}
