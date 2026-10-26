import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD131–setD140: far-edge commands
// under content mutation, input batches, disabling and a modal cover.
// Brief 04 in the coordination root's evidence directory.

private struct SetDAppendLog: View {
  let offset: SetDOffsetBox
  let lazy: Bool
  @State private var lines: [String]

  init(offset: SetDOffsetBox, start: Int, lazy: Bool = false) {
    self.offset = offset
    self.lazy = lazy
    _lines = State(initialValue: (0..<start).map { "l\($0)" })
  }

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("append") {
          lines.append("l\(lines.count)")
          _ = proxy.scrollTo(edge: .bottom)
        }
        ScrollView(.vertical, position: offset.binding) {
          if lazy {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(lines, id: \.self) { Text($0) }
            }
          } else {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(lines, id: \.self) { Text($0) }
            }
          }
        }
        .frame(height: 6)
        .scrollIndicators(.hidden)
      }
      .onKeyPress(.character("a")) { _ in
        lines.append("l\(lines.count)")
        return .handled
      }
    }
  }
}

private struct SetDVariableLazy: View {
  let offset: SetDOffsetBox
  var body: some View {
    ScrollView(.vertical, position: offset.binding) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(0..<120, id: \.self) { index in
          Text("a\(index)").frame(height: index < 40 ? 1 : 3, alignment: .topLeading)
        }
      }
    }
    .frame(width: 20, height: 8)
    .scrollIndicators(.hidden)
  }
}

@MainActor
private final class SetDCoverModel {
  var presented = false
  var binding: Binding<Bool> { .init(get: { self.presented }, set: { self.presented = $0 }) }
}

@MainActor
@Suite(
  "Campaign F2 pass 2: scroll edges under mutation, batches, disabling and modals", .serialized)
struct AdversarialSetDScrollEdgeModeTests {
  private func appendLog(
    _ name: String, start: Int, at y: Int, lazy: Bool = false
  ) throws -> (SetDLiveHarness<some View>, SetDOffsetBox) {
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness(name, size: .init(width: 20, height: 7)) {
      SetDAppendLog(offset: offset, start: start, lazy: lazy)
    }
    offset.value = .init(x: 0, y: y)
    try h.renderRoot()
    return (h, offset)
  }

  // STUI-1305 (repaired in wave 4), setD131–setD135: a far edge issued by
  // the action that appends re-resolves after the next layout.
  @Test("setD131: append plus scrollTo(edge: .bottom) at the bottom shows the new last row")
  func setD131AppendAndBottomEdgeAtBottom() throws {
    let (h, offset) = try appendLog("131", start: 20, at: 14)
    defer { h.shutdown() }
    try #require(h.frame.contains("l19") && offset.value.y == 14, "\(h.frame)")
    try h.clickText("append")
    #expect(h.frame.contains("l20"), "\(h.frame)")
    #expect(offset.value.y == 15, "\(offset.value)")
  }

  @Test("setD132: append plus scrollTo(edge: .bottom) at the first overflow shows the new row")
  func setD132AppendAndBottomEdgeAtFirstOverflow() throws {
    let (h, offset) = try appendLog("132", start: 6, at: 0)
    defer { h.shutdown() }
    try #require(h.frame.contains("l5") && !h.frame.contains("l6"), "\(h.frame)")
    try h.clickText("append")
    #expect(h.frame.contains("l6"), "\(h.frame)")
    #expect(offset.value.y == 1, "\(offset.value)")
  }

  @Test(
    "setD133: append plus scrollTo(edge: .bottom) one line above the bottom reaches the new bottom")
  func setD133AppendAndBottomEdgeAboveBottom() throws {
    let (h, offset) = try appendLog("133", start: 20, at: 13)
    defer { h.shutdown() }
    try #require(!h.frame.contains("l19"), "\(h.frame)")
    try h.clickText("append")
    #expect(h.frame.contains("l20"), "\(h.frame)")
    #expect(offset.value.y == 15, "\(offset.value)")
  }

