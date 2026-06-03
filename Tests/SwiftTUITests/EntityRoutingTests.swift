import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct EntityRoutingTests {
  @Test("state survives moving a keyed entity between containers")
  func stateSurvivesCrossContainerMove() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()
    let buttonIdentity = testIdentity("EntityRouting", "MoveButton")

    _ = renderer.render(
      EntityRoutingMoveRoot(
        moveRight: false,
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingMove"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: buttonIdentity))

    let moved = renderer.render(
      EntityRoutingMoveRoot(
        moveRight: true,
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingMove"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(moved.rasterSurface.lines.contains(where: { $0.contains("Right 1") }))
  }

  @Test("state survives toggling a wrapper around a keyed entity")
  func stateSurvivesWrapperToggle() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()
    let buttonIdentity = testIdentity("EntityRouting", "WrapperButton")

    _ = renderer.render(
      EntityRoutingWrapperRoot(
        wrapped: false,
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingWrapper"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: buttonIdentity))

    let wrapped = renderer.render(
      EntityRoutingWrapperRoot(
        wrapped: true,
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingWrapper"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(wrapped.rasterSurface.lines.contains(where: { $0.contains("Wrapped 1") }))
  }

  @Test("state resets when the explicit entity id changes")
  func stateResetsWhenEntityChanges() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()
    let buttonIdentity = testIdentity("EntityRouting", "ChangingIDButton")

    _ = renderer.render(
      EntityRoutingChangingIDRoot(
        entityID: "first",
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingChangingID"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: buttonIdentity))

    let changed = renderer.render(
      EntityRoutingChangingIDRoot(
        entityID: "second",
        buttonIdentity: buttonIdentity
      ),
      context: .init(
        identity: testIdentity("EntityRoutingChangingID"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(changed.rasterSurface.lines.contains(where: { $0.contains("Changing 0") }))
    #expect(changed.rasterSurface.lines.contains(where: { $0.contains("Changing 1") }) == false)
  }

  @Test("closure-owned and per-element state stay distinct across reorder")
  func closureOwnerAndElementStateStayDistinctAcrossReorder() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()
    let sharedButton = testIdentity("EntityRouting", "Shared", "1")
    let localButton = testIdentity("EntityRouting", "Local", "1")

    _ = renderer.render(
      EntityRoutingForEachOwnerRoot(items: [1, 2]),
      context: .init(
        identity: testIdentity("EntityRoutingForEachOwner"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: sharedButton))
    #expect(registry.dispatch(identity: localButton))

    let reordered = renderer.render(
      EntityRoutingForEachOwnerRoot(items: [2, 1]),
      context: .init(
        identity: testIdentity("EntityRoutingForEachOwner"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(reordered.rasterSurface.lines.contains(where: { $0.contains("Row 1 local 1") }))
    #expect(reordered.rasterSurface.lines.contains(where: { $0.contains("Row 2 local 0") }))
    #expect(reordered.rasterSurface.lines.filter { $0.contains("shared 1") }.count == 2)
  }

  @Test("same ids in independent ForEach collections keep distinct lifetimes")
  func independentForEachCollectionsDoNotShareEntityRoutes() throws {
    let renderer = DefaultRenderer()
    let registry = LocalActionRegistry()
    let leftButton = testIdentity("EntityRouting", "Independent", "Left", "1")

    _ = renderer.render(
      EntityRoutingIndependentForEachRoot(),
      context: .init(
        identity: testIdentity("EntityRoutingIndependentForEach"),
        localActionRegistry: registry,
        applyEnvironmentValues: true
      )
    )

    #expect(registry.dispatch(identity: leftButton))

    let rendered = renderer.render(
      EntityRoutingIndependentForEachRoot(),
      context: .init(
        identity: testIdentity("EntityRoutingIndependentForEach"),
        localActionRegistry: LocalActionRegistry(),
        applyEnvironmentValues: true
      )
    )

    #expect(rendered.rasterSurface.lines.contains(where: { $0.contains("Left 1 local 1") }))
    #expect(rendered.rasterSurface.lines.contains(where: { $0.contains("Right 1 local 0") }))
  }

  @Test("routing table releases entities that are truly gone")
  func routingTableReleasesGoneEntities() {
    let renderer = DefaultRenderer()

    _ = renderer.render(
      EntityRoutingListRoot(items: [1, 2, 3]),
      context: .init(identity: testIdentity("EntityRoutingChurn"))
    )
    _ = renderer.render(
      EntityRoutingListRoot(items: [3, 1, 4]),
      context: .init(identity: testIdentity("EntityRoutingChurn"))
    )
    _ = renderer.render(
      EntityRoutingListRoot(items: []),
      context: .init(identity: testIdentity("EntityRoutingChurn"))
    )

    let graph = renderer.debugRuntimeSubsystemSnapshot().viewGraph
    #expect(graph.entityRoutingTable.nodeIDByEntity.isEmpty)
    #expect(graph.entityRoutingTable.entityByNodeID.isEmpty)
  }

  @Test("duplicate ForEach ids resolve to distinct ViewNodeIDs")
  func duplicateIDsShouldResolveToDistinctViewNodeIDs() {
    let renderer = DefaultRenderer()
    _ = renderer.render(
      EntityRoutingDuplicateIDRoot(),
      context: .init(identity: testIdentity("EntityRoutingDup"))
    )

    let graph = renderer.debugRuntimeSubsystemSnapshot().viewGraph
    let elementNodeIDs = Set(
      graph.nodesByNodeID.values
        .filter { node in
          node.committed.structuralPath.components.last.map {
            "\($0)".contains("ForEachElement")
          } ?? false
        }
        .map(\.viewNodeID)
    )

    // G13 (closed) — same-collection duplicate ids (`ForEach([7, 7])`) now get
    // distinct runtime lifetimes. `ViewGraph.nodeForIdentity` is
    // occurrence-aware: a duplicate-occurrence sibling no longer adopts or
    // evicts the primary's node, so both elements coexist as separate
    // `ViewNode`s. See `swift-tui/docs/VISION-GAP.md` ("Duplicate explicit ids").
    #expect(elementNodeIDs.count == 2)
  }

  @Test("duplicate-id siblings tear down without orphaning node-store entries")
  func duplicateIDSiblingsTearDownWithoutOrphans() {
    let renderer = DefaultRenderer()
    let identity = testIdentity("EntityRoutingDupChurn")

    func elementNodeCount() -> Int {
      renderer.debugRuntimeSubsystemSnapshot().viewGraph.nodesByNodeID.values
        .filter { node in
          node.committed.structuralPath.components.last.map {
            "\($0)".contains("ForEachElement")
          } ?? false
        }
        .count
    }

    _ = renderer.render(
      EntityRoutingVariableDuplicateRoot(values: [7, 7]),
      context: .init(identity: identity)
    )
    #expect(elementNodeCount() == 2)

    _ = renderer.render(
      EntityRoutingVariableDuplicateRoot(values: [7]),
      context: .init(identity: identity)
    )
    #expect(elementNodeCount() == 1)

    _ = renderer.render(
      EntityRoutingVariableDuplicateRoot(values: []),
      context: .init(identity: identity)
    )
    #expect(elementNodeCount() == 0)

    // The collision collapse must not leave orphaned entity routes behind.
    let graph = renderer.debugRuntimeSubsystemSnapshot().viewGraph
    #expect(graph.entityRoutingTable.nodeIDByEntity.isEmpty)
    #expect(graph.entityRoutingTable.entityByNodeID.isEmpty)
  }
}

private struct EntityRoutingDuplicateIDRoot: View {
  var body: some View {
    VStack {
      ForEach([7, 7], id: \.self) { value in
        Text("Dup \(value)")
      }
    }
  }
}

private struct EntityRoutingVariableDuplicateRoot: View {
  let values: [Int]

  var body: some View {
    VStack {
      ForEach(values, id: \.self) { value in
        Text("Dup \(value)")
      }
    }
  }
}

private struct EntityRoutingIndependentForEachRoot: View {
  var body: some View {
    HStack(spacing: 2) {
      VStack(alignment: .leading, spacing: 1) {
        ForEach([1], id: \.self) { value in
          EntityRoutingIndependentRow(label: "Left", value: value)
        }
      }
      VStack(alignment: .leading, spacing: 1) {
        ForEach([1], id: \.self) { value in
          EntityRoutingIndependentRow(label: "Right", value: value)
        }
      }
    }
  }
}

private struct EntityRoutingMoveRoot: View {
  let moveRight: Bool
  let buttonIdentity: Identity

  var body: some View {
    HStack(spacing: 1) {
      VStack {
        if !moveRight {
          EntityRoutingCounter(label: "Left", buttonIdentity: buttonIdentity)
            .id("movable-counter")
        }
      }
      VStack {
        if moveRight {
          EntityRoutingCounter(label: "Right", buttonIdentity: buttonIdentity)
            .id("movable-counter")
        }
      }
    }
  }
}

private struct EntityRoutingWrapperRoot: View {
  let wrapped: Bool
  let buttonIdentity: Identity

  var body: some View {
    if wrapped {
      AnyView(
        EntityRoutingCounter(label: "Wrapped", buttonIdentity: buttonIdentity)
          .id("wrapped-counter")
      )
    } else {
      EntityRoutingCounter(label: "Wrapped", buttonIdentity: buttonIdentity)
        .id("wrapped-counter")
    }
  }
}

private struct EntityRoutingChangingIDRoot: View {
  let entityID: String
  let buttonIdentity: Identity

  var body: some View {
    EntityRoutingCounter(label: "Changing", buttonIdentity: buttonIdentity)
      .id(entityID)
  }
}

private struct EntityRoutingForEachOwnerRoot: View {
  let items: [Int]
  @State private var shared = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(items, id: \.self) { value in
        VStack(alignment: .leading, spacing: 1) {
          Text("Row \(value) shared \(shared)")
          Button("Shared \(value)") {
            shared += 1
          }
          .id(testIdentity("EntityRouting", "Shared", "\(value)"))
          EntityRoutingRowCounter(value: value)
        }
      }
    }
  }
}

private struct EntityRoutingListRoot: View {
  let items: [Int]

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(items, id: \.self) { value in
        Text("Item \(value)")
      }
    }
  }
}

private struct EntityRoutingCounter: View {
  let label: String
  let buttonIdentity: Identity
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(label) \(count)")
      Button("Increment \(label)") {
        count += 1
      }
      .id(buttonIdentity)
    }
  }
}

private struct EntityRoutingRowCounter: View {
  let value: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Row \(value) local \(local)")
      Button("Local \(value)") {
        local += 1
      }
      .id(testIdentity("EntityRouting", "Local", "\(value)"))
    }
  }
}

private struct EntityRoutingIndependentRow: View {
  let label: String
  let value: Int
  @State private var local = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(label) \(value) local \(local)")
      Button("\(label) \(value)") {
        local += 1
      }
      .id(testIdentity("EntityRouting", "Independent", label, "\(value)"))
    }
  }
}
