import Testing

@testable import TerminalUIScenes

@MainActor
struct SceneLifecycleTests {
  @Test("Initial state is created")
  func initialStateIsCreated() {
    let lifecycle = SceneLifecycle()
    #expect(lifecycle.state == .created)
  }

  @Test("Transitions from created to rendering on client attach")
  func createdToRendering() {
    var lifecycle = SceneLifecycle()
    let transitioned = lifecycle.clientAttached()
    #expect(transitioned)
    #expect(lifecycle.state == .rendering)
  }

  @Test("Transitions from rendering to suspended on client detach")
  func renderingToSuspended() {
    var lifecycle = SceneLifecycle()
    _ = lifecycle.clientAttached()
    let transitioned = lifecycle.clientDetached()
    #expect(transitioned)
    #expect(lifecycle.state == .suspended)
  }

  @Test("Transitions from suspended to rendering on re-attach")
  func suspendedToRendering() {
    var lifecycle = SceneLifecycle()
    _ = lifecycle.clientAttached()
    _ = lifecycle.clientDetached()
    let transitioned = lifecycle.clientAttached()
    #expect(transitioned)
    #expect(lifecycle.state == .rendering)
  }

  @Test("Detach from created state is a no-op")
  func detachFromCreatedIsNoOp() {
    var lifecycle = SceneLifecycle()
    let transitioned = lifecycle.clientDetached()
    #expect(!transitioned)
    #expect(lifecycle.state == .created)
  }

  @Test("Double attach is a no-op")
  func doubleAttachIsNoOp() {
    var lifecycle = SceneLifecycle()
    _ = lifecycle.clientAttached()
    let transitioned = lifecycle.clientAttached()
    #expect(!transitioned)
    #expect(lifecycle.state == .rendering)
  }

  @Test("Primary scene is always rendering")
  func primarySceneAlwaysRendering() {
    let lifecycle = SceneLifecycle(isPrimary: true)
    #expect(lifecycle.state == .rendering)
  }
}
