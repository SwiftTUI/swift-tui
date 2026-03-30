import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

private enum FocusedReuseKey: FocusedValueKey {
  typealias Value = String
}

private enum FocusedReuseGroupKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var focusedReuseValue: String? {
    get { self[FocusedReuseKey.self] }
    set { self[FocusedReuseKey.self] = newValue }
  }

  fileprivate var focusedReuseGroup: String? {
    get { self[FocusedReuseGroupKey.self] }
    set { self[FocusedReuseGroupKey.self] = newValue }
  }
}

private struct ResolveProbeRecord: Equatable {
  let identity: Identity
  let invalidatedIdentities: Set<Identity>
  let isSelfInvalidated: Bool
  let subtreeAffected: Bool
  let unrelatedSubtreeAffected: Bool
}

private final class BranchResolveRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var identities: [Identity] = []

  func record(_ identity: Identity) {
    lock.lock()
    defer { lock.unlock() }
    identities.append(identity)
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    identities.removeAll(keepingCapacity: true)
  }
}

private final class ResolveProbeRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var records: [ResolveProbeRecord] = []

  func record(_ record: ResolveProbeRecord) {
    lock.lock()
    defer { lock.unlock() }
    records.append(record)
  }
}

@MainActor
private func resolvedProbeTextNode(
  _ content: String,
  in context: ResolveContext
) -> ResolvedNode {
  if let reused = context.reusedResolvedSubtreeIfAvailable() {
    return reused
  }
  context.recordResolvedComputation()
  return ResolvedNode(
    identity: context.identity,
    kind: .view("Text"),
    environmentSnapshot: context.environment,
    transactionSnapshot: context.transaction,
    drawPayload: .text(content)
  )
}

private struct ResolveProbeLeaf: View, ResolvableView {
  let recorder: ResolveProbeRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    recorder.record(
      ResolveProbeRecord(
        identity: context.identity,
        invalidatedIdentities: context.invalidatedIdentities,
        isSelfInvalidated: context.isInvalidated(context.identity),
        subtreeAffected: context.invalidationAffectsSubtree(),
        unrelatedSubtreeAffected: context.invalidationAffectsSubtree(
          at: (context.identity.parent ?? context.identity).child("Elsewhere")
        )
      )
    )
    return [resolvedProbeTextNode("Probe", in: context)]
  }
}

private struct RecordingBranchLeaf: View, ResolvableView {
  let label: String
  let recorder: BranchResolveRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    recorder.record(context.identity)
    context.recordResolvedComputation()
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Text"),
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        drawPayload: .text(label)
      )
    ]
  }
}

private struct RecordingBranchRoot: View, ResolvableView {
  let labels: [String]
  let recorder: BranchResolveRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    context.recordResolvedComputation()
    let children = labels.enumerated().map { index, label in
      resolveView(
        RecordingBranchLeaf(label: label, recorder: recorder),
        in: context.indexedChild(kind: .named("Branches"), index: index)
      )
    }
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("Branches"),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

private struct ResolveProbeRoot: View, ResolvableView {
  let recorder: ResolveProbeRecorder

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    if let reused = context.reusedResolvedSubtreeIfAvailable() {
      return [reused]
    }
    context.recordResolvedComputation()
    recorder.record(
      ResolveProbeRecord(
        identity: context.identity,
        invalidatedIdentities: context.invalidatedIdentities,
        isSelfInvalidated: context.isInvalidated(context.identity),
        subtreeAffected: context.invalidationAffectsSubtree(),
        unrelatedSubtreeAffected: context.invalidationAffectsSubtree(
          at: (context.identity.parent ?? context.identity).child("Elsewhere")
        )
      )
    )

