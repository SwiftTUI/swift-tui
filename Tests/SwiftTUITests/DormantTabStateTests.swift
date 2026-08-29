import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private struct DormantJob: Sendable {
  let identifier: Int
}

private struct DormantExecutor: Sendable {
  let identifier: Int
}

private struct DormantValueNamedIdentifier: Equatable, Sendable {
  let identifier: Int
}

private struct DormantValueNamedType: Equatable, Sendable {
  let typeCode: Int
}

@MainActor
@Suite(.serialized)
struct DormantTabStateTests {
  @Test("inactive tab bodies stay unevaluated and composed state restores before activation")
  func composedStateRestoresSynchronously() {
    let model = DormantTabModel()
    let probe = DormantTabProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsSync")

    let firstActions = LocalActionRegistry()
    let first = renderer.render(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: firstActions)
    )
    #expect(surfaceText(first).contains("A count 0"))
    #expect(!surfaceText(first).contains("B count"))
    #expect(probe.bodyEvaluations == ["A": 1])
    assertQualifiedPayloadOwners(in: renderer.viewGraph)

    #expect(firstActions.dispatch(identity: testIdentity("DormantIncrement-A")))
    let incremented = renderer.render(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(incremented).contains("A count 1"))
    let evaluationsBeforeLeavingA = probe.bodyEvaluations["A"]

    model.selection = "B"
    let second = renderer.render(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(second).contains("B count 0"))
    #expect(!surfaceText(second).contains("A count"))
    #expect(probe.bodyEvaluations["A"] == evaluationsBeforeLeavingA)
    #expect(probe.bodyEvaluations["B"] == 1)

    let owner = renderer.viewGraph.nodeForIdentity(root)
    let archived = tabDormantRegistrySnapshot(in: owner)
    #expect(archived.archivedTabCount == 1)
    #expect(archived.persistentSlotCount > 0)

