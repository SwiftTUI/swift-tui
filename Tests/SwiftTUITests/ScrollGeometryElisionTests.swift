import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollGeometryElisionTests {
  @Test(arguments: [false, true], [KeyEvent.home, .end])
  func boundaryKeyAfterElidedRegistrationPublication(nested: Bool, key: KeyEvent) async throws {
    let offsets = ElidedScrollOffsets()
    let outerHostID = testIdentity("elided-scroll-outer")
    let innerID = testIdentity("elided-scroll-inner")
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("elided-scroll-root"),
      size: .init(width: 30, height: 8)
    ) {
      HStack(alignment: .top) {
        ScrollView(.vertical, position: offsets.outer) {
          VStack(alignment: .leading, spacing: 0) {
            if nested {
              ScrollView(.vertical, position: offsets.inner) {
                Text((0..<20).map { "inner \($0)" }.joined(separator: "\n"))
              }
              .frame(height: 3)
              .id(innerID)
            }
            Text((0..<30).map { "outer \($0)" }.joined(separator: "\n"))
          }
        }
        .frame(width: 16, height: 6)
        .id(outerHostID)
        VStack {
          ForEach(0..<40) { index in Text("sibling \(index)") }
        }
      }
    }
    defer { h.shutdown() }
    let frozenNow = MonotonicInstant.now()
    h.runLoop.frameClock = { frozenNow }
    let outerID = try #require(
      h.runLoop.latestSemanticSnapshot.commandScrollRoutes.first {
        $0.viewportRect.size.height == 6
      }?.identity)
    _ = try h.focus(outerID)
    offsets.outerValue.y = 1
    offsets.innerValue.y = 2
    _ = try h.renderAfterExternalMutation()
    let routes = h.runLoop.latestSemanticSnapshot.commandScrollRoutes
    let outer = try #require(routes.first { $0.identity == outerID })
    let maximum = max(0, outer.contentBounds.size.height - outer.viewportRect.size.height)
    let before = h.runLoop.renderer.elidedFrameCount

    // In-place handler refreshes queue a publication even on a deadline-only
    // frame with no dirty evaluation. A property-only animation can elide
    // before the head, so it would not exercise the registration commit.
    h.runLoop.renderer.viewGraph.refreshActionRegistration(
      identity: outerID, handler: { false }, followUpInvalidationIdentity: nil, in: nil)
    if !nested {
      // A different publication target forces resetAll rather than the
      // scoped refresh exercised by the nested case.
      h.runLoop.renderer.viewGraph.recordCommittedRuntimeRegistrationTarget(
        RuntimeRegistrationSet().targetIdentity)
    }
    h.runLoop.scheduler.requestDeadline(frozenNow)
    var rendered = 0
    _ = try await h.runLoop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
    #expect(h.runLoop.renderer.elidedFrameCount == before + 1)
    #expect(rendered == 1)
    #expect(
      h.runLoop.localScrollPositionRegistry.viewportRect(scopeIdentity: outerID)
        == outer.viewportRect)

    // Dispatch before rendering: a committed tail would repair the missing
    // geometry and hide the wrong-view/no-op window.
    #expect(h.runLoop.handleKeyPress(KeyPress(key)) == nil)
    #expect(offsets.outerValue.y == (key == .home ? 0 : maximum))
    #expect(offsets.innerValue.y == 2)
    _ = try h.render()
    #expect(offsets.outerValue.y == (key == .home ? 0 : maximum))
    #expect(offsets.innerValue.y == 2)
  }

  @Test("Home resets both axes even without published scroll geometry")
  func homeWithoutGeometry() throws {
    let offsets = ElidedScrollOffsets()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("home-without-geometry"),
      size: .init(width: 12, height: 4)
    ) {
      ScrollView([.horizontal, .vertical], position: offsets.outer) {
        Text(
          Array(repeating: String(repeating: "x", count: 30), count: 20)
            .joined(separator: "\n"))
      }
    }
    defer { h.shutdown() }
    let identity = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    _ = try h.focus(identity)
    offsets.outerValue = .init(x: 3, y: 4)
    _ = try h.renderAfterExternalMutation()
    h.runLoop.localScrollPositionRegistry.updateGeometry(scrollRoutes: [], scrollTargets: [])
    #expect(h.runLoop.handleKeyPress(KeyPress(.home)) == nil)
    #expect(offsets.outerValue == .zero)
  }
}

@MainActor
private final class ElidedScrollOffsets {
  var outerValue = ScrollCellOffset.zero
  var innerValue = ScrollCellOffset.zero
  var outer: Binding<ScrollCellOffset> {
    .init(get: { self.outerValue }, set: { self.outerValue = $0 })
  }
  var inner: Binding<ScrollCellOffset> {
    .init(get: { self.innerValue }, set: { self.innerValue = $0 })
  }
}
