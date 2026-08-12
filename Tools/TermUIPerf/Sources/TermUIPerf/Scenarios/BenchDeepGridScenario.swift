@_spi(Runners) import SwiftTUI

/// `bench-deep-grid` (plan 2026-08-11-005 D2): a depth-8 alternating
/// `VStack`/`HStack` tree, branching factor 2 per level — 256 `Text` leaves
/// labeled `g<r>.<c>` on a 16x16 grid — with one counter leaf spliced at the
/// deepest spine (leaf position 0,0). The warm drive clicks it 8 times,
/// closed loop: every click invalidates the root path and re-descends the
/// 8-level spine, pinning resolve descent, measure/place spine arithmetic,
/// and the plan-004 branching-factor counters on a deep, regular tree.
///
/// The tree is fully typed — eight `DeepGridSplit` generic levels, no
/// erasure seams — so the measured descent is container arithmetic, not
/// `AnyView` bridging.
public struct BenchDeepGridScenario: PerfScenario {
  public let name: PerfScenarioName = .benchDeepGrid
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 40)
  public let scriptedEvents = [
    "click the counter leaf at the deepest grid spine 8 times, closed loop"
  ]
  public let visualMarkers = ["count 0"]
  public let settlingDescription = "first frame that shows count 0"

  private static let clickCount = 8

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfDeepGridView()
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "count 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0
      for click in 1...Self.clickCount {
        let cell = try driver.cell(containing: "inc")
        driver.sendClick(at: cell)
        let matching = try await driver.waitForFrame(
          containing: "count \(click)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
      }
      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "bench-deep-grid-clicks",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "count \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }
}

extension BenchDeepGridScenario: BenchColdRenderable {
  func makeColdRoot() -> PerfDeepGridView {
    PerfDeepGridView()
  }
}

struct PerfDeepGridView: View {
  @State private var count = 0

  var body: some View {
    DeepGridBuilder.root(counterValue: count) {
      count += 1
    }
  }
}

/// The either-type leaf: position (0,0) is the counter, everything else a
/// plain labeled `Text`. One uniform type keeps the eight generic levels
/// fully typed.
private struct DeepGridLeaf: View {
  let row: Int
  let column: Int
  let counterValue: Int
  let increment: (@MainActor @Sendable () -> Void)?

  var body: some View {
    if let increment {
      VStack(alignment: .leading, spacing: 0) {
        Text("count \(counterValue)")
        Button("inc", action: increment)
      }
    } else {
      Text("g\(row).\(column)")
    }
  }
}

/// One binary split level. Even depths split rows with a `VStack`, odd
/// depths split columns with an `HStack` — the D2 alternation.
private struct DeepGridSplit<Child: View>: View {
  let horizontal: Bool
  let first: Child
  let second: Child

  var body: some View {
    if horizontal {
      HStack(alignment: .top, spacing: 0) {
        first
        second
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        first
        second
      }
    }
  }
}

/// Builds the depth-8 tree bottom-up with one explicitly named type per
/// level: value recursion cannot produce increasingly nested generic types,
/// so the unrolling is spelled out once here.
@MainActor
private enum DeepGridBuilder {
  typealias L1 = DeepGridSplit<DeepGridLeaf>
  typealias L2 = DeepGridSplit<L1>
  typealias L3 = DeepGridSplit<L2>
  typealias L4 = DeepGridSplit<L3>
  typealias L5 = DeepGridSplit<L4>
  typealias L6 = DeepGridSplit<L5>
  typealias L7 = DeepGridSplit<L6>
  typealias L8 = DeepGridSplit<L7>

  /// The cell-range one subtree covers.
  struct Region {
    var rowBase: Int
    var columnBase: Int
    var rows: Int
    var columns: Int
  }

  static func root(counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void) -> L8 {
    l8(
      Region(rowBase: 0, columnBase: 0, rows: 16, columns: 16),
      counterValue: counterValue,
      increment: increment
    )
  }

  /// Splits `region` for `depth`: even depths split rows (vertical), odd
  /// depths split columns (horizontal), so the root (8) is a `VStack`.
  private static func split<Child: View>(
    depth: Int,
    _ region: Region,
    child: (Region) -> Child
  ) -> DeepGridSplit<Child> {
    if depth % 2 == 1 {
      let half = region.columns / 2
      var left = region
      left.columns = half
      var right = region
      right.columnBase += half
      right.columns = region.columns - half
      return DeepGridSplit(horizontal: true, first: child(left), second: child(right))
    }
    let half = region.rows / 2
    var top = region
    top.rows = half
    var bottom = region
    bottom.rowBase += half
    bottom.rows = region.rows - half
    return DeepGridSplit(horizontal: false, first: child(top), second: child(bottom))
  }

  private static func leaf(
    _ region: Region,
    counterValue: Int,
    increment: @escaping @MainActor @Sendable () -> Void
  ) -> DeepGridLeaf {
    DeepGridLeaf(
      row: region.rowBase,
      column: region.columnBase,
      counterValue: counterValue,
      increment: region.rowBase == 0 && region.columnBase == 0 ? increment : nil
    )
  }

  private static func l1(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L1 {
    split(depth: 1, region) { leaf($0, counterValue: counterValue, increment: increment) }
  }

  private static func l2(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L2 {
    split(depth: 2, region) { l1($0, counterValue: counterValue, increment: increment) }
  }

  private static func l3(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L3 {
    split(depth: 3, region) { l2($0, counterValue: counterValue, increment: increment) }
  }

  private static func l4(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L4 {
    split(depth: 4, region) { l3($0, counterValue: counterValue, increment: increment) }
  }

  private static func l5(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L5 {
    split(depth: 5, region) { l4($0, counterValue: counterValue, increment: increment) }
  }

  private static func l6(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L6 {
    split(depth: 6, region) { l5($0, counterValue: counterValue, increment: increment) }
  }

  private static func l7(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L7 {
    split(depth: 7, region) { l6($0, counterValue: counterValue, increment: increment) }
  }

  private static func l8(
    _ region: Region, counterValue: Int, increment: @escaping @MainActor @Sendable () -> Void
  ) -> L8 {
    split(depth: 8, region) { l7($0, counterValue: counterValue, increment: increment) }
  }
}