    model.selection = "A"
    let restored = renderer.render(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restored).contains("A count 1"))
    #expect(!surfaceText(restored).contains("B count"))
    assertQualifiedPayloadOwners(in: renderer.viewGraph)
    assertNoDormantRestorePlaceholders(in: renderer.viewGraph)
  }

  @Test("async rendering has the same dormant state behavior")
  func composedStateRestoresAsynchronously() async {
    let model = DormantTabModel()
    let probe = DormantTabProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsAsync")
    let actions = LocalActionRegistry()

    _ = await renderer.renderAsync(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: actions)
    )
    #expect(actions.dispatch(identity: testIdentity("DormantIncrement-A")))
    _ = await renderer.renderAsync(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    model.selection = "B"
    _ = await renderer.renderAsync(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    model.selection = "A"
    let restored = await renderer.renderAsync(
      DormantTabsFixture(model: model, probe: probe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    #expect(surfaceText(restored).contains("A count 1"))
    #expect(!surfaceText(restored).contains("B count"))
  }

  @Test("authored text input and sibling state restore together after tab dormancy")
  func authoredTextInputStateRestoresWithSiblingState() async {
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsAuthoredTextInput")
    let editorIdentity = testIdentity("DormantJourneyEditor")
    let pointerIdentity = testIdentity("DormantJourneyPointer")
    var keys = LocalKeyHandlerRegistry()
    var actions = LocalActionRegistry()

    let first = await renderer.renderAsync(
      DormantEditorFixture(),
      context: dormantContext(
        root: root,
        actions: actions,
        keys: keys,
        focusedIdentity: editorIdentity
      )
    )
    #expect(surfaceText(first).contains("Editor state seed"))
    #expect(surfaceText(first).contains("Pointer count 0"))

    for character in "-native" {
      #expect(
        keys.dispatch(
          identity: editorIdentity,
          keyPress: KeyPress(.character(character))
        )
      )
      keys = LocalKeyHandlerRegistry()
      actions = LocalActionRegistry()
      _ = await renderer.renderAsync(
        DormantEditorFixture(),
        context: dormantContext(
          root: root,
          actions: actions,
          keys: keys,
          focusedIdentity: editorIdentity
        )
      )
    }
    #expect(actions.dispatch(identity: pointerIdentity))

    let edited = await renderer.renderAsync(
      DormantEditorFixture(),
      context: dormantContext(
        root: root,
        actions: LocalActionRegistry(),
        keys: LocalKeyHandlerRegistry(),
        focusedIdentity: editorIdentity
      )
    )
    #expect(surfaceText(edited).contains("Editor state seed-native"))
    #expect(surfaceText(edited).contains("Pointer count 1"))

    #expect(
      actions.dispatch(identity: testIdentity("DormantJourneyShowEvidence"))
    )
    let evidence = await renderer.renderAsync(
      DormantEditorFixture(),
      context: dormantContext(root: root, actions: actions)
    )
    #expect(surfaceText(evidence).contains("Evidence"))
    #expect(!surfaceText(evidence).contains("Editor state"))

    #expect(actions.dispatch(identity: testIdentity("DormantJourneyShowEditor")))
    let restored = await renderer.renderAsync(
      DormantEditorFixture(),
      context: dormantContext(
        root: root,
        actions: LocalActionRegistry(),
        keys: LocalKeyHandlerRegistry(),
        focusedIdentity: editorIdentity
      )
    )
    #expect(surfaceText(restored).contains("Editor state seed-native"))
    #expect(surfaceText(restored).contains("Pointer count 1"))
  }

  @Test("a departing tab archives state written while its async frame tail is suspended")
  func departingStateWriteDuringSuspendedTailRestoresNewestValue() async {
    let model = DormantTabModel()
    let bindingProbe = DormantTailWriteBindingProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsAsyncDepartingWrite")

    _ = await renderer.renderAsync(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(
      .init(beforeRaster: {
        gate.beforeRaster()
      })
    )
    defer {
      gate.release()
      renderer.setFrameTailRenderHooks(nil)
    }

    model.selection = "B"
    let switchTask = Task { @MainActor in
      await renderer.renderAsync(
        DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
    }
    await gate.waitUntilBlocked()

    bindingProbe.binding?.wrappedValue = 1
    #expect(bindingProbe.binding?.wrappedValue == 1)
    gate.release()
    _ = await switchTask.value

    model.selection = "A"
    let restored = await renderer.renderAsync(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    #expect(surfaceText(restored).contains("A count 1"))
    #expect(!surfaceText(restored).contains("B count"))
  }

  @Test("a suspended tail with no departing write preserves the head archive value")
  func suspendedTailWithoutDepartingWritePreservesArchiveValue() async {
    let model = DormantTabModel()
    let bindingProbe = DormantTailWriteBindingProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsAsyncNoDepartingWrite")

    _ = await renderer.renderAsync(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      renderer.setFrameTailRenderHooks(nil)
    }

    model.selection = "B"
    let switchTask = Task { @MainActor in
      await renderer.renderAsync(
        DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
    }
    await gate.waitUntilBlocked()
    #expect(bindingProbe.binding?.wrappedValue == 0)
    gate.release()
    _ = await switchTask.value

    model.selection = "A"
    let restored = await renderer.renderAsync(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restored).contains("A count 0"))
  }

  @Test("a discarded completed tail does not commit its dormant archive refresh")
  func discardedCompletedTailDoesNotCommitDormantArchiveRefresh() async throws {
    let model = DormantTabModel()
    let bindingProbe = DormantTailWriteBindingProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsDiscardedDepartingWrite")

    _ = renderer.render(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    bindingProbe.binding?.wrappedValue = 1
    let committed = renderer.render(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(committed).contains("A count 1"))
    let archiveBefore = tabDormantRegistrySnapshot(
      in: renderer.viewGraph.nodeForIdentity(root)
    )

    model.selection = "B"
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      renderer.setFrameTailRenderHooks(nil)
    }
    let discardTask = Task { @MainActor in
      await renderer.discardPreparedFrameTailForReconciliationTesting(
        draft,
        decision: .dropVisualOnly(
          eligibility: FrameDropEligibility(decision: .canDropVisualOnly)
        )
      )
    }
    await gate.waitUntilBlocked()
    bindingProbe.binding?.wrappedValue = 2
    #expect(bindingProbe.binding?.wrappedValue == 2)
    #expect(
      tabDormantRegistrySnapshot(in: renderer.viewGraph.nodeForIdentity(root))
        == archiveBefore,
      "a candidate's value-only refresh must not publish while its tail is suspended"
    )
    gate.release()
    let discarded = await discardTask.value
    #expect(discarded)
    #expect(
      tabDormantRegistrySnapshot(in: renderer.viewGraph.nodeForIdentity(root))
        == archiveBefore
    )

    let acceptedDeparture = renderer.render(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(acceptedDeparture).contains("A B"))
    model.selection = "A"
    let restored = renderer.render(
      DormantTailWriteFixture(model: model, bindingProbe: bindingProbe),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(
      surfaceText(restored).contains("A count 1"),
      "the dropped candidate's late value 2 must not replace committed value 1"
    )
  }

  @Test("a stale dormant refresh token cannot replace a newer tab archive")
  func staleDormantRefreshTokenIsIgnored() throws {
    let model = DormantTabModel()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsStaleRefreshToken")

    let firstActions = LocalActionRegistry()
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: firstActions)
    )
    #expect(firstActions.dispatch(identity: testIdentity("DormantIncrement-A")))
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    model.selection = "B"
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    let ownerNode = try #require(renderer.viewGraph.nodeForIdentity(root))
    let owner = try #require(ownerNode.stateOwnerHandle)
    let registryBefore = tabDormantRegistrySnapshot(in: ownerNode)

    applyDormantTabArchiveCommitRefreshes(
      [
        DormantTabArchiveCommitRefresh(
          owner: owner,
          key: TabDormantKey(
            value: AnyID("A"),
            includeOptional: false,
            occurrence: 0
          ),
          refreshToken: .max,
          archive: DormantStateArchive()
        )
      ],
      in: renderer.viewGraph
    )
    #expect(tabDormantRegistrySnapshot(in: ownerNode) == registryBefore)

    model.selection = "A"
    let restored = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restored).contains("A count 1"))
  }

  @Test("multiple departing tab owners refresh independently in one candidate")
  func multipleDepartingTabOwnersRefreshIndependently() async {
    let leftModel = DormantTabModel()
    let rightModel = DormantTabModel()
    let leftProbe = DormantTailWriteBindingProbe()
    let rightProbe = DormantTailWriteBindingProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsMultipleDepartingOwners")
    let fixture = DormantDualTailWriteFixture(
      leftModel: leftModel,
      rightModel: rightModel,
      leftProbe: leftProbe,
      rightProbe: rightProbe
    )

    _ = await renderer.renderAsync(
      fixture,
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      renderer.setFrameTailRenderHooks(nil)
    }

    leftModel.selection = "B"
    rightModel.selection = "B"
    let switchTask = Task { @MainActor in
      await renderer.renderAsync(
        fixture,
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
    }
    await gate.waitUntilBlocked()
    leftProbe.binding?.wrappedValue = 1
    rightProbe.binding?.wrappedValue = 2
    #expect(leftProbe.binding?.wrappedValue == 1)
    #expect(rightProbe.binding?.wrappedValue == 2)
    gate.release()
    _ = await switchTask.value

    leftModel.selection = "A"
    rightModel.selection = "A"
    let restored = await renderer.renderAsync(
      fixture,
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restored).contains("left count 1"))
    #expect(surfaceText(restored).contains("right count 2"))
  }

  @Test("active tab lifetimes own distinct qualified structural state nodes")
  func activePayloadLifetimesDistinguishStateOwners() throws {
    let model = DormantPayloadOwnerModel()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantPayloadOwners")

    let first = renderer.render(
      DormantPayloadOwnerFixture(model: model),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(first).contains("A owner 1"))
    let firstOwner = try #require(payloadOwnership(in: renderer.viewGraph))
    #expect(firstOwner.hostEntityIdentity != nil)
    #expect(firstOwner.stateOwnerEntityIdentity == nil)
    #expect(firstOwner.stateSlotTypes.contains("Swift.Int"))
    #expect(
      firstOwner.stateOwnerIdentity.contains("/TabContentPayload/TabContentValue[")
    )
    #expect(firstOwner.stateOwnerIdentity.contains("Swift.String:\"A\""))
    #expect(
      firstOwner.stateOwnerIdentity.contains(
        ";optional=true;occurrence=0;generation=0]"
      )
    )

    let repeated = renderer.render(
      DormantPayloadOwnerFixture(model: model),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(repeated).contains("A owner 1"))
    let repeatedOwner = try #require(payloadOwnership(in: renderer.viewGraph))
    #expect(repeatedOwner.hostViewNodeID == firstOwner.hostViewNodeID)
    #expect(repeatedOwner.stateOwnerViewNodeID == firstOwner.stateOwnerViewNodeID)
    #expect(repeatedOwner.stateOwnerIdentity == firstOwner.stateOwnerIdentity)

    model.selection = "B"
    let second = renderer.render(
      DormantPayloadOwnerFixture(model: model),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(
      surfaceText(second).contains("B owner 2"),
      "a newly active tab must not read the previous tag's positional state slot"
    )
    let secondOwner = try #require(payloadOwnership(in: renderer.viewGraph))
    #expect(secondOwner.hostEntityIdentity != nil)
    #expect(secondOwner.stateOwnerEntityIdentity == nil)
    #expect(secondOwner.stateSlotTypes.contains("Swift.Int"))
    #expect(secondOwner.stateOwnerIdentity.contains("Swift.String:\"B\""))
    #expect(
      secondOwner.stateOwnerIdentity.contains(
        ";optional=true;occurrence=0;generation=1]"
      )
    )
    #expect(secondOwner.hostViewNodeID != firstOwner.hostViewNodeID)
    #expect(secondOwner.hostEntityIdentity != firstOwner.hostEntityIdentity)
    #expect(secondOwner.stateOwnerViewNodeID != firstOwner.stateOwnerViewNodeID)
    #expect(secondOwner.stateOwnerIdentity != firstOwner.stateOwnerIdentity)
  }

  @Test("a nested TabView rejoins its archived payload lifetimes with its outer tab")
  func nestedTabViewRejoinsArchivedPayloadLifetimes() {
    let outerModel = DormantTabModel()
    let innerModel = DormantTabModel()
    let probe = DormantTabProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("NestedDormantTabs")

    let firstActions = LocalActionRegistry()
    let first = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: firstActions)
    )
    #expect(surfaceText(first).contains("inner-A count 0"))
    #expect(firstActions.dispatch(identity: testIdentity("DormantIncrement-inner-A")))
    let incrementedA = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(incrementedA).contains("inner-A count 1"))

    innerModel.selection = "B"
    let innerBActions = LocalActionRegistry()
    let innerB = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: innerBActions)
    )
    #expect(surfaceText(innerB).contains("inner-B count 0"))
    #expect(innerBActions.dispatch(identity: testIdentity("DormantIncrement-inner-B")))
    let incrementedB = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(incrementedB).contains("inner-B count 1"))
    let innerEntityBeforeOuterDeparture = nestedTabContentHostEntity(
      in: renderer.viewGraph
    )
    #expect(innerEntityBeforeOuterDeparture != nil)
    #expect(
      innerEntityBeforeOuterDeparture
        != outerTabContentHostEntity(in: renderer.viewGraph),
      "inner and outer TabViews must own isolated payload entities"
    )
    let evaluationsBeforeOuterDeparture = probe.bodyEvaluations
    let nestedValueArchive = renderer.viewGraph.captureDormantStateArchive(rootedAt: root)
    let persistentRegistryRecords = nestedValueArchive.records.filter { record in
      record.stateSlots.keys.contains {
        $0.ordinal == StateSlotOrdinals.tabDormantArchive
      }
    }
    #expect(persistentRegistryRecords.count == 2)
    #expect(
      nestedValueArchive.records.allSatisfy { record in
        !record.stateSlots.keys.contains {
          $0.ordinal == StateSlotOrdinals.tabDormantArchive - 1
        }
      },
      "live dormant-state locators must remain transient raw-ID recipes"
    )

    outerModel.selection = "B"
    let outerBActions = LocalActionRegistry()
    let outerB = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: outerBActions)
    )
    #expect(surfaceText(outerB).contains("outer-B"))
    #expect(!surfaceText(outerB).contains("inner-"))
    #expect(probe.bodyEvaluations == evaluationsBeforeOuterDeparture)
    #expect(
      !outerBActions.hasHandler(identity: testIdentity("DormantIncrement-inner-B")),
      "the dormant nested payload must not retain its action registration"
    )

    outerModel.selection = "A"
    let restoredB = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restoredB).contains("inner-B count 1"))
    #expect(!surfaceText(restoredB).contains("inner-A count"))
    #expect(
      nestedTabContentHostEntity(in: renderer.viewGraph)
        == innerEntityBeforeOuterDeparture,
      "the inner TabView must rejoin the same enclosing-entity-derived payload lifetime"
    )

    innerModel.selection = "A"
    let restoredA = renderer.render(
      NestedDormantTabsFixture(
        outerModel: outerModel,
        innerModel: innerModel,
        probe: probe
      ),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restoredA).contains("inner-A count 1"))
    #expect(!surfaceText(restoredA).contains("inner-B count"))

    for iteration in 0..<12 {
      innerModel.selection = iteration.isMultiple(of: 2) ? "A" : "B"
      _ = renderer.render(
        NestedDormantTabsFixture(
          outerModel: outerModel,
          innerModel: innerModel,
          probe: probe
        ),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
      let evaluationsBeforeDormancy = probe.bodyEvaluations
      outerModel.selection = "B"
      _ = renderer.render(
        NestedDormantTabsFixture(
          outerModel: outerModel,
          innerModel: innerModel,
          probe: probe
        ),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
      #expect(probe.bodyEvaluations == evaluationsBeforeDormancy)
      outerModel.selection = "A"
      _ = renderer.render(
        NestedDormantTabsFixture(
          outerModel: outerModel,
          innerModel: innerModel,
          probe: probe
        ),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
    }

    let graph = renderer.viewGraph.debugTotalStateSnapshot()
    #expect(graph.effectRegistrationOwnerNodeIDs.isSubset(of: graph.liveNodeIDs))
    #expect(graph.nodesByNodeID.count < 60)
    assertNoDormantRestorePlaceholders(in: renderer.viewGraph)
  }

  @Test("duplicate tab tags keep occurrence isolation and emit the supported warning")
  func duplicateTabTagsEmitWarning() {
    let model = DormantTabModel()
    let resolved = Resolver().resolve(
      TabView(selection: model.selectionBinding) {
        Tab("first-A", value: "A") { Text("first") }
        Tab("second-A", value: "A") { Text("second") }
        Tab("B", value: "B") { Text("B") }
      },
      in: ResolveContext(identity: testIdentity("DormantDuplicateTags"))
    )

    let issues = resolved.preferenceValues[RuntimeIssuePreferenceKey.self]
      .filter { $0.code == "tab.duplicateTag" }
    #expect(issues.count == 1)
    #expect(issues[0].message.contains("occurrence 1"))
  }

  @Test("tag identity survives reorder while removal and owner replacement evict archives")
  func reorderRemovalAndOwnerReplacement() {
    let model = DormantTabModel()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsIdentity")

    let actions = LocalActionRegistry()
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: actions)
    )
    #expect(actions.dispatch(identity: testIdentity("DormantIncrement-A")))
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    model.selection = "B"
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    model.reversed = true
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    model.selection = "A"
    let reordered = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(reordered).contains("A count 1"))

    model.selection = "B"
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    model.includesA = false
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    let owner = renderer.viewGraph.nodeForIdentity(root)
    #expect(tabDormantRegistrySnapshot(in: owner).archivedTabCount == 0)

    model.includesA = true
    model.selection = "A"
    let reinserted = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(reinserted).contains("A count 0"))

    let replacementActions = LocalActionRegistry()
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: replacementActions)
    )
    #expect(replacementActions.dispatch(identity: testIdentity("DormantIncrement-A")))
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    model.selection = "B"
    _ = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )

    model.ownerGeneration += 1
    model.selection = "A"
    let replacedOwner = renderer.render(
      DormantTabsFixture(model: model, probe: DormantTabProbe()),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(replacedOwner).contains("A count 0"))
  }

  @Test("FocusState restores but GestureState and gesture registrations do not")
  func persistentFocusAndTransientGestureState() {
    let model = DormantTabModel()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsTransient")
    let gestures = LocalGestureRegistry()
    let gestureStates = LocalGestureStateRegistry()
    let actions = LocalActionRegistry()

    _ = renderer.render(
      DormantFocusGestureFixture(model: model),
      context: dormantContext(
        root: root,
        actions: actions,
        gestures: gestures,
        gestureStates: gestureStates
      )
    )
    #expect(actions.dispatch(identity: testIdentity("DormantFocusToggle")))
    #expect(gestureStates.snapshot().values.reduce(0) { $0 + $1.count } == 1)

    let mutated = renderer.render(
      DormantFocusGestureFixture(model: model),
      context: dormantContext(
        root: root,
        actions: LocalActionRegistry(),
        gestures: gestures,
        gestureStates: gestureStates
      )
    )
    #expect(surfaceText(mutated).contains("focus true gesture 0"))

    model.selection = "B"
    _ = renderer.render(
      DormantFocusGestureFixture(model: model),
      context: dormantContext(
        root: root,
        actions: LocalActionRegistry(),
        gestures: gestures,
        gestureStates: gestureStates
      )
    )
    #expect(gestureStates.snapshot().isEmpty)

    model.selection = "A"
    let restored = renderer.render(
      DormantFocusGestureFixture(model: model),
      context: dormantContext(
        root: root,
        actions: LocalActionRegistry(),
        gestures: gestures,
        gestureStates: gestureStates
      )
    )
    #expect(surfaceText(restored).contains("focus true gesture 0"))
    #expect(gestureStates.snapshot().values.reduce(0) { $0 + $1.count } == 1)
  }

  @Test("navigation activation and lifecycle restart after dormancy")
  func navigationAndLifecycleRestoreAsValuesOnly() {
    let model = DormantTabModel()
    let lifecycleProbe = DormantLifecycleProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsNavigation")
    let coordinator = LifecycleCoordinator()

    func render() -> RenderSnapshot {
      let lifecycle = LocalLifecycleRegistry()
      let tasks = LocalTaskRegistry()
      let snapshot = renderer.render(
        DormantNavigationFixture(model: model, lifecycleProbe: lifecycleProbe),
        context: ResolveContext(
          identity: root,
          localLifecycleRegistry: lifecycle,
          localTaskRegistry: tasks,
          applyEnvironmentValues: true
        )
      )
      coordinator.applyCommittedFrame(
        plan: snapshot.commitPlan,
        currentLifecycleRegistry: lifecycle,
        currentTaskRegistry: tasks
      )
      return snapshot
    }

    let first = render()
    #expect(surfaceText(first).contains("detail-A"))
    #expect(lifecycleProbe.appears == 1)

    model.selection = "B"
    let second = render()
    #expect(surfaceText(second).contains("plain-B"))
    #expect(lifecycleProbe.disappears == 1)

    let archived = tabDormantRegistrySnapshot(in: renderer.viewGraph.nodeForIdentity(root))
    #expect(archived.persistentSlotCount >= 2)

    model.selection = "A"
    let restored = render()
    #expect(surfaceText(restored).contains("detail-A"))
    #expect(lifecycleProbe.appears == 2)
  }

  @Test("SIMD vectors and Foundation value leaves archive as dormant state")
  func simdAndFoundationValueLeavesArchive() throws {
    // Gallery shapes that the audit used to reject: a mesh-gradient point
    // array (`[SIMD2<Float>]` reflects its lanes as a `Builtin.Vec…` leaf)
    // and `Identifiable` rows keyed by `UUID` (a Foundation struct whose
    // custom mirror is empty). Both are plain values and must round-trip.
    let root = testIdentity("DormantSIMDFoundationLeaves")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    let points: [SIMD2<Float>] = [SIMD2(0.25, 0.75), SIMD2(1, 0)]
    let rowID = UUID()
    let stamp = Date(timeIntervalSinceReferenceDate: 1_234.5)
    let rows = [DormantIdentifiedRow(id: rowID, title: "Write docs", done: false)]

    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 3_001, value: points)
      node.setStateSlotSilently(ordinal: 3_002, value: rowID)
      node.setStateSlotSilently(ordinal: 3_003, value: stamp)
      node.setStateSlotSilently(ordinal: 3_004, value: rows)
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)
    let issues = graph.frameRuntimeIssues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(issues.isEmpty, "unexpected rejections: \(issues.map(\.message))")
    #expect(archive.persistentSlotCount == 4)

    let restoredGraph = ViewGraph()
    restoredGraph.beginFrame()
    restoredGraph.restoreDormantStateArchive(archive)
    let restoredNode = try #require(restoredGraph.nodeForIdentity(root))
    #expect(
      try #require(restoredNode.stateSlotStorage(ordinal: 3_001)).value(as: [SIMD2<Float>].self)
        == points
    )
    #expect(try #require(restoredNode.stateSlotStorage(ordinal: 3_002)).value(as: UUID.self) == rowID)
    #expect(try #require(restoredNode.stateSlotStorage(ordinal: 3_003)).value(as: Date.self) == stamp)
    #expect(
      try #require(restoredNode.stateSlotStorage(ordinal: 3_004)).value(
        as: [DormantIdentifiedRow].self
      ) == rows
    )
  }

  @Test("a Foundation reference behind a value wrapper is still rejected")
  func foundationReferencesStayRejected() throws {
    // Trusting Foundation's value-type mirrors must not become a door for
    // reference payloads: the metadata-kind check still rejects a class, and
    // a Foundation struct whose mirror exposes a raw pointer (`Data`) still
    // hits the pointer leaf rule.
    let root = testIdentity("DormantFoundationReferences")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 3_011, value: NSObject())
      node.setStateSlotSilently(ordinal: 3_012, value: Data([1, 2, 3]))
    }
    let archive = graph.captureDormantStateArchive(rootedAt: root)
    #expect(archive.persistentSlotCount == 0)
    let issues = graph.frameRuntimeIssues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(issues.count == 2, "issues: \(issues.map(\.message))")
  }

  @Test("a TextEditor's measured-width scratch never reaches the dormant archive")
  func textEditorScratchStateIsTransientForDormancy() async {
    // The editor carries a reference-typed width carrier in `@State` so the
    // layout pass can write it without scheduling a frame. It is re-derived on
    // the first layout after reactivation, so it is declared transient for
    // dormancy — the archive must neither store it nor warn about it.
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTextEditorScratch")
    var actions = LocalActionRegistry()
    let first = await renderer.renderAsync(
      DormantTextEditorFixture(),
      context: dormantContext(root: root, actions: actions)
    )
    #expect(surfaceText(first).contains("editor seed"))

    #expect(actions.dispatch(identity: testIdentity("DormantTextEditorShowOther")))
    actions = LocalActionRegistry()
    let departed = await renderer.renderAsync(
      DormantTextEditorFixture(),
      context: dormantContext(root: root, actions: actions)
    )
    #expect(surfaceText(departed).contains("Other"))
    let unsupported = departed.diagnostics.runtime.issues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(unsupported.isEmpty, "unexpected: \(unsupported.map(\.message))")

    #expect(actions.dispatch(identity: testIdentity("DormantTextEditorShowEditor")))
    let restored = await renderer.renderAsync(
      DormantTextEditorFixture(),
      context: dormantContext(root: root, actions: LocalActionRegistry())
    )
    #expect(surfaceText(restored).contains("editor seed"))
  }

  @Test("collection scroll anchors are persistent archive values")
  func collectionScrollAnchorRoundTripsThroughArchive() throws {
    let root = testIdentity("DormantScrollAnchor")
    let sourceGraph = ViewGraph()
    sourceGraph.beginFrame()
    let sourceNode = sourceGraph.beginEvaluation(identity: root, invalidator: nil)
    let expected = CollectionScrollAnchor(firstVisibleItemIndex: 17, intraItemLineOffset: 0)
    setStoredCollectionScrollAnchor(expected, in: sourceNode)
    withPersistentDormantStateSlot {
      sourceNode.setStateSlotSilently(
        ordinal: 1_001,
        value: DormantReferenceValue()
      )
    }

    _ = sourceGraph.captureDormantStateArchive(rootedAt: root)
    _ = sourceGraph.captureDormantStateArchive(rootedAt: root)
    let classIssues = sourceGraph.frameRuntimeIssues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(classIssues.count == 1)
    #expect(classIssues.first?.message.contains("hoist") == true)

    withPersistentDormantStateSlot {
      sourceNode.setStateSlotSilently(
        ordinal: 1_002,
        value: { @MainActor in }
      )
    }

    let archive = sourceGraph.captureDormantStateArchive(rootedAt: root)
    #expect(archive.persistentSlotCount == 1)

    let restoredGraph = ViewGraph()
    restoredGraph.beginFrame()
    restoredGraph.restoreDormantStateArchive(archive)
    let restoredNode = try #require(restoredGraph.nodeForIdentity(root))
    #expect(storedCollectionScrollAnchor(in: restoredNode) == expected)
    #expect(restoredNode.stateSlotStorage(ordinal: 1_001) == nil)
    #expect(restoredNode.stateSlotStorage(ordinal: 1_002) == nil)
  }

  @Test("raw pointers are rejected from dormant state with an interpolated warning")
  func rawPointersAreNotArchived() throws {
    let root = testIdentity("DormantRawPointers")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    let raw = unsafe UnsafeRawPointer(bitPattern: 0x1)!
    let mutable = unsafe UnsafeMutableRawPointer(bitPattern: 0x2)!

    withPersistentDormantStateSlot {
      unsafe node.setStateSlotSilently(ordinal: 2_001, value: raw)
      unsafe node.setStateSlotSilently(ordinal: 2_002, value: mutable)
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)
    #expect(archive.persistentSlotCount == 0)
    let issues = graph.frameRuntimeIssues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(issues.count == 2)
    #expect(
      issues.contains {
        $0.message.contains("2001") && $0.message.contains("UnsafeRawPointer")
      }
    )
    #expect(
      issues.contains {
        $0.message.contains("2002") && $0.message.contains("UnsafeMutableRawPointer")
      }
    )
  }

  @Test("runtime identity leaves are rejected without name-based false positives")
  func objectIdentifiersAndMetatypesAreNotArchived() throws {
    #expect(AnyStateSlot.malformedDormantSnapshotIsRejectedForTesting())

    let root = testIdentity("DormantRuntimeIdentityLeaves")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    let reference = DormantReferenceValue()

    withPersistentDormantStateSlot {
      node.setStateSlotSilently(
        ordinal: 2_011,
        value: ObjectIdentifier(reference)
      )
      node.setStateSlotSilently(ordinal: 2_012, value: Int.self)
      node.setStateSlotSilently(
        ordinal: 2_013,
        value: DormantValueNamedIdentifier(identifier: 13)
      )
      node.setStateSlotSilently(
        ordinal: 2_014,
        value: DormantValueNamedType(typeCode: 14)
      )
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)
    #expect(archive.persistentSlotCount == 2)

    let restoredGraph = ViewGraph()
    restoredGraph.beginFrame()
    restoredGraph.restoreDormantStateArchive(archive)
    let restoredNode = try #require(restoredGraph.nodeForIdentity(root))
    #expect(restoredNode.stateSlotStorage(ordinal: 2_011) == nil)
    #expect(restoredNode.stateSlotStorage(ordinal: 2_012) == nil)
    let namedIdentifier = try #require(
      restoredNode.stateSlotStorage(ordinal: 2_013)
    )
    #expect(
      namedIdentifier.value(as: DormantValueNamedIdentifier.self).identifier == 13
    )
    let namedType = try #require(restoredNode.stateSlotStorage(ordinal: 2_014))
    #expect(
      namedType.value(as: DormantValueNamedType.self).typeCode == 14
    )

    let issues = graph.frameRuntimeIssues.filter {
      $0.code == "tab.dormantStateUnsupportedValue"
    }
    #expect(issues.count == 2)
    #expect(issues.contains { $0.message.contains("Swift.ObjectIdentifier") })
    #expect(issues.contains { $0.message.contains("Swift.Int.Type") })
  }

  @Test("a class cannot hide behind a struct-shaped custom mirror in dormant state")
  func customMirrorCannotMaskAClass() {
    let root = testIdentity("DormantMaskedClass")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 2_101, value: DormantMaskedClass())
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)

    #expect(archive.persistentSlotCount == 0)
  }

  @Test("a value wrapper cannot hide a reference behind an empty custom mirror")
  func customMirrorCannotMaskAReferenceContainingValue() {
    let root = testIdentity("DormantMaskedReferenceWrapper")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    withPersistentDormantStateSlot {
      node.setStateSlotSilently(
        ordinal: 2_102,
        value: DormantMaskedReferenceWrapper(reference: DormantReferenceValue())
      )
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)

    #expect(archive.persistentSlotCount == 0)
  }

  @Test("a recursive custom mirror is rejected without recursive inspection")
  func recursiveCustomMirrorCannotExhaustDormantInspection() {
    let root = testIdentity("DormantRecursiveCustomMirror")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)
    let recursive = DormantRecursiveCustomMirror(remainingDepth: 256)
    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 2_103, value: recursive)
    }

    let archive = graph.captureDormantStateArchive(rootedAt: root)

    #expect(archive.persistentSlotCount == 0)
    #expect(recursive.mirrorReadCount == 0)
  }

  @Test("continuations and opaque stream handles are rejected from dormant state")
  func continuationRuntimeHandlesAreNotArchived() async {
    let root = testIdentity("DormantRuntimeHandles")
    let graph = ViewGraph()
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: root, invalidator: nil)

    var unsafeCount = -1
    await unsafe withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
      withPersistentDormantStateSlot {
        unsafe node.setStateSlotSilently(ordinal: 2_201, value: continuation)
      }
      unsafeCount = graph.captureDormantStateArchive(rootedAt: root).persistentSlotCount
      unsafe continuation.resume()
    }
    #expect(unsafeCount == 0)

    var checkedCount = -1
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      withPersistentDormantStateSlot {
        node.setStateSlotSilently(ordinal: 2_202, value: continuation)
      }
      checkedCount = graph.captureDormantStateArchive(rootedAt: root).persistentSlotCount
      continuation.resume()
    }
    #expect(checkedCount == 0)

    var streamContinuation: AsyncStream<Int>.Continuation?
    let stream = AsyncStream<Int> { streamContinuation = $0 }
    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 2_203, value: streamContinuation!)
    }
    let streamCount = graph.captureDormantStateArchive(rootedAt: root).persistentSlotCount
    streamContinuation?.finish()
    withExtendedLifetime(stream) {}
    #expect(streamCount == 0)

    let executor = unsafe MainActor.shared.unownedExecutor
    withPersistentDormantStateSlot {
      unsafe node.setStateSlotSilently(ordinal: 2_204, value: executor)
    }
    let executorCount = graph.captureDormantStateArchive(rootedAt: root).persistentSlotCount
    #expect(executorCount == 0)

    withPersistentDormantStateSlot {
      node.setStateSlotSilently(ordinal: 2_205, value: DormantJob(identifier: 7))
      node.setStateSlotSilently(ordinal: 2_206, value: DormantExecutor(identifier: 8))
    }
    let valueNamedCount = graph.captureDormantStateArchive(rootedAt: root).persistentSlotCount
    #expect(valueNamedCount == 2)
  }

  @Test("repeated switches keep graph nodes, effects, and archives bounded")
  func graphAndArchiveStorageRemainBounded() {
    let model = DormantTabModel()
    let renderer = DefaultRenderer()
    let root = testIdentity("DormantTabsBounded")

    for iteration in 0..<64 {
      model.selection = iteration.isMultiple(of: 2) ? "A" : "B"
      _ = renderer.render(
        DormantTabsFixture(model: model, probe: DormantTabProbe()),
        context: dormantContext(root: root, actions: LocalActionRegistry())
      )
    }

    let graph = renderer.viewGraph.debugTotalStateSnapshot()
    #expect(Set(graph.nodesByNodeID.keys) == graph.liveNodeIDs)
    #expect(graph.effectRegistrationOwnerNodeIDs.isSubset(of: graph.liveNodeIDs))
    #expect(graph.nodesByNodeID.count < 40)

    let archive = tabDormantRegistrySnapshot(in: renderer.viewGraph.nodeForIdentity(root))
    #expect(archive.archivedTabCount == 1)
    #expect(archive.archivedNodeCount < 20)
  }

  @Test("a returning dormant tab whose content .id moved keeps its task registration")
  func returningDormantTabWithMovedContentIDKeepsItsTask() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DormantTabTaskIdentityChurn"),
      size: .init(width: 48, height: 12)
    ) {
      DormantTaskIdentityChurnFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 1)

    // Generation 1 activates a tab that has never been dormant, so there is no
    // archive to seed. Generation 2 is the first RETURN to a tab that has one,
    // and its content `.id` moved while it was away — the archive's records
    // name the departed identity. Seeding them must not claim the arriving
    // content's entity route, or the arriving node loses co-residency to the
    // placeholder and is retired in the frame that built it, taking its task
    // registration with it. The start is then dropped as superseded, which is
    // silent: `taskStartSkipCount` stays 0, so assert the superseded counter.
    for generation in 1...4 {
      _ = try harness.clickText("Cycle")
      #expect(
        harness.activeTaskCount == 1,
        "generation \(generation) lost its task registration"
      )
      #expect(
        harness.runLoop.lifecycleCoordinator.taskStartSupersededCount == 0,
        "generation \(generation) had a genuine task start dropped as superseded"
      )
    }
  }
}

