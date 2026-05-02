import Testing

@testable import Core
@testable import SwiftTUI
@testable import View

@MainActor
@Suite
struct LayoutAndRenderingPipelineTests {
  @Test("vertical stack measures and places children top-down with spacing")
  func verticalStackMeasuresAndPlacesChildren() {
    let root = VStack(alignment: .leading, spacing: 1) {
      Text("Hello")
      Text("Yo")
    }
    let resolved = root.resolve(in: .init(identity: testIdentity("Root")))
    let layoutEngine = LayoutEngine()
    let measured = layoutEngine.measure(resolved)
    let placed = layoutEngine.place(resolved, measured: measured)

    #expect(measured.measuredSize == .init(width: 5, height: 3))
    #expect(placed.children.count == 2)
    #expect(placed.children[0].bounds.origin == .init(x: 0, y: 0))
    #expect(placed.children[0].bounds.size == .init(width: 5, height: 1))
    #expect(placed.children[1].bounds.origin == .init(x: 0, y: 2))
    #expect(placed.children[1].bounds.size == .init(width: 2, height: 1))
  }

  @Test("horizontal stack measures and places children left-to-right with spacing")
  func horizontalStackMeasuresAndPlacesChildren() {
    let root = HStack(spacing: 2) {
      Text("One")
      Text("Two")
    }
    let resolved = root.resolve(in: .init(identity: testIdentity("Root")))
    let layoutEngine = LayoutEngine()
    let measured = layoutEngine.measure(resolved)
    let placed = layoutEngine.place(resolved, measured: measured)

    #expect(measured.measuredSize == .init(width: 8, height: 1))
    #expect(placed.children[0].bounds.origin == .init(x: 0, y: 0))
    #expect(placed.children[1].bounds.origin == .init(x: 5, y: 0))
  }

