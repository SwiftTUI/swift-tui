@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct NestedScrollExtentTests {
  @Test("STUI-485: inner scrolling preserves outer extent and reaches both ends")
  func nestedExtent() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedScrollExtent"), size: .init(width: 60, height: 40)
    ) { NestedScrollExtentFixture() }
    defer { harness.shutdown() }
    func routes() -> [ScrollRoute] { harness.runLoop.latestSemanticSnapshot.scrollRoutes }
    let outer = try #require(
      routes().max { $0.viewportRect.size.height < $1.viewportRect.size.height })
    let inner = try #require(routes().first { $0.identity != outer.identity })
    #expect(outer.contentBounds.size.height == 80)
    #expect(inner.contentBounds.size.height == 60)
    let innerPoint = Point(
      x: Double(inner.viewportRect.origin.x + 2), y: Double(inner.viewportRect.origin.y + 2))
    for _ in 0..<40 {
      _ = try harness.scrollPointer(at: innerPoint, deltaY: 1)
      let current = try #require(routes().first { $0.identity == outer.identity })
      #expect(current.contentBounds == outer.contentBounds)
    }
    let innerBottom = try #require(routes().first { $0.identity == inner.identity })
    #expect(innerBottom.contentBounds.origin.y + 60 == innerBottom.viewportRect.origin.y + 20)
    _ = try harness.scrollPointer(at: innerPoint, deltaY: -1)
    let innerReversed = try #require(routes().first { $0.identity == inner.identity })
    #expect(innerReversed.contentBounds.origin.y == innerBottom.contentBounds.origin.y + 1)
    #expect(routes().first { $0.identity == outer.identity }?.contentBounds == outer.contentBounds)
    _ = try harness.scrollPointer(at: innerPoint, deltaY: 1)
    // Further input chains to the outer scroll once the inner reaches its end.
    _ = try harness.scrollPointer(at: innerPoint, deltaY: 1)
    let chained = try #require(routes().first { $0.identity == outer.identity })
    #expect(chained.contentBounds.origin.y == outer.contentBounds.origin.y - 1)
    #expect(chained.contentBounds.size == outer.contentBounds.size)
    let outerPoint = Point(
      x: Double(outer.viewportRect.origin.x + 1), y: Double(outer.viewportRect.origin.y + 1))
    // Coalesce endpoint traversal; the inner journey, handoff, and one-cell
    // reversals above and below retain their individual input assertions.
    _ = try harness.scrollPointer(at: outerPoint, deltaY: 60)
    let bottom = try #require(routes().first { $0.identity == outer.identity })
    #expect(bottom.contentBounds.size == outer.contentBounds.size)
    #expect(
      bottom.contentBounds.origin.y + bottom.contentBounds.size.height == bottom.viewportRect.origin
        .y + bottom.viewportRect.size.height)
    _ = try harness.scrollPointer(at: outerPoint, deltaY: -1)
    let reversed = try #require(routes().first { $0.identity == outer.identity })
    #expect(reversed.contentBounds.origin.y == bottom.contentBounds.origin.y + 1)
    _ = try harness.scrollPointer(at: outerPoint, deltaY: -60)
    let top = try #require(routes().first { $0.identity == outer.identity })
    #expect(top.contentBounds == outer.contentBounds)
  }

  @Test("nested horizontal scroll content stays inside its parent's extent")
  func horizontalExtent() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HorizontalNestedExtent"), size: .init(width: 40, height: 10)
    ) {
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          Rectangle().frame(width: 10)
          ScrollView(.horizontal) {
            HStack(spacing: 0) {
              ForEach(0..<30) { _ in Rectangle().frame(width: 2) }
            }
          }.offset(x: 1).frame(width: 20).padding(.vertical, 2)
          Rectangle().frame(width: 50)
        }
      }.frame(width: 30)
    }
    defer { harness.shutdown() }
    let routes = harness.runLoop.latestSemanticSnapshot.scrollRoutes
    let outer = try #require(routes.max { $0.viewportRect.size.width < $1.viewportRect.size.width })
    let inner = try #require(routes.first { $0.identity != outer.identity })
    #expect(outer.contentBounds.size.width == 80)
    let point = Point(
      x: Double(inner.viewportRect.origin.x + 2), y: Double(inner.viewportRect.origin.y + 1))
    for _ in 0..<40 {
      _ = try harness.scrollPointer(at: point, deltaX: 1, deltaY: 0)
      let current = try #require(
        harness.runLoop.latestSemanticSnapshot.scrollRoutes.first { $0.identity == outer.identity })
      #expect(current.contentBounds == outer.contentBounds)
    }
    let bottom = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes.first { $0.identity == inner.identity })
    #expect(
      bottom.contentBounds.origin.x + bottom.contentBounds.size.width == bottom.viewportRect.origin
        .x + bottom.viewportRect.size.width)
  }
}

@MainActor
private struct NestedScrollExtentFixture: View {
  var body: some View {
    ScrollView(.vertical) {
      VStack {
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
        ScrollView(.vertical) {
          VStack {
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
            Rectangle().fill(Color.red)
              .frame(height: 2)
            Rectangle().fill(Color.yellow)
              .frame(height: 2)
            Rectangle().fill(Color.green)
              .frame(height: 2)
            Rectangle().fill(Color.blue)
              .frame(height: 2)
            Rectangle().fill(Color.magenta)
              .frame(height: 2)
          }
        }
        .frame(height: 20)
        .padding(.horizontal, 5)
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
        Rectangle().fill(Color.white)
          .frame(height: 5)
        Rectangle().fill(Color.black)
          .frame(height: 5)
      }
    }
    .frame(height: 30)
  }
}
