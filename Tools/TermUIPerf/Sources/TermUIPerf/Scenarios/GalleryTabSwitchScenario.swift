@_spi(Runners) import SwiftTUI

/// Reconstructs the gallery's tab / sidebar switch flow without depending on
/// `swift-tui-examples`.
///
/// A real `TabView` uses the gallery's literal-tab style and swaps among six
/// content panes. Clicking a tab changes the `@State` selection, so every switch
/// frame carries both a focus/press change and the dormant-tab archive/restore
/// work whose cost Stage 0 must keep bounded.
///
/// The switch sequence revisits earlier tabs so reuse/restoration of an
/// already-built tab body can be observed (`resolved_reused`). The per-tab
/// content row count is fixed by default (smoke-test friendly) but can be
/// overridden with `SWIFTTUI_PERF_TAB_SWITCH_CONTENT_ROWS` to sweep content
/// size.
public struct GalleryTabSwitchScenario: PerfScenario {
  public let name: PerfScenarioName = .galleryTabSwitch
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 36)
  public let scriptedEvents = [
    "click across tab-bar entries; swap a per-tab content pane while chrome stays stable"
  ]
  public let visualMarkers = ["tab 0 body"]
  public let settlingDescription = "first frame that shows tab 0 body"

  private static let defaultContentRows = 24
  /// Tabs visited in order, including revisits so reuse of an already-built tab
  /// body is exercised.
  private static let switchSequence = [1, 2, 3, 4, 5, 2, 0, 3]

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let contentRows = Self.resolvedContentRows()
    let sequence = Self.switchSequence
    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfGalleryTabSwitchView(contentRows: contentRows)
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

  private static func resolvedContentRows() -> Int {
    resolvedPositiveInt("SWIFTTUI_PERF_TAB_SWITCH_CONTENT_ROWS", default: defaultContentRows)
  }

  private static func resolvedPositiveInt(_ key: String, default fallback: Int) -> Int {
    guard let raw = environmentValue(key), let parsed = Int(raw), parsed > 0 else {
      return fallback
    }
    return parsed
  }
}

extension GalleryTabSwitchScenario: BenchColdRenderable {
  func makeColdRoot() -> PerfGalleryTabSwitchView {
    PerfGalleryTabSwitchView(contentRows: Self.defaultContentRows)
  }
}

struct PerfGalleryTabSwitchView: View {
  let contentRows: Int

  @State private var selectedTab = 0

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("[T0]", value: 0) { PerfGalleryTabBody(tab: 0, contentRows: contentRows) }
      Tab("[T1]", value: 1) { PerfGalleryTabBody(tab: 1, contentRows: contentRows) }
      Tab("[T2]", value: 2) { PerfGalleryTabBody(tab: 2, contentRows: contentRows) }
      Tab("[T3]", value: 3) { PerfGalleryTabBody(tab: 3, contentRows: contentRows) }
      Tab("[T4]", value: 4) { PerfGalleryTabBody(tab: 4, contentRows: contentRows) }
      Tab("[T5]", value: 5) { PerfGalleryTabBody(tab: 5, contentRows: contentRows) }
    }
    .tabViewStyle(.literalTabs)
    .panel(id: "perf-tab-switch")
  }
}

private struct PerfGalleryTabBody: View {
  let tab: Int
  let contentRows: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("tab \(tab) body")
        .foregroundStyle(.tint)
      ForEach(0..<contentRows, id: \.self) { row in
        HStack(spacing: 1) {
          Text("t\(tab) row \(row)")
          Spacer(minLength: 1)
          Text("v\(tab * 1000 + row)")
            .foregroundStyle(.separator)
        }
        .border(.separator)
      }
    }
  }
}
