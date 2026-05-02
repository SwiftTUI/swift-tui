import Foundation
import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite
struct OnTapGestureTests {
  @Test(".onTapGesture count:1 fires on single tap")
  func singleTapSugar() throws {
    @MainActor class Box { var count = 0 }
    let box = Box()
    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

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
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .onTapGesture { box.count += 1 },
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary),
        location: Point(region.rect.origin),
        targetRect: region.rect
      )
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary),
        location: Point(region.rect.origin),
        targetRect: region.rect
      )
    )
    #expect(box.count == 1)
  }

  @Test(".onTapGesture count:2 requires two taps")
  func doubleTapSugar() throws {
    @MainActor class Box { var count = 0 }
    let box = Box()
    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

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
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .onTapGesture(count: 2) { box.count += 1 },
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)

    // First tap
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    #expect(box.count == 0)  // not yet

    // Second tap
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary), location: Point(region.rect.origin), targetRect: region.rect)
    )
    #expect(box.count == 1)
  }
}
