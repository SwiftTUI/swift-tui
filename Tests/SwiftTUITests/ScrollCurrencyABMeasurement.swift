import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The A/B measurement classes for the scroll-currency program (root plan
/// `docs/plans/2026-07-28-007-collection-scroll-currency-plan.md`), which the
/// house rule requires before any perf claim.
///
/// Written to compile and run UNCHANGED on both sides of the program, so it
/// uses no probe or API the program introduced: row realization is counted by a
/// closure-local counter, exactly as `NodeHostedCollectionRowsTests` does. Run
/// it in a worktree at `2a5dca6f` (the commit before S0) to reproduce the
/// A-side; the `#expect`s below are the B-side contract and are *supposed* to
/// fail there, alongside the printed `AB|` lines that are the measurement.
///
/// Recorded 2026-07-30, debug configuration, both sides on the same quiet
/// machine, two runs each agreeing within 3%:
///
/// | class | case | A-side | B-side |
/// | --- | --- | --- | --- |
/// | C | `ScrollView { List(1k) }` | 1,000 realized, 525-538 ms | 26 realized, 37-38 ms |
/// | C | `ScrollView { List(10k) }` | 10,000 realized, 33.0-33.4 s | 26 realized, 198-204 ms |
/// | C | `ScrollView { Table(1k) }` | 1,000 realized, 1.16 s | 14 realized, 49 ms |
/// | C | `ScrollView { Table(10k) }` | 10,000 realized, 68.2-70.4 s | 14 realized, 358-363 ms |
/// | A | 20 frames, `List(1k)`, finite | 11.50-11.71 ms/frame | 10.65-10.74 ms/frame |
/// | A | 20 frames, `List(10k)`, finite | 44.21-44.45 ms/frame | 35.53-35.81 ms/frame |
/// | B | `scrollTo` jump, 1k | did not land, 27.6 ms | landed, 22.9 ms |
/// | B | `scrollTo` jump, 10k | did not land, 75.8 ms | landed, 27.3 ms |
///
/// Reading them: class C is the D17 cliff and it is gone — realization is
/// viewport-bounded at every size, and the A-side's super-linear growth (10x
/// the rows cost 62x the time) goes with it. Class A is the already-windowed
/// finite-proposal path, where the gain is the S3/S4 and line/payload
/// reductions rather than realization, and it grows with dataset size (-8% at
/// 1k, -20% at 10k) because that is where the retired O(dataset) work lived.
/// Class B is a capability change first and a cost change second: the A-side
/// never reaches the row (register item D16).
///
/// Class E is deterministic rather than timed and lives with its reduction:
/// `ListLayoutProductTests` T-31 and `TableLayoutProductTests` T-37.
@MainActor
@Suite(.serialized)
struct ScrollCurrencyABMeasurement {
  final class Counter {
    var value = 0
  }

  @Test("Class C: the D17 cliff — ScrollView { List(N) } invalidating frame")
  func classCScrollViewCliff() {
    for rowCount in [1_000, 10_000] {
      let counter = Counter()
      let start = ContinuousClock.now
      let artifacts = DefaultRenderer().render(
        ScrollView {
          List(0..<rowCount, id: \.self) { row in
            counter.value += 1
            return Text("«\(row)»")
          }
        },
        context: .init(
          identity: testIdentity("ABClassC\(rowCount)"),
          applyEnvironmentValues: false
        ),
        proposal: .init(width: .finite(40), height: .finite(24))
      )
      let elapsed = ContinuousClock.now - start
      let drew = artifacts.rasterSurface.lines.joined(separator: "\n").contains("«0»")
      print(
        "AB|class=C|rows=\(rowCount)|realized=\(counter.value)"
          + "|ms=\(elapsed.milliseconds)|drew=\(drew)"
      )
      #expect(drew, "the first row is on screen")
      #expect(
        counter.value < 64,
        "D17: realization is viewport-bounded, not O(dataset) — realized \(counter.value)"
      )
    }
  }

  @Test("Class A: steady-state frames over a windowed collection")
  func classASteadyState() {
    // The closest cross-version comparable to the plan's offset-scroll class:
    // repeated invalidating frames over the same large collection. Both sides
    // realize and measure whatever their windowing lets them.
    for rowCount in [1_000, 10_000] {
      let counter = Counter()
      var frames = 0
      let start = ContinuousClock.now
      for selected in 0..<20 {
        _ = DefaultRenderer().render(
          List(0..<rowCount, id: \.self, selection: .constant(selected as Int?)) { row in
            counter.value += 1
            return Text("«\(row)»")
          },
          context: .init(
            identity: testIdentity("ABClassA\(rowCount)"),
            applyEnvironmentValues: false
          ),
          proposal: .init(width: .finite(40), height: .finite(24))
        )
        frames += 1
      }
      let elapsed = ContinuousClock.now - start
      print(
        "AB|class=A|rows=\(rowCount)|frames=\(frames)|realized=\(counter.value)"
          + "|ms=\(elapsed.milliseconds)|msPerFrame=\(elapsed.milliseconds / Double(frames))"
      )
      #expect(
        counter.value < 64 * frames,
        "a finite proposal was already windowed on both sides — realized \(counter.value)"
      )
    }
  }

  @Test("Class B: first frame after a scrollTo jump")
  func classBJump() throws {
    // Driven through the composed runtime, not a one-shot render: interaction
    // and scroll geometry only exist from frame 2, so a `DefaultRenderer`
    // render exercises the no-geometry fallback and the jump never lands on
    // EITHER side. `landed` keeps that honest.
    for rowCount in [1_000, 10_000] {
      let target = rowCount - 500
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("ABClassB\(rowCount)"),
        size: .init(width: 40, height: 16)
      ) {
        ABJumpList(rowCount: rowCount, target: target)
      }
      defer { harness.shutdown() }

      let start = ContinuousClock.now
      _ = try harness.clickText("Jump")
      let elapsed = ContinuousClock.now - start
      let landed = harness.frame.contains("«\(target)»")
      print(
        "AB|class=B|rows=\(rowCount)|target=\(target)"
          + "|ms=\(elapsed.milliseconds)|landed=\(landed)"
      )
      #expect(landed, "D16: scrollTo reaches a collection row:\n\(harness.frame)")
    }
  }

  @Test("Class C-table: the D17 cliff for Table")
  func classCTable() {
    for rowCount in [1_000, 10_000] {
      let counter = Counter()
      let start = ContinuousClock.now
      _ = DefaultRenderer().render(
        ScrollView {
          Table(0..<rowCount, id: \.self, columns: [.init("Value", width: 10)]) { row in
            counter.value += 1
            return Text("«\(row)»")
          }
        },
        context: .init(
          identity: testIdentity("ABClassCTable\(rowCount)"),
          applyEnvironmentValues: false
        ),
        proposal: .init(width: .finite(40), height: .finite(24))
      )
      let elapsed = ContinuousClock.now - start
      print(
        "AB|class=Ctable|rows=\(rowCount)|realized=\(counter.value)|ms=\(elapsed.milliseconds)"
      )
      #expect(counter.value < 64, "D17 for Table too — realized \(counter.value)")
    }
  }
}

extension Duration {
  fileprivate var milliseconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
  }
}

private struct ABJumpList: View {
  let rowCount: Int
  let target: Int
  @State private var result = "none"

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Text("result=\(result)")
        Button("Jump") { result = proxy.scrollTo(target) ? "true" : "false" }
        List(0..<rowCount, id: \.self) { row in
          Text("«\(row)»")
        }
        .frame(height: 10)
      }
    }
  }
}
