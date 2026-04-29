import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct GestureIntegrationTests {
  @Test("Draggable pin — @GestureState tracks translation, commits on end")
  func draggablePin() throws {
    @MainActor class Model {
      var position = Point(x: 0, y: 0)
    }
    let model = Model()

    struct Pin: View {
      @GestureState var dragOffset = Vector(dx: 0, dy: 0)
      let model: Model

      var body: some View {
        Text("📍")
          .frame(minWidth: 3, maxWidth: 3, minHeight: 1, maxHeight: 1)
          .gesture(
            DragGesture()
              .updating($dragOffset) { value, state, _ in
                state = value.translation
              }
              .onEnded { value in
                model.position = Point(
                  x: model.position.x + value.translation.dx,
                  y: model.position.y + value.translation.dy
                )
              }
          )
      }
    }

    let root = Identity(components: [IdentityComponent(rawValue: "r")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 40, height: 10)

    let pointerRegistry = LocalPointerHandlerRegistry()
    let gestureRegistry = LocalGestureRegistry()
    let gestureStateRegistry = LocalGestureStateRegistry()

    var ctx = ResolveContext(identity: root, environmentValues: env)
    ctx.localPointerHandlerRegistry = pointerRegistry
    ctx.localGestureRegistry = gestureRegistry
    ctx.localGestureStateRegistry = gestureStateRegistry

    let artifacts = DefaultRenderer().render(
      Pin(model: model),
      context: ctx,
      proposal: .init(width: 40, height: 10)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.captureOnPress == true)  // DragGesture captures

    let start = region.rect.origin
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary),
        location: Point(start),
        targetRect: region.rect
      )
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .dragged(.primary),
        location: Point(CellPoint(x: start.x + 5, y: start.y + 2)),
        targetRect: region.rect
      )
    )
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .up(.primary),
        location: Point(CellPoint(x: start.x + 5, y: start.y + 2)),
        targetRect: region.rect
      )
    )
    #expect(model.position == Point(x: 5, y: 2))
  }

  @Test("Tap + double-tap exclusively composed — only double-tap fires on two taps")
  func exclusiveTapDisambiguation() throws {
    @MainActor class Counts {
      var single = 0
      var double = 0
    }
    let counts = Counts()

    struct V: View {
      let counts: Counts
      var body: some View {
        Text("X")
          .frame(minWidth: 3, maxWidth: 3, minHeight: 1, maxHeight: 1)
          .gesture(
            TapGesture(count: 2).onEnded { counts.double += 1 }
              .exclusively(before: TapGesture().onEnded { counts.single += 1 })
          )
      }
    }

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
      V(counts: counts),
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )
    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)

    // Two taps — double-tap wins.
    for _ in 0..<2 {
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
    }
    #expect(counts.double == 1)
    #expect(counts.single == 0)
  }
}