private struct DormantTaskIdentityChurnFixture: View {
  @State private var selection = "left"
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle") {
        generation += 1
        selection = selection == "left" ? "right" : "left"
      }

      TabView(selection: $selection) {
        Tab("Left", value: "left") {
          DormantTaskIdentityChurnPane(label: "left", generation: generation)
            .id("left-\(generation)")
        }

        Tab("Right", value: "right") {
          DormantTaskIdentityChurnPane(label: "right", generation: generation)
            .id("right-\(generation)")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 48, height: 12, alignment: .topLeading)
  }
}

private struct DormantTaskIdentityChurnPane: View {
  let label: String
  let generation: Int

  var body: some View {
    Text("task \(label) generation \(generation)")
      .task(id: generation) {
        await suspendUntilCancelled()
      }
  }
}

@MainActor
private final class DormantTabModel {
  var selection = "A"
  var reversed = false
  var includesA = true
  var ownerGeneration = 0

  var selectionBinding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
private final class DormantPayloadOwnerModel {
  var selection = "A"

  var selectionBinding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

private struct DormantPayloadOwnershipSnapshot {
  var hostViewNodeID: ViewNodeID
  var hostEntityIdentity: EntityIdentity?
  var stateOwnerViewNodeID: ViewNodeID
  var stateOwnerIdentity: String
  var stateOwnerEntityIdentity: EntityIdentity?
  var stateSlotTypes: [String]
}

@MainActor
private func payloadOwnership(
  in graph: ViewGraph
) -> DormantPayloadOwnershipSnapshot? {
  let nodes = graph.debugTotalStateSnapshot().nodesByNodeID.values
  let hosts = nodes.filter { snapshot in
    String(describing: snapshot.committed.identity).hasSuffix("/TabContentPayload")
      && snapshot.committed.entityIdentity != nil
  }
  guard hosts.count == 1, let host = hosts.first else {
    return nil
  }
  let stateOwners = nodes.filter { snapshot in
    String(describing: snapshot.committed.identity).contains(
      "/TabContentPayload/TabContentValue["
    ) && !snapshot.stateSlots.isEmpty
  }
  guard stateOwners.count == 1, let stateOwner = stateOwners.first else {
    return nil
  }
  return DormantPayloadOwnershipSnapshot(
    hostViewNodeID: host.viewNodeID,
    hostEntityIdentity: host.committed.entityIdentity ?? host.lastHomedEntityIdentity,
    stateOwnerViewNodeID: stateOwner.viewNodeID,
    stateOwnerIdentity: String(describing: stateOwner.committed.identity),
    stateOwnerEntityIdentity:
      stateOwner.committed.entityIdentity ?? stateOwner.lastHomedEntityIdentity,
    stateSlotTypes: stateOwner.stateSlots.map(\.storedTypeDescription)
  )
}

@MainActor
private func outerTabContentHostEntity(in graph: ViewGraph) -> EntityIdentity? {
  tabContentHostEntities(in: graph)[1]
}

@MainActor
private func nestedTabContentHostEntity(in graph: ViewGraph) -> EntityIdentity? {
  tabContentHostEntities(in: graph)[2]
}

@MainActor
private func tabContentHostEntities(in graph: ViewGraph) -> [Int: EntityIdentity] {
  graph.debugTotalStateSnapshot().nodesByNodeID.values.reduce(into: [:]) {
    result, snapshot in
    let identity = String(describing: snapshot.committed.identity)
    guard identity.hasSuffix("/TabContentPayload"),
      let entity = snapshot.committed.entityIdentity ?? snapshot.lastHomedEntityIdentity
    else {
      return
    }
    let depth = identity.split(separator: "/").count { $0 == "TabContentPayload" }
    result[depth] = entity
  }
}

@MainActor
private func assertQualifiedPayloadOwners(in graph: ViewGraph) {
  let nodes = graph.debugTotalStateSnapshot().nodesByNodeID.values
  let hosts = nodes.filter { snapshot in
    String(describing: snapshot.committed.identity).hasSuffix("/TabContentPayload")
      && (snapshot.committed.entityIdentity ?? snapshot.lastHomedEntityIdentity) != nil
      && snapshot.stateSlots.isEmpty
  }
  let stateOwners = nodes.filter { snapshot in
    let identity = String(describing: snapshot.committed.identity)
    return identity.contains("/TabContentPayload/TabContentValue[")
      && identity.contains(";optional=true;occurrence=0;generation=0]")
      && snapshot.stateSlots.contains { $0.storedTypeDescription == "Swift.Int" }
  }
  #expect(hosts.count == 1)
  #expect(stateOwners.count == 1)
  if let host = hosts.first, let stateOwner = stateOwners.first {
    #expect(host.viewNodeID != stateOwner.viewNodeID)
    #expect(
      (host.committed.entityIdentity ?? host.lastHomedEntityIdentity)
        != (stateOwner.committed.entityIdentity ?? stateOwner.lastHomedEntityIdentity)
    )
  }
}

@MainActor
private func assertNoDormantRestorePlaceholders(in graph: ViewGraph) {
  let nodes = graph.debugTotalStateSnapshot().nodesByNodeID.values
  let placeholders = nodes.compactMap { snapshot -> String? in
    guard let node = graph.nodeForViewNodeID(snapshot.viewNodeID) else {
      return nil
    }
    let identity = String(describing: node.identity)
    return identity.contains("DormantRestoreSeed") ? identity : nil
  }
  #expect(placeholders.isEmpty, "unadopted dormant placeholders: \(placeholders)")
}

@MainActor
private final class DormantTabProbe {
  var bodyEvaluations: [String: Int] = [:]