    let child = resolveView(
      ResolveProbeLeaf(recorder: recorder),
      in: context.indexedChild(kind: .named("ProbeRoot"), index: 0)
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ProbeRoot"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}

@MainActor
@Suite
struct DiagnosticsAndCacheTests {
  @Test("measurement cache reuses entries for repeated probes with the same proposal")
  func measurementCacheReusesEntries() {
    let root = VStack(alignment: .leading, spacing: 1) {
      Text("Hello")
      Text("World")
    }
    let resolved = root.resolve(in: .init(identity: testIdentity("Root")))
    let cache = MeasurementCache()
    let engine = LayoutEngine(cache: cache)

    let first = engine.measure(resolved, proposal: .unspecified)
    let countAfterFirst = cache.count
    let second = engine.measure(resolved, proposal: .unspecified)
    let countAfterSecond = cache.count
    let third = engine.measure(resolved, proposal: .init(width: 4, height: nil))
    let countAfterThird = cache.count
    let metrics = cache.metrics

    #expect(first == second)
    #expect(countAfterFirst == 3)
    #expect(countAfterSecond == countAfterFirst)
    #expect(third.measuredSize.width == 4)
    #expect(countAfterThird == 6)
    #expect(metrics.generation == 0)
    #expect(metrics.entries == 6)
    #expect(metrics.lookups == 7)
    #expect(metrics.hits == 1)
    #expect(metrics.misses == 6)
    #expect(metrics.stores == 6)
  }

  @Test("measurement cache reset advances generation and clears per-epoch counters")
  func measurementCacheResetClearsMetrics() {
    let cache = MeasurementCache()
    let resolved = Text("Hello").resolve(in: .init(identity: testIdentity("Root")))
    let engine = LayoutEngine(cache: cache)

    _ = engine.measure(resolved, proposal: .unspecified)
    cache.reset()
    let metrics = cache.metrics

    #expect(metrics.generation == 1)
    #expect(metrics.entries == 0)
    #expect(metrics.lookups == 0)
    #expect(metrics.hits == 0)
    #expect(metrics.misses == 0)
    #expect(metrics.stores == 0)
  }

  @Test("default renderer reuses compatible measurements across repeated frames")
  func defaultRendererReusesCompatibleMeasurementsAcrossFrames() throws {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let root = VStack(alignment: .leading, spacing: 1) {
      Text("Hello")
      Text("World")
    }

    let first = renderer.render(root, context: .init(identity: testIdentity("Root")))
    let second = renderer.render(root, context: .init(identity: testIdentity("Root")))
    let firstMetrics = try #require(first.diagnostics.measurementCache)
    let secondMetrics = try #require(second.diagnostics.measurementCache)

    #expect(firstMetrics.generation == 0)
    #expect(firstMetrics.entries == 3)
    #expect(firstMetrics.lookups == 3)
    #expect(firstMetrics.hits == 0)
    #expect(firstMetrics.misses == 3)
    #expect(firstMetrics.stores == 3)
    #expect(first.diagnostics.measuredNodesComputed == 3)
    #expect(first.diagnostics.measuredNodesReused == 0)
    #expect(first.diagnostics.placedNodesComputed == 3)
    #expect(first.diagnostics.placedNodesReused == 0)

    #expect(secondMetrics.generation == 0)
    #expect(secondMetrics.entries == 3)
    #expect(secondMetrics.lookups == 3)
    #expect(secondMetrics.hits == 0)
    #expect(secondMetrics.misses == 3)
    #expect(secondMetrics.stores == 3)
    #expect(second.measuredTree == first.measuredTree)
    #expect(second.placedTree == first.placedTree)
    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.measuredNodesReused == 3)
    #expect(second.diagnostics.placedNodesComputed == 0)
    #expect(second.diagnostics.placedNodesReused == 3)
  }

  @Test("default renderer recomputes layout when the proposal changes across frames")
  func defaultRendererRecomputesLayoutOnProposalChange() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let view = Text("abcdef")

    let first = renderer.render(
      view,
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 6, height: nil)
    )
    let second = renderer.render(
      view,
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 3, height: nil)
    )

