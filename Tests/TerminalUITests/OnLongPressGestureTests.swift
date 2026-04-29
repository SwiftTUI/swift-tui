import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct OnLongPressGestureTests {
  @Test(".onLongPressGesture dispatches via deadline")
  func dispatches() throws {
    @MainActor class Box { var count = 0 }
    let box = Box()
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
        .onLongPressGesture(minimumDuration: .milliseconds(10)) {
          box.count += 1
        },
      context: ctx,
      proposal: .init(width: 10, height: 3)
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)

    // Fire .down — recognizer schedules its deadline.
    _ = pointerRegistry.dispatch(
      routeID: region.routeID,
      event: .init(
        kind: .down(.primary),
        location: Point(region.rect.origin),
        targetRect: region.rect
      )
    )

    // Simulate the scheduler firing the deadline by driving each
    // active recognizer directly.
    for (_, rec) in gestureRegistry.activeRecognizers() {
      _ = rec.handleDeadline(at: MonotonicInstant.now().advanced(by: .seconds(1)))
    }

    #expect(box.count == 1)
  }
}