  @Test("setD134: an appending key and End in one batch at the bottom show the new last row")
  func setD134AppendKeyAndEndInOneBatch() throws {
    let (h, offset) = try appendLog("134", start: 20, at: 14)
    defer { h.shutdown() }
    let scroll = try #require(
      h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity, "no scroll route")
    try h.focus(scroll)
    try h.keys([.character("a"), .end])
    #expect(h.frame.contains("l20"), "\(h.frame)")
    #expect(offset.value.y == 15, "\(offset.value)")
  }

  @Test("setD135: lazy append plus scrollTo(edge: .bottom) at the bottom shows the new last row")
  func setD135LazyAppendAndBottomEdgeAtBottom() throws {
    let (h, offset) = try appendLog("135", start: 20, at: 14, lazy: true)
    defer { h.shutdown() }
    try #require(h.frame.contains("l19") && offset.value.y == 14, "\(h.frame)")
    try h.clickText("append")
    #expect(h.frame.contains("l20"), "\(h.frame)")
    #expect(offset.value.y == 15, "\(offset.value)")
  }

  // STUI-1317 (repaired in wave 4): a disabled scroll view keeps its route
  // for programmatic commands.
  @Test("setD136: a reader's proxy does not move a later scroll view past a disabled first one")
  func setD136ProxyAddressesFirstScrollViewEvenWhenDisabled() throws {
    let first = SetDOffsetBox()
    let second = SetDOffsetBox()
    let h = try SetDLiveHarness("136", size: .init(width: 30, height: 8)) {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Button("jump") { _ = proxy.scrollTo(edge: .bottom) }
          HStack(alignment: .top, spacing: 1) {
            ScrollView(.vertical, position: first.binding) {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("a\($0)") }
              }
            }
            .frame(width: 8, height: 5)
            .disabled(true)
            ScrollView(.vertical, position: second.binding) {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<30, id: \.self) { Text("b\($0)") }
              }
            }
            .frame(width: 8, height: 5)
          }
        }
      }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("a0") && h.frame.contains("b0"), "\(h.frame)")
    try h.clickText("jump")
    #expect(second.value == .zero, "the second view moved: \(second.value)")
  }

  @Test("setD137: End then Home in one batch leaves a lazy view at its start")
  func setD137EndThenHomeInOneBatch() throws {
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness("137", size: .init(width: 20, height: 8)) {
      SetDVariableLazy(offset: offset)
    }
    defer { h.shutdown() }
    let scroll = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try h.focus(scroll)
    try h.keys([.end, .home])
    #expect(offset.value.y == 0, "\(offset.value)")
    #expect(h.tokens(prefix: "a").first == "a0", "\(h.frame)")
  }

  @Test("setD138: Home then End in one batch reaches the last variable-height row")
  func setD138HomeThenEndInOneBatch() throws {
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness("138", size: .init(width: 20, height: 8)) {
      SetDVariableLazy(offset: offset)
    }
    defer { h.shutdown() }
    offset.value = .init(x: 0, y: 30)
    try h.renderRoot()
    let scroll = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try h.focus(scroll)
    try h.keys([.home, .end])
    #expect(h.frame.contains("a119"), "\(h.frame)")
  }

  @Test("setD139: a full-screen cover blocks base edge keys until Escape")
  func setD139CoverBlocksBaseEdgeKeys() throws {
    let offset = SetDOffsetBox()
    let cover = SetDCoverModel()
    let h = try SetDLiveHarness("139", size: .init(width: 20, height: 8)) {
      ScrollView(.vertical, position: offset.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<30, id: \.self) { Text("c\($0)") }
        }
      }
      .scrollIndicators(.hidden)
      .fullScreenCover(isPresented: cover.binding) { Button("cover action") {} }
    }
    defer { h.shutdown() }
    let scroll = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first?.identity)
    try h.focus(scroll)
    cover.presented = true
    try h.renderRoot()
    try #require(h.frame.contains("cover action"), "\(h.frame)")
    try h.key(.end)
    try h.key(.pageDown)
    #expect(offset.value == .zero, "\(offset.value)")
    try h.key(.escape)
    #expect(!cover.presented)
    try h.key(.end)
    #expect(h.frame.contains("c29"), "\(h.frame)")
  }

  @Test("setD140: probe — End on a nested scroll view already at its bottom")
  func setD140NestedEndAtInnerBottom() throws {
    let outer = SetDOffsetBox()
    let inner = SetDOffsetBox()
    let h = try SetDLiveHarness("140", size: .init(width: 20, height: 8)) {
      ScrollView(.vertical, position: outer.binding) {
        VStack(alignment: .leading, spacing: 0) {
          Text("top")
          ScrollView(.vertical, position: inner.binding) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<10, id: \.self) { Text("i\($0)") }
            }
          }
          .frame(height: 4)
          .scrollIndicators(.hidden)
          ForEach(0..<20, id: \.self) { Text("o\($0)") }
        }
      }
      .scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    let routes = h.runLoop.latestSemanticSnapshot.scrollRoutes
    try #require(routes.count == 2, "\(routes.map(\.identity))")
    let innerRoute = try #require(
      routes.min { $0.viewportRect.size.height < $1.viewportRect.size.height })
    try h.focus(innerRoute.identity)
    try h.key(.end)
    try #require(inner.value.y == 6, "\(inner.value)")
    let outerBefore = outer.value
    try h.key(.end)
    print(
      "setD140 observation: outer offset \(outerBefore) -> \(outer.value), inner \(inner.value)")
    #expect(inner.value.y == 6)
  }
}