  func evaluated(_ tag: String) {
    bodyEvaluations[tag, default: 0] += 1
  }
}

@MainActor
private final class DormantLifecycleProbe {
  var appears = 0
  var disappears = 0
}

@MainActor
private final class DormantReferenceValue {}

private final class DormantMaskedClass: CustomReflectable {
  var customMirror: Mirror {
    Mirror(self, children: [:], displayStyle: .struct)
  }
}

private struct DormantMaskedReferenceWrapper: CustomReflectable {
  let reference: DormantReferenceValue

  var customMirror: Mirror {
    Mirror(self, children: [:], displayStyle: .struct)
  }
}

private final class DormantRecursiveCustomMirror: CustomReflectable {
  private var remainingDepth: Int
  private(set) var mirrorReadCount = 0

  init(remainingDepth: Int) {
    self.remainingDepth = remainingDepth
  }

  var customMirror: Mirror {
    mirrorReadCount += 1
    guard remainingDepth > 0 else {
      return Mirror(self, children: [:], displayStyle: .struct)
    }
    remainingDepth -= 1
    return Mirror(self, children: ["recursive": self], displayStyle: .struct)
  }
}

@propertyWrapper
@MainActor
private struct DormantComposedCounter: DynamicProperty {
  @State private var value = 0

  var wrappedValue: Int { value }
  var projectedValue: Self { self }

