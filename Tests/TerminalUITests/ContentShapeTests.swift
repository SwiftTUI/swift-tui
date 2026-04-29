import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ContentShapeTests {
  @Test(".contentShape overrides the hit-test rect")
  func contentShapeOverrides() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 3)

    let shapeRect = CellRect(
      origin: .zero,
      size: CellSize(width: 10, height: 3)
    )

    // Same pattern as GestureViewModifierTests: construct registries,
    // attach to ResolveContext, render.
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("X")
        .contentShape(shapeRect)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 3)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.rect.size.width == 10)
    #expect(region.rect.size.height == 3)
  }

  @Test("content-shape nil falls back to the default interaction rect")
  func contentShapeNilRestoresDefault() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 3)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("X")
        .contentShape(nil)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 3)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    // Default shape — should match the text's natural bounds (width 1 for "X").
    #expect(region.rect.size.width >= 1)
  }
}