    #expect(first.measuredTree.measuredSize == .init(width: 6, height: 1))
    #expect(second.measuredTree.measuredSize == .init(width: 3, height: 4))
    #expect(second.diagnostics.measuredNodesComputed == second.diagnostics.measuredNodeCount)
    #expect(second.diagnostics.measuredNodesReused == 0)
    #expect(second.diagnostics.placedNodesComputed == second.diagnostics.placedNodeCount)
    #expect(second.diagnostics.placedNodesReused == 0)
  }

  @Test(
    "default renderer recomputes layout when environment-driven scroll indicator visibility changes"
  )
  func defaultRendererRecomputesLayoutOnEnvironmentDrivenLayoutChange() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let view = ScrollView(.horizontal) {
      Text("abcdef")
    }

    var visibleEnvironment = EnvironmentValues()
    visibleEnvironment.scrollIndicatorVisibility = .visible

    var hiddenEnvironment = EnvironmentValues()
    hiddenEnvironment.scrollIndicatorVisibility = .hidden

    let first = renderer.render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: visibleEnvironment
      ),
      proposal: .init(width: 4, height: nil)
    )
    let second = renderer.render(
      view,
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: hiddenEnvironment
      ),
      proposal: .init(width: 4, height: nil)
    )

    #expect(first.measuredTree.measuredSize == .init(width: 4, height: 2))
    #expect(second.measuredTree.measuredSize == .init(width: 4, height: 1))
    #expect(second.diagnostics.measuredNodesComputed > 0)
    #expect(second.diagnostics.placedNodesComputed > 0)
  }

  @Test("default renderer reuses measurements across ScrollView position changes")
  func defaultRendererReusesMeasurementsAcrossScrollPositionChanges() {
    final class ScrollPositionBox: @unchecked Sendable {
      var position = ScrollPosition.zero
    }

    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let box = ScrollPositionBox()

    func makeView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.position },
          set: { box.position = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
          Text("Row 4")
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    let first = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )

    box.position.scrollBy(y: 1)

    let second = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.measuredNodesReused == second.diagnostics.measuredNodeCount)
    #expect(second.diagnostics.placedNodesComputed == first.diagnostics.placedNodesComputed)
    #expect(second.diagnostics.placedNodesReused == 0)
  }

  @Test("default renderer invalidates changed subtrees even when identities stay stable")
  func defaultRendererInvalidatesChangedSubtrees() throws {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot(secondLine: String) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Hello")
        Text(secondLine)
      }
    }

    let first = renderer.render(
      makeRoot(secondLine: "World"),
      context: .init(identity: testIdentity("Root"))
    )
    let second = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
      )
    )
    let secondMetrics = try #require(second.diagnostics.measurementCache)

    #expect(first.measuredTree.measuredSize == .init(width: 5, height: 3))
    #expect(second.measuredTree.measuredSize == .init(width: 7, height: 3))
    #expect(secondMetrics.generation == 0)
    #expect(secondMetrics.entries == 3)
    #expect(secondMetrics.lookups == 5)
    #expect(secondMetrics.hits == 0)
    #expect(secondMetrics.misses == 5)
    #expect(secondMetrics.stores == 5)
    #expect(second.diagnostics.invalidatedIdentities == [testIdentity("Root", "VStack[1]")])
    #expect(second.diagnostics.resolvedNodesComputed == 2)
    #expect(second.diagnostics.resolvedNodesReused == 1)
    #expect(second.diagnostics.measuredNodesComputed == 2)
    #expect(second.diagnostics.measuredNodesReused == 1)
    #expect(second.diagnostics.placedNodesComputed == 2)
    #expect(second.diagnostics.placedNodesReused == 1)
  }

  @Test("default renderer reuses clean siblings when a dirty subtree is invalidated")
  func defaultRendererReusesCleanSiblingsWithinDirtyFrames() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot(secondLine: String) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable")
        Text(secondLine)
      }
    }

    _ = renderer.render(
      makeRoot(secondLine: "World"),
      context: .init(identity: testIdentity("Root"))
    )
    let updated = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
      )
    )

    #expect(updated.measuredTree.childMeasurements[0].measuredSize == .init(width: 6, height: 1))
    #expect(updated.measuredTree.childMeasurements[1].measuredSize == .init(width: 7, height: 1))
    #expect(updated.diagnostics.resolvedNodesComputed == 2)
    #expect(updated.diagnostics.resolvedNodesReused == 1)
    #expect(updated.diagnostics.measuredNodesComputed == 2)
    #expect(updated.diagnostics.measuredNodesReused == 1)
    #expect(updated.diagnostics.placedNodesComputed == 2)
    #expect(updated.diagnostics.placedNodesReused == 1)
  }

  @Test("resolve reuse replays local action and key handlers for reused controls")
  func resolveReuseReplaysLocalHandlers() {
    final class ValueBox {
      var value = 0
    }

    let box = ValueBox()
    let actionRegistry = LocalActionRegistry()
    let keyRegistry = LocalKeyHandlerRegistry()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot(secondLine: String) -> some View {
      VStack(spacing: 1) {
        Stepper(
          "Count",
          value: Binding(
            get: { box.value },
            set: { box.value = $0 }
          ),
          in: 0...3
        )
        .id(testIdentity("CountStepper"))
        Text(secondLine)
      }
    }

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("CountStepper")

    _ = renderer.render(
      makeRoot(secondLine: "World"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    actionRegistry.reset()
    keyRegistry.reset()

    let updated = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")],
        localActionRegistry: actionRegistry,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      )
    )

    let dispatched = actionRegistry.dispatch(identity: testIdentity("CountStepper"))

    #expect(updated.diagnostics.resolvedNodesReused > 0)
    #expect(dispatched)
    #expect(box.value == 1)
    #expect(keyRegistry.dispatch(identity: testIdentity("CountStepper"), event: .arrowRight))
    #expect(box.value == 2)
  }

  @Test("resolve reuse replays focused value publishers for reused controls")
  func resolveReuseReplaysFocusedValuePublishers() {
    let focusedValuesRegistry = LocalFocusedValuesRegistry()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot(secondLine: String) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Button("Stable") {}
          .id(testIdentity("FocusedReuseButton"))
          .focusedValue(\.focusedReuseValue, "Stable")
        Text(secondLine)
      }
    }

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("FocusedReuseButton")
    environmentValues.focusedValues = .init()

    var initialContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues
    )
    initialContext.localFocusedValuesRegistry = focusedValuesRegistry

    _ = renderer.render(
      makeRoot(secondLine: "World"),
      context: initialContext
    )

    focusedValuesRegistry.reset()

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
    )
    updatedContext.localFocusedValuesRegistry = focusedValuesRegistry

    let updated = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: updatedContext
    )

    #expect(updated.diagnostics.resolvedNodesReused > 0)
    #expect(
      focusedValuesRegistry.focusedValues(for: testIdentity("FocusedReuseButton")).focusedReuseValue
        == "Stable"
    )
  }

  @Test("focused value publishers on the same control merge into one focused value set")
  func focusedValuePublishersMergeForTheSameControl() {
    let focusedValuesRegistry = LocalFocusedValuesRegistry()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = testIdentity("FocusedMergeButton")

    var context = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues
    )
    context.localFocusedValuesRegistry = focusedValuesRegistry

    _ = renderer.render(
      Button("Merged") {}
        .id(testIdentity("FocusedMergeButton"))
        .focusedValue(\.focusedReuseValue, "Primary")
        .focusedValue(\.focusedReuseGroup, "Secondary"),
      context: context
    )

    let resolvedValues = focusedValuesRegistry.focusedValues(
      for: testIdentity("FocusedMergeButton"))
    #expect(resolvedValues.focusedReuseValue == "Primary")
    #expect(resolvedValues.focusedReuseGroup == "Secondary")
  }

  @Test("default renderer reuses clean resolved siblings when invalidation stays local")
  func defaultRendererReusesCleanResolvedSiblingsWithinDirtyFrames() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let recorder = BranchResolveRecorder()
    let root = RecordingBranchRoot(labels: ["Stable", "Dirty"], recorder: recorder)

    _ = renderer.render(
      root,
      context: .init(identity: testIdentity("Root"))
    )
    recorder.reset()

    let updated = renderer.render(
      root,
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "Branches[1]")]
      )
    )

    #expect(recorder.identities == [testIdentity("Root", "Branches[1]")])
    #expect(updated.diagnostics.resolvedNodesComputed == 4)
    #expect(updated.diagnostics.resolvedNodesReused == 1)
  }

  @Test("draw-only style changes reuse measurement and placement work")
  func drawOnlyStyleChangesReuseLayoutWork() {
    final class StyleBox: @unchecked Sendable {
      var highlighted = false
    }

    let box = StyleBox()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable")
        Text("Accent")
          .foregroundStyle(
            box.highlighted
              ? AnyShapeStyle(.success)
              : AnyShapeStyle(.muted)
          )
      }
    }

    let first = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("Root"))
    )

    box.highlighted = true

    let second = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(first.diagnostics.measuredNodesComputed > 0)
    #expect(second.diagnostics.resolvedNodesComputed > 0)
    #expect(second.diagnostics.resolvedNodesReused == 0)
    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.placedNodesComputed == 0)
    #expect(
      second.diagnostics.measuredNodesReused == second.diagnostics.measuredNodeCount
    )
    #expect(second.diagnostics.placedNodesReused == second.diagnostics.placedNodeCount)
  }

  @Test("text content changes still invalidate layout reuse")
  func textContentChangesStillInvalidateLayoutReuse() {
    final class TextBox: @unchecked Sendable {
      var value = "Accent"
    }

    let box = TextBox()
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable")
        Text(box.value)
      }
    }

    _ = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("Root"))
    )

    box.value = "Accent!"

    let second = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(second.diagnostics.resolvedNodesComputed > 0)
    #expect(second.diagnostics.measuredNodesComputed > 0)
    #expect(second.diagnostics.placedNodesComputed > 0)
    #expect(second.diagnostics.measuredNodesReused < second.diagnostics.measuredNodeCount)
    #expect(second.diagnostics.placedNodesReused < second.diagnostics.placedNodeCount)
  }

  @Test("default renderer handles structural insertions and removals without stale subtree reuse")
  func defaultRendererHandlesStructuralInsertionsAndRemovals() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot(showExtra: Bool) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Stable")
        if showExtra {
          Text("Extra")
        }
      }
    }

    _ = renderer.render(
      makeRoot(showExtra: false),
      context: .init(identity: testIdentity("Root"))
    )

    let inserted = renderer.render(
      makeRoot(showExtra: true),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
      )
    )
    let removed = renderer.render(
      makeRoot(showExtra: false),
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
      )
    )

    #expect(inserted.measuredTree.measuredSize == .init(width: 6, height: 2))
    #expect(inserted.diagnostics.resolvedNodesReused > 0)
    #expect(inserted.rasterSurface.lines.joined(separator: "\n").contains("Extra"))
    #expect(removed.measuredTree.measuredSize == .init(width: 6, height: 1))
    #expect(removed.diagnostics.resolvedNodesReused > 0)
    #expect(!removed.rasterSurface.lines.joined(separator: "\n").contains("Extra"))
  }

  @Test("resolve context carries invalidated identities and subtree dirty checks")
  func resolveContextCarriesInvalidatedIdentitiesAndSubtreeChecks() throws {
    let recorder = ResolveProbeRecorder()
    let rootIdentity = testIdentity("Root")
    let childIdentity = rootIdentity.child("ProbeRoot[0]")

    _ = DefaultRenderer().render(
      ResolveProbeRoot(recorder: recorder),
      context: .init(
        identity: rootIdentity,
        invalidatedIdentities: [childIdentity]
      )
    )

    let rootRecord = try #require(recorder.records.first { $0.identity == rootIdentity })
    let childRecord = try #require(recorder.records.first { $0.identity == childIdentity })

    #expect(rootRecord.invalidatedIdentities == [childIdentity])
    #expect(!rootRecord.isSelfInvalidated)
    #expect(rootRecord.subtreeAffected)
    #expect(!rootRecord.unrelatedSubtreeAffected)

    #expect(childRecord.invalidatedIdentities == [childIdentity])
    #expect(childRecord.isSelfInvalidated)
    #expect(childRecord.subtreeAffected)
    #expect(!childRecord.unrelatedSubtreeAffected)
  }

  @Test("snapshot renderer exposes resolved, placed, semantic, draw, and raster layers")
  func snapshotRendererExposesArchitectureLayers() {
    let root = VStack(alignment: .leading, spacing: 1) {
      Text("Hi")
      Text("Go").focusable()
    }
    let artifacts = DefaultRenderer().render(
      root,
      context: .init(
        identity: testIdentity("Root"),
        invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
      )
    )
    let snapshot = SnapshotRenderer().frameArtifacts(artifacts)

    #expect(snapshot.contains("[Resolved]"))
    #expect(snapshot.contains("Root kind=view(VStack) layout=stack(vertical,1,leading)"))
    #expect(snapshot.contains("Root/VStack[1] kind=view(Text)"))
    #expect(snapshot.contains("[Semantics]"))
    #expect(snapshot.contains("Root/VStack[1] rect=@(0,2) 2x1 route=Root/VStack[1]#primary"))
    #expect(snapshot.contains("[Raster]"))
    #expect(snapshot.contains("  Hi"))
    #expect(snapshot.contains("  Go"))
    #expect(snapshot.contains("[Diagnostics]"))
    #expect(snapshot.contains("invalidatedIdentities=Root/VStack[1]"))
    #expect(snapshot.contains("resolvedNodes=3"))
    #expect(snapshot.contains("resolvedWork=computed:4 reused:0"))
    #expect(snapshot.contains("measuredWork=computed:3 reused:0"))
    #expect(snapshot.contains("placedWork=computed:3 reused:0"))
    #expect(snapshot.contains("measurementCache=generation:0"))
  }

  @Test("snapshot renderer formats scheduled wake causes and invalidations")
  func snapshotRendererFormatsScheduledFrames() {
    let frame = ScheduledFrame(
      causes: [.invalidation, .signal, .deadline],
      invalidatedIdentities: [testIdentity("Root"), testIdentity("Root", "Button")],
      signalNames: ["SIGWINCH"],
      externalReasons: ["test"],
      triggeredDeadline: .init(offset: .seconds(10)),
      nextDeadline: nil
    )

    let snapshot = SnapshotRenderer().scheduledFrame(frame)

    #expect(snapshot.contains("causes=deadline,invalidation,signal"))
    #expect(snapshot.contains("invalidatedIdentities=Root,Root/Button"))
    #expect(snapshot.contains("signalNames=SIGWINCH"))
    #expect(snapshot.contains("externalReasons=test"))
    #expect(snapshot.contains("triggeredDeadline=10.000"))
    #expect(snapshot.contains("nextDeadline=nil"))
  }
}