  func increment() {
    value += 1
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    .unchanged
  }
}

@MainActor
private struct DormantTabsFixture: View {
  let model: DormantTabModel
  let probe: DormantTabProbe

  var body: some View {
    TabView(selection: model.selectionBinding) {
      if model.reversed {
        tabB
        if model.includesA { tabA }
      } else {
        if model.includesA { tabA }
        tabB
      }
    }
    .id(model.ownerGeneration)
  }

  private var tabA: some View {
    Tab("A", value: "A") {
      DormantCounterContent(tag: "A", probe: probe)
        .id("nested-exact-A")
    }
  }

  private var tabB: some View {
    Tab("B", value: "B") {
      DormantCounterContent(tag: "B", probe: probe)
        .id("nested-exact-B")
    }
  }
}

@MainActor
private struct DormantEditorFixture: View {
  @State private var selection = "A"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 1) {
        Button("Show editor") { selection = "A" }
          .id(testIdentity("DormantJourneyShowEditor"))
        Button("Show evidence") { selection = "B" }
          .id(testIdentity("DormantJourneyShowEvidence"))
      }
      TabView(selection: $selection) {
        Tab("Editor", value: "A") {
          DormantEditorContent()
        }
        Tab("Evidence", value: "B") {
          Text("Evidence")
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

@MainActor
private struct DormantEditorContent: View {
  @Environment(\.clipboardWriteAction) private var clipboardWriteAction
  @State private var pointerCount = 0
  @State private var editorText = "seed"
  @State private var clipboardStatus = "Clipboard: idle"
  @State private var pastedText = ""
  @FocusState private var editorFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      TextField("Journey editor", text: $editorText)
        .focused($editorFocused)
        .defaultFocus($editorFocused)
        .id(testIdentity("DormantJourneyEditor"))
      Button("Pointer count \(pointerCount)") {
        pointerCount += 1
      }
      .id(testIdentity("DormantJourneyPointer"))
      Button("Copy journey token") {
        clipboardStatus =
          clipboardWriteAction("token")
          ? "Clipboard: copied" : "Clipboard: unavailable"
      }
      Text(clipboardStatus)
      TextField("Paste verifier", text: $pastedText)
      Text("Editor state \(editorText)")
    }
  }
}

@MainActor
private struct DormantPayloadOwnerFixture: View {
  let model: DormantPayloadOwnerModel

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") {
        DormantPayloadOwnerContent(tag: "A", initialValue: 1)
      }
      Tab("B", value: "B") {
        DormantPayloadOwnerContent(tag: "B", initialValue: 2)
      }
    }
  }
}

