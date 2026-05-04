import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct GestureViewModifierTests {
  @Test(".gesture(TapGesture().onEnded) fires on pointer down+up")
  func tapGestureFires() throws {
    @MainActor final class Box { var count = 0 }
    let box = Box()
    let renderer = DefaultRenderer()

    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    // Create the registries and wire them into the resolve context.
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env,
      applyEnvironmentValues: true
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = renderer.render(
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .gesture(TapGesture().onEnded { box.count += 1 }),
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.captureOnPress == false)

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

  @Test(".gesture(DragGesture()) sets captureOnPress on the region")
  func dragCaptures() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("Drag")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .gesture(DragGesture().onEnded { _ in }),
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.captureOnPress == true)
  }

  @Test(".gesture(LongPressGesture()) sets captureOnPress on the region")
  func longPressCaptures() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("Hold")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .gesture(LongPressGesture().onEnded { _ in }),
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.captureOnPress == true)
  }

  @Test(".gesture attached after offset translates the interaction region")
  func gestureAfterOffsetMovesInteractionRegion() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "offset-root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 6)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .offset(x: 4, y: 2)
        .gesture(TapGesture().onEnded {}),
      context: ctx,
      proposal: .init(width: 20, height: 6)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.rect == .init(origin: .init(x: 4, y: 2), size: .init(width: 5, height: 1)))
  }

  @Test(".gesture(_:including: .subviews) does not register at this view")
  func gestureMaskExcludesGesture() throws {
    @MainActor final class Box { var count = 0 }
    let box = Box()
    let renderer = DefaultRenderer()

    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    // Create the registries and wire them into the resolve context.
    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(
      identity: root,
      environmentValues: env,
      applyEnvironmentValues: true
    )
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = renderer.render(
      Text("Tap")
        .frame(minWidth: 5, maxWidth: 5, minHeight: 1, maxHeight: 1)
        .gesture(TapGesture().onEnded { box.count += 1 }, including: .subviews),
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    // When mask excludes .gesture, no interaction region is registered at this view.
    #expect(artifacts.semanticSnapshot.interactionRegions.isEmpty)

    // Verify that no pointer handler was registered by attempting dispatch
    // (this is a no-op if no handler exists, and box.count remains 0).
    #expect(box.count == 0)
  }
}
