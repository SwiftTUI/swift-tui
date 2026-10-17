import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct LazyStackViewportCacheTests {
  @Test(arguments: [false, true])
  func repeatedViewportJumpsPreserveAuthoredOffsets(selective: Bool) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["LazyStackScrollProbe"]),
      size: .init(width: 80, height: 32), selectiveEvaluation: selective
    ) { LazyStackScrollProbe() }
    defer { h.shutdown() }
    #expect(h.frame.contains("vrow 0"))
    for burst in 1...6 {
      _ = try h.scrollPointer(at: .init(x: 5.5, y: 5.5), deltaY: 30)
      #expect(h.frame.contains("vrow \(burst * 30)"), "\(h.frame)")
      let route = try #require(
        h.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
          h.runLoop.latestSemanticSnapshot.scrollRoutes
        ).first)
      #expect(route.contentOffset.y == min(burst * 30, 178))
    }
  }
}
private struct LazyStackScrollProbe: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Lazy vstack scroll workload")
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<200, id: \.self) { index in
            HStack(spacing: 1) {
              Text("vrow \(index)")
              Spacer(minLength: 1)
              Text("meta \(index % 89)")
            }
          }
        }.padding(1)
      }.frame(height: 24).border(.separator)
    }.padding(1)
  }
}