@MainActor
private struct NestedDormantTabsFixture: View {
  let outerModel: DormantTabModel
  let innerModel: DormantTabModel
  let probe: DormantTabProbe

  var body: some View {
    TabView(selection: outerModel.selectionBinding) {
      Tab("outer-A", value: "A") {
        TabView(selection: innerModel.selectionBinding) {
          Tab("inner-A", value: "A") {
            DormantCounterContent(tag: "inner-A", probe: probe)
          }
          Tab("inner-B", value: "B") {
            DormantCounterContent(tag: "inner-B", probe: probe)
          }
        }
      }
      Tab("outer-B", value: "B") {
        Text("outer-B")
      }
    }
  }
}

@MainActor
private struct DormantPayloadOwnerContent: View {
  let tag: String
  @State private var value: Int

  init(tag: String, initialValue: Int) {
    self.tag = tag
    _value = State(initialValue: initialValue)
  }

  var body: some View {
    Text("\(tag) owner \(value)")
  }
}

@MainActor
private struct DormantCounterContent: View {
  let tag: String
  let probe: DormantTabProbe
  @DormantComposedCounter private var count: Int

  var body: some View {
    probe.evaluated(tag)
    return VStack(alignment: .leading, spacing: 1) {
      Text("\(tag) count \(count)")
      Button("Increment \(tag)") { [$count] in
        $count.increment()
      }
      .id(testIdentity("DormantIncrement-\(tag)"))
    }
  }
}

