@_spi(Runners) import SwiftTUI

/// Shared content and knobs for the scroll-latency scenario family
/// (program Stage 0, WP-2).
///
/// Four of the five scenarios share one windowed-collection shape so their
/// numbers are comparable: the only thing that varies between them is *how the
/// scroll is driven* — per-notch closed loop, open loop at a fixed cadence,
/// a momentum fling, or a programmatic jump. The fifth uses a deliberately
/// different, heterogeneous document shape, because a uniform-row collection
/// cannot show the cost that non-uniform block extents impose.
enum ScrollScenarioContent {
  /// Row count for the uniform collection shapes.
  ///
  /// 10k is the scale the program cares about and the scale windowed
  /// measurement made drivable. Overridable so a smoke sweep can pin a small
  /// tree and stay a wiring check rather than a benchmark.
  static func rowCount(default defaultRowCount: Int = 10_000) -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_LAZY_LIST_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }

  /// Block count for the heterogeneous-document shape.
  ///
  /// The default is deliberately *under* the worker-snapshot budget
  /// (`4 * max(columns, rows)`), because that is where real documents sit:
  /// small enough to be pre-realized on the main actor for tail offload
  /// (`canRunOnWorker == true`). Before Stage 2 (plan 2026-07-31-002) that
  /// was exactly the condition windowed measurement refused — the
  /// eligibility cliff this scenario was built to pin. Both regimes window
  /// now; raising this above the budget flips the same scenario onto the
  /// live-source path as a consistency lever rather than a rebuild.
  static func documentBlockCount(default defaultBlockCount: Int = 120) -> Int {
    guard let raw = environmentValue("SWIFTTUI_PERF_SCROLL_DOCUMENT_BLOCKS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultBlockCount
    }
    return parsed
  }
}

/// The uniform windowed-collection shape: a total indexed source, so a finite
/// frame realizes the visible band plus bounded overscan while the wheel walks
/// that band over an unchanged dataset.
struct PerfScrollListView: View {
  let rowCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll latency workload")
        .foregroundStyle(.tint)
      List(0..<rowCount, id: \.self) { index in
        HStack(spacing: 1) {
          Text("srow \(index)")
          Spacer(minLength: 1)
          Text("meta \(index % 97)")
            .foregroundStyle(.separator)
        }
      }
      .frame(height: 24)
      .border(.separator)
    }
    .padding(1)
  }
}

/// The fling vehicle: the uniform collection hosted by a `ScrollView` BODY.
///
/// `List` cannot carry this scenario — direct-manipulation panning and the
/// release-fling are scroll-BODY behaviors (the body's pointer handler claims
/// the `.down`/`.dragged`/`.up` stream; `List`'s handler only answers
/// `.scrolled`), so a drag over a `List` never captures a pan and the release
/// never seeds momentum. The run that exposed this recorded ZERO deadline
/// frames: the scenario had silently measured an ignored drag since the host
/// capability gate landed. Same row content and `srow` markers as
/// `PerfScrollListView`, so the driver's anchors are unchanged.
struct PerfScrollFlingView: View {
  let rowCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll fling workload")
        .foregroundStyle(.tint)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<rowCount, id: \.self) { index in
            HStack(spacing: 1) {
              Text("srow \(index)")
              Spacer(minLength: 1)
              Text("meta \(index % 97)")
                .foregroundStyle(.separator)
            }
          }
        }
        .padding(1)
      }
      .frame(height: 24)
      .border(.separator)
    }
    .padding(1)
  }
}

/// The heterogeneous-document shape: the mrkdwn silhouette.
///
/// Blocks vary from 1 to 12 rows and change kind on a fixed cycle, so no two
/// adjacent blocks share an extent and a scroll delta can never be satisfied
/// by a uniform row stride. `ScrollView { LazyVStack { ForEach } }` is the one
/// composition that windows placement today — a wrapper between the scroll
/// view and the stack kills it — so this shape measures the best case the
/// framework currently offers a document, not a pessimised one.
struct PerfScrollDocumentView: View {
  let blockCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Scroll document workload")
        .foregroundStyle(.tint)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(0..<blockCount, id: \.self) { index in
            block(index)
          }
        }
      }
      .padding(1)
      .frame(height: 24)
      .border(.separator)
    }
    .padding(1)
  }

  @ViewBuilder
  func block(_ index: Int) -> some View {
    // A deterministic marker on every block's first row, so the driver can
    // settle on a block having become visible without depending on wrapping.
    let marker = "sblk \(index)"
    switch index % 5 {
    case 0:
      Text("\(marker) — Heading")
        .foregroundStyle(.tint)
    case 1:
      Text(
        "\(marker) "
          + String(repeating: "paragraph text that wraps across the viewport width. ", count: 3)
      )
    case 2:
      VStack(alignment: .leading, spacing: 0) {
        Text("\(marker) code")
        ForEach(0..<(2 + index % 6), id: \.self) { line in
          Text("    let value\(line) = compute(\(line))")
            .foregroundStyle(.separator)
        }
      }
    case 3:
      VStack(alignment: .leading, spacing: 0) {
        Text("\(marker) quote")
        ForEach(0..<(1 + index % 3), id: \.self) { line in
          Text("  | quoted line \(line)")
            .foregroundStyle(.separator)
        }
      }
    default:
      VStack(alignment: .leading, spacing: 0) {
        Text("\(marker) table")
        ForEach(0..<(3 + index % 9), id: \.self) { row in
          HStack(spacing: 1) {
            Text("r\(row)")
            Spacer(minLength: 1)
            Text("c\(row % 4)")
            Spacer(minLength: 1)
            Text("v\(row * index % 71)")
          }
        }
      }
    }
  }
}
