import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct MemoReadWorkloadTests {
  @Test(
    "state-reading workload matches the fresh oracle while avoiding body work",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTTUI_MEMO_READ_WORKLOAD"] == "1"))
  func pairedWorkload() {
    for pair in 0..<5 {
      let order = pair.isMultiple(of: 2) ? [true, false] : [false, true]
      var outputs: [String] = []
      for forceFresh in order {
        let renderer = DefaultRenderer()
        let probe = WorkProbe()
        let root = testIdentity("ReadCertificateWorkload")
        let start = ContinuousClock.now
        var finalText = ""
        for frame in 0..<30 {
          let snapshot = renderer.render(
            WorkRoot(probe: probe, frame: frame, nonce: forceFresh ? frame : 0),
            context: .init(identity: root, invalidatedIdentities: frame == 0 ? [] : [root]))
          finalText = snapshot.rasterSurface.lines.joined()
        }
        let elapsed = start.duration(to: .now)
        #expect(probe.evaluations == (forceFresh ? 30 : 1))
        #expect(finalText.contains("frame 29"))
        outputs.append(finalText)
        print(
          "STUI125_WORKLOAD pair=\(pair) fresh=\(forceFresh) elapsed=\(elapsed) bodies=\(probe.evaluations) output=\(finalText)"
        )
      }
      #expect(outputs.first == outputs.last)
    }
  }
}

@MainActor
private final class WorkProbe { var evaluations = 0 }

@MainActor
private struct WorkRoot: View {
  let probe: WorkProbe
  let frame: Int
  let nonce: Int
  var body: some View {
    VStack {
      WorkBoundary(probe: probe, nonce: nonce)
      Text("frame \(frame)")
    }
  }
}

@MainActor
private struct WorkBoundary: View, Equatable {
  let probe: WorkProbe
  let nonce: Int
  @State private var seed: UInt64 = 7
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.nonce == rhs.nonce }
  var body: some View {
    probe.evaluations += 1
    var digest = seed
    for index in 0..<1_000_000 {
      digest = (digest &* 6_364_136_223_846_793_005 &+ UInt64(index)) ^ (digest >> 17)
    }
    return Text("digest \(digest)")
  }
}