@MainActor
private final class DormantTailWriteBindingProbe {
  var binding: Binding<Int>?
}

@MainActor
private struct DormantTailWriteFixture: View {
  let model: DormantTabModel
  let bindingProbe: DormantTailWriteBindingProbe
  var label = "A"

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") {
        DormantTailWriteContent(label: label, bindingProbe: bindingProbe)
      }
      Tab("B", value: "B") {
        Text("\(label) B")
      }
    }
  }
}

@MainActor
private struct DormantTailWriteContent: View {
  let label: String
  let bindingProbe: DormantTailWriteBindingProbe
  @State private var value = 0

  var body: some View {
    bindingProbe.binding = $value
    return Text("\(label) count \(value)")
  }
}

@MainActor
private struct DormantDualTailWriteFixture: View {
  let leftModel: DormantTabModel
  let rightModel: DormantTabModel
  let leftProbe: DormantTailWriteBindingProbe
  let rightProbe: DormantTailWriteBindingProbe

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DormantTailWriteFixture(
        model: leftModel,
        bindingProbe: leftProbe,
        label: "left"
      )
      .id("left-tabs")
      DormantTailWriteFixture(
        model: rightModel,
        bindingProbe: rightProbe,
        label: "right"
      )
      .id("right-tabs")
    }
  }
}

