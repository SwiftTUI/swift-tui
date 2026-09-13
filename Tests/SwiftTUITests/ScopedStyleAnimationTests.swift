import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ScopedStyleAnimationTests {
  private struct RuntimeStyle: View {
    @State private var changed = false
    var body: some View {
      VStack {
        Button("change") { changed.toggle() }
        Rectangle().frame(width: 4, height: 1).offset(x: changed ? 4 : 0, y: 0)
          .animation(.linear(duration: .milliseconds(200))) { view in
            view.foregroundStyle(changed ? Color.blue : .red)
          }
      }
    }
  }

  @Test("input starts the scoped style animation without animating base geometry")
  func runtimeInput() async throws {
    let harness = try AnimatorRuntimeHarness { RuntimeStyle() }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController
    try withAnimationSinks(controller) { _ = try harness.clickText("change") }
    let keys = controller.debugStateSnapshot().activeAnimationKeys
    #expect(keys.contains { $0.scope == .property(.foregroundShapeStyle) })
    #expect(!keys.contains { $0.scope == .property(.offset) })
    try await harness.wait { controller.activeAnimationCount == 0 }
  }

  private struct Foreground: View {
    var changed: Bool
    var explicitBase = false
    var body: some View {
      VStack {
        if explicitBase {
          Rectangle().foregroundStyle(changed ? Color.green : .yellow)
            .frame(width: 4, height: 1)
            .animation(.linear(duration: .seconds(1))) { view in
              view.foregroundStyle(changed ? Color.blue : .red)
            }
        } else {
          Rectangle().frame(width: 4, height: 1).offset(x: changed ? 4 : 0, y: 0)
            .animation(.linear(duration: .seconds(1))) { view in
              view.foregroundStyle(changed ? Color.blue : .red)
            }
        }
        Rectangle().foregroundStyle(changed ? Color.blue : .red).frame(width: 4, height: 1)
      }
    }
  }

  @Test("scoped foreground animates while base geometry and sibling styles snap")
  func foreground() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("scoped-style")
    let start = MonotonicInstant(offset: .seconds(100))
    let proposal = ProposedSize(width: .finite(20), height: .finite(5))
    withAnimationSinks(controller) {
      _ = renderer.render(
        Foreground(changed: false), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      _ = renderer.render(
        Foreground(changed: true), context: .init(identity: root),
        proposal: proposal, frameInstant: start)
      let keys = controller.debugStateSnapshot().activeAnimationKeys
      #expect(keys.contains { $0.scope == .property(.foregroundShapeStyle) })
      #expect(!keys.contains { $0.scope == .property(.offset) })
      #expect(!keys.contains { $0.identity.path.contains("VStack[1]") })
      let halfway = renderer.render(
        Foreground(changed: true), context: .init(identity: root),
        proposal: proposal, frameInstant: start.advanced(by: .milliseconds(500)))
      let colours = halfway.rasterSurface.cells.flatMap { $0 }.flatMap {
        [$0.style?.foregroundColor, $0.style?.backgroundColor].compactMap { $0 }
      }
      #expect(colours.contains { $0 != .red && $0 != .blue })
    }
  }

  @Test("a foreground writer on the base overrides the scoped style and its provenance")
  func baseOverride() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("scoped-style-override")
    let frame = withAnimationSinks(controller) {
      _ = renderer.render(
        Foreground(changed: false, explicitBase: true), context: .init(identity: root))
      return renderer.render(
        Foreground(changed: true, explicitBase: true), context: .init(identity: root))
    }
    let state = controller.debugStateSnapshot()
    for key in state.activeAnimationKeys {
      if let tree = state.previousTreeRoot,
        let node = AnimationTreeQueries.findResolvedSubtree(in: tree, identity: key.identity)
      {
        if case .shape = node.drawPayload { Issue.record("the base shape must snap") }
      }
    }
    let paints = frame.rasterSurface.cells.flatMap { $0 }.compactMap { $0.style?.backgroundColor }
    #expect(paints.contains(.green))
    #expect(!paints.contains(.yellow))
  }

  private struct Tint: View {
    var changed: Bool
    var body: some View {
      Rectangle().foregroundStyle(.tint).frame(width: 4, height: 1)
        .transaction({ $0.animation = .linear(duration: .seconds(1)) }) { view in
          view.tint(changed ? Color.blue : .red)
        }
    }
  }

  @Test("scoped transaction tint gets its own animatable style channel")
  func tint() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("scoped-tint")
    let start = MonotonicInstant(offset: .seconds(100))
    withAnimationSinks(controller) {
      _ = renderer.render(Tint(changed: false), context: .init(identity: root), frameInstant: start)
      _ = renderer.render(Tint(changed: true), context: .init(identity: root), frameInstant: start)
      #expect(
        controller.debugStateSnapshot().activeAnimationKeys.contains {
          $0.scope == .property(.tintShapeStyle)
        })
      _ = renderer.render(
        Tint(changed: true), context: .init(identity: root),
        frameInstant: start.advanced(by: .milliseconds(1500)))
      #expect(controller.activeAnimationCount == 0)
    }
  }

  private struct Nested: View {
    var changed: Bool
    var body: some View {
      Rectangle().frame(width: 4, height: 1)
        .animation(.linear(duration: .seconds(2))) { view in
          view.foregroundStyle(changed ? Color.blue : .red)
        }
        .animation(.linear(duration: .seconds(1))) { view in
          view.tint(changed ? Color.green : .yellow)
        }
    }
  }

  @Test("nested scopes retain distinct per-style timing")
  func nestedScopes() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("nested-scoped-style")
    let start = MonotonicInstant(offset: .seconds(100))
    withAnimationSinks(controller) {
      _ = renderer.render(
        Nested(changed: false), context: .init(identity: root), frameInstant: start)
      _ = renderer.render(
        Nested(changed: true), context: .init(identity: root), frameInstant: start)
    }
    let boxes = controller.debugStateSnapshot().activeAnimationBoxesByKey
    let foreground = boxes.filter { $0.key.scope == .property(.foregroundShapeStyle) }
    let tint = boxes.filter { $0.key.scope == .property(.tintShapeStyle) }
    #expect(!foreground.isEmpty && !tint.isEmpty)
    #expect(
      foreground.values.allSatisfy { $0.unwrap(as: Animation.self)?.totalDuration == .seconds(2) })
    #expect(tint.values.allSatisfy { $0.unwrap(as: Animation.self)?.totalDuration == .seconds(1) })
  }

  private struct Disabled: View {
    var changed: Bool
    var body: some View {
      Rectangle().frame(width: 4, height: 1).offset(x: changed ? 4 : 0, y: 0)
        .animation(nil) { view in view.foregroundStyle(changed ? Color.blue : .red) }
    }
  }

  @Test("a disabled scoped foreground stays separate from animated base geometry")
  func disabledScope() {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let root = testIdentity("disabled-scoped-style")
    let start = MonotonicInstant(offset: .seconds(100))
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)
    withAnimationSinks(controller) {
      _ = renderer.render(
        Disabled(changed: false), context: .init(identity: root), frameInstant: start)
      _ = renderer.render(
        Disabled(changed: true), context: .init(identity: root, transaction: transaction),
        frameInstant: start)
    }
    let keys = controller.debugStateSnapshot().activeAnimationKeys
    #expect(keys.contains { $0.scope == .property(.offset) })
    #expect(!keys.contains { $0.scope == .property(.foregroundShapeStyle) })
  }
}
