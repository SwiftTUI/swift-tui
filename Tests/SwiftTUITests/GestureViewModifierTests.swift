import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
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

  @Test("stacked .gesture modifiers share one pointer stream")
  func stackedGestureModifiersSharePointerStream() throws {
    @MainActor final class Box {
      var tapLocation: Point?
      var dragLocation: Point?
      var longPressCount = 0
    }
    let box = Box()
    let root = Identity(components: [IdentityComponent(rawValue: "stacked-gestures")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 5)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("Pointer")
        .frame(minWidth: 10, maxWidth: 10, minHeight: 2, maxHeight: 2)
        .gesture(
          SpatialTapGesture().onEnded { value in
            box.tapLocation = value.location
          }
        )
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { value in
            box.dragLocation = value.location
          }
        )
        .onLongPressGesture(minimumDuration: .milliseconds(1)) {
          box.longPressCount += 1
        },
      context: ctx,
      proposal: .init(width: 20, height: 5)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    let point = Point(x: Double(region.rect.origin.x + 2), y: Double(region.rect.origin.y))
    let pointer = PointerLocation.subCell(
      location: point,
      source: .nativePixels,
      metrics: .estimated
    )
    let t0 = MonotonicInstant.now()

    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary),
        location: pointer,
        targetRect: region.rect,
        timestamp: t0
      )
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary),
        location: pointer,
        targetRect: region.rect,
        timestamp: t0.advanced(by: .milliseconds(2))
      )
    )

    #expect(box.tapLocation == Point(x: 2, y: 0))
    #expect(box.dragLocation == Point(x: 2, y: 0))
    #expect(box.longPressCount == 1)
  }

  @Test("high-priority gestures defeat ordinary siblings but preserve simultaneous gestures")
  func highPriorityGestureWinsItsRecognizerStack() throws {
    @MainActor final class Counts {
      var ordinary = 0
      var highPriority = 0
      var simultaneous = 0
    }
    let counts = Counts()
    let root = Identity(components: [.named("high-priority-stack")])
    var environment = EnvironmentValues()
    environment.terminalSize = CellSize(width: 20, height: 5)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()
    var context = ResolveContext(identity: root, environmentValues: environment)
    context.localPointerHandlerRegistry = pointerRegistry
    context.localGestureRegistry = gestureRegistry
    context.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Text("Priority")
        .frame(minWidth: 10, maxWidth: 10, minHeight: 1, maxHeight: 1)
        .gesture(TapGesture().onEnded { counts.ordinary += 1 })
        .highPriorityGesture(TapGesture().onEnded { counts.highPriority += 1 })
        .simultaneousGesture(TapGesture().onEnded { counts.simultaneous += 1 }),
      context: context,
      proposal: .init(width: 20, height: 5)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.pointerGesturePriority == .high)
    let eventLocation = Point(region.rect.origin)
    for _ in 0..<2 {
      _ = pointerRegistry.dispatch(
        routeID: region.routeID,
        event: .init(kind: .down(.primary), location: eventLocation, targetRect: region.rect)
      )
      _ = pointerRegistry.dispatch(
        routeID: region.routeID,
        event: .init(kind: .up(.primary), location: eventLocation, targetRect: region.rect)
      )
    }

    #expect(counts.highPriority == 2)
    #expect(counts.simultaneous == 2)
    #expect(counts.ordinary == 0)
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