@MainActor
private struct DormantFocusGestureFixture: View {
  let model: DormantTabModel

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") { DormantFocusGestureContent() }
      Tab("B", value: "B") { Text("plain-B") }
    }
  }
}

@MainActor
private struct DormantFocusGestureContent: View {
  @FocusState private var focused: Bool
  @GestureState private var gestureValue = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("focus \(focused) gesture \(gestureValue)")
        .gesture(
          DragGesture().updating($gestureValue) { _, value, _ in
            value = 1
          }
        )
      Button("Toggle focus") { focused.toggle() }
        .id(testIdentity("DormantFocusToggle"))
    }
  }
}

@MainActor
private struct DormantNavigationFixture: View {
  let model: DormantTabModel
  let lifecycleProbe: DormantLifecycleProbe

  var body: some View {
    TabView(selection: model.selectionBinding) {
      Tab("A", value: "A") {
        DormantNavigationContent(lifecycleProbe: lifecycleProbe)
      }
      Tab("B", value: "B") { Text("plain-B") }
    }
  }
}

@MainActor
private struct DormantNavigationContent: View {
  let lifecycleProbe: DormantLifecycleProbe
  @State private var presentsDetail = true

  var body: some View {
    NavigationStack {
      Text("root-A")
        .navigationDestination(isPresented: $presentsDetail) {
          Text("detail-A")
            .onAppear { lifecycleProbe.appears += 1 }
            .onDisappear { lifecycleProbe.disappears += 1 }
        }
    }
  }
}

@MainActor
private func dormantContext(
  root: Identity,
  actions: LocalActionRegistry,
  keys: LocalKeyHandlerRegistry? = nil,
  focusedIdentity: Identity? = nil,
  gestures: LocalGestureRegistry? = nil,
  gestureStates: LocalGestureStateRegistry? = nil
) -> ResolveContext {
  var context = ResolveContext(
    identity: root,
    localActionRegistry: actions,
    localKeyHandlerRegistry: keys,
    applyEnvironmentValues: true
  )
  context.environmentValues.focusedIdentity = focusedIdentity
  context.localGestureRegistry = gestures
  context.localGestureStateRegistry = gestureStates
  return context
}

private func surfaceText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private struct DormantIdentifiedRow: Identifiable, Equatable {
  var id: UUID
  var title: String
  var done: Bool
}

private struct DormantTextEditorFixture: View {
  @State private var selection = "A"
  @State private var text = "editor seed"

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 1) {
        Button("Show editor") { selection = "A" }
          .id(testIdentity("DormantTextEditorShowEditor"))
        Button("Show other") { selection = "B" }
          .id(testIdentity("DormantTextEditorShowOther"))
      }
      TabView(selection: $selection) {
        Tab("Editor", value: "A") {
          TextEditor(text: $text)
            .frame(width: 24, height: 3)
        }
        Tab("Other", value: "B") {
          Text("Other")
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}