  @Test("default renderer builds geometry, semantics, draw tree, raster output, and commit plan")
  func defaultRendererBuildsEndToEndArtifacts() {
    let root = VStack(alignment: .leading, spacing: 1) {
      Text("Hello")
      Text("Tap").focusable()
    }

    let artifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("Root"))
    )

    #expect(artifacts.measuredTree.measuredSize == .init(width: 5, height: 3))
    #expect(artifacts.placedTree.children[1].identity == testIdentity("Root", "VStack[1]"))
    #expect(artifacts.semanticSnapshot.focusRegions.count == 1)
    #expect(artifacts.semanticSnapshot.interactionRegions.count == 1)
    #expect(
      artifacts.semanticSnapshot.interactionRegions[0].routeID == testRoute("Root", "VStack[1]"))
    #expect(artifacts.drawTree.children.count == 2)
    #expect(artifacts.rasterSurface.lines == ["Hello", "", "Tap"])
    #expect(
      artifacts.commitPlan.handlerInstallations == [
        .init(handlerID: testRoute("Root", "VStack[1]"))
      ])
  }

  @Test("overlay layout places children at the same origin and raster keeps last draw visible")
  func overlayLayoutPlacesChildrenAtSameOrigin() {
    let root = ZStack(alignment: .topLeading) {
      Text("Base")
      Text("Top")
    }

    let artifacts = DefaultRenderer().render(
      root,
      context: .init(identity: testIdentity("Overlay"))
    )

    #expect(artifacts.placedTree.children[0].bounds.origin == .zero)
    #expect(artifacts.placedTree.children[1].bounds.origin == .zero)
    #expect(artifacts.rasterSurface.lines.first == "Tope")
  }

  @Test("clipped interaction regions are reduced to the visible clip bounds")
  func clippedInteractionRegionsRespectVisibleBounds() throws {
    let artifacts = DefaultRenderer().render(
      Text("ABCDEFG")
        .semanticMetadata(.init(isFocusable: true, participatesInPointerHitTesting: true))
        .frame(width: 3, height: 1, alignment: .leading)
        .clipped(),
      context: .init(identity: testIdentity("Root"))
    )

    let region = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    #expect(region.rect == .init(origin: .zero, size: .init(width: 3, height: 1)))
  }

  @Test("offset moves clipped focus and interaction regions")
  func offsetTranslatesClippedSemanticRegions() throws {
    let artifacts = DefaultRenderer().render(
      Text("Tap")
        .semanticMetadata(.init(isFocusable: true, participatesInPointerHitTesting: true))
        .frame(width: 3, height: 1, alignment: .leading)
        .clipped()
        .offset(x: 2, y: 1)
        .frame(width: 6, height: 3, alignment: .topLeading),
      context: .init(identity: testIdentity("Root"))
    )

    let interactionRegion = try #require(artifacts.semanticSnapshot.interactionRegions.first)
    let focusRegion = try #require(artifacts.semanticSnapshot.focusRegions.first)

    #expect(
      interactionRegion.rect == .init(origin: .init(x: 2, y: 1), size: .init(width: 3, height: 1)))
    #expect(focusRegion.rect == .init(origin: .init(x: 2, y: 1), size: .init(width: 3, height: 1)))
  }

  @Test("render registers lifecycle work in the commit plan without executing it during resolve")
  func renderRegistersLifecycleWorkWithoutExecutingItDuringResolve() async throws {
    final class CounterBox: Sendable {
      private struct State: Sendable {
        var appearCount = 0
        var disappearCount = 0
        var taskCount = 0
      }

      private let state = LockedBox(State())

      var appearCount: Int {
        get { state.value.appearCount }
        set { state.withLock { $0.appearCount = newValue } }
      }

      var disappearCount: Int {
        get { state.value.disappearCount }
        set { state.withLock { $0.disappearCount = newValue } }
      }

      var taskCount: Int {
        get { state.value.taskCount }
        set { state.withLock { $0.taskCount = newValue } }
      }
    }

    let counters = CounterBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()

    let artifacts = DefaultRenderer().render(
      Text("Load")
        .onAppear { counters.appearCount += 1 }
        .onDisappear { counters.disappearCount += 1 }
        .task(priority: .userInitiated) { counters.taskCount += 1 },
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )

    #expect(counters.appearCount == 0)
    #expect(counters.disappearCount == 0)
    #expect(counters.taskCount == 0)
    #expect(
      artifacts.commitPlan.lifecycle == [
        .init(
          identity: testIdentity("Root"),
          operation: .appear(handlerIDs: ["Root#appear[0]"])
        ),
        .init(
          identity: testIdentity("Root"),
          operation: .taskStart(.init(id: "Root#task", priority: .userInitiated))
        ),
      ]
    )
    #expect(lifecycleRegistry.appearHandler(for: "Root#appear[0]") != nil)
    #expect(lifecycleRegistry.disappearHandler(for: "Root#disappear[0]") != nil)

    let taskRegistration = try #require(taskRegistry.registration(for: testIdentity("Root")))
    #expect(
      taskRegistration.descriptor == TaskDescriptor(id: "Root#task", priority: .userInitiated))

    await MainActor.run {
      lifecycleRegistry.appearHandler(for: "Root#appear[0]")?()
      lifecycleRegistry.disappearHandler(for: "Root#disappear[0]")?()
    }
    await taskRegistration.run()

    #expect(counters.appearCount == 1)
    #expect(counters.disappearCount == 1)
    #expect(counters.taskCount == 1)
  }

  @Test("lifecycle coordinator replays change handlers from committed frames")
  func lifecycleCoordinatorReplaysChangeHandlers() {
    final class CounterBox {
      var changeCount = 0
    }

    let counters = CounterBox()
    let lifecycleRegistry = LocalLifecycleRegistry()
    lifecycleRegistry.registerChange(handlerID: "Root#change[0]") {
      counters.changeCount += 1
    }

    LifecycleCoordinator().applyCommittedFrame(
      plan: .init(
        lifecycle: [
          .init(
            identity: testIdentity("Root"),
            operation: .change(handlerIDs: ["Root#change[0]"])
          )
        ]
      ),
      currentLifecycleRegistry: lifecycleRegistry,
      currentTaskRegistry: LocalTaskRegistry()
    )

    #expect(counters.changeCount == 1)
  }
}
