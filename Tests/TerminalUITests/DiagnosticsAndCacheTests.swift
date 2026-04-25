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

private final class BranchResolveRecorder: Sendable {
  private let identitiesStorage = LockedBox<[Identity]>([])

  var identities: [Identity] {
    identitiesStorage.value
  }

  func record(_ identity: Identity) {
    identitiesStorage.withLock {
      $0.append(identity)
    }
  }

  func reset() {
    identitiesStorage.withLock {
      $0.removeAll(keepingCapacity: true)
    }
  }
}

private final class ResolveProbeRecorder: Sendable {
  private let recordsStorage = LockedBox<[ResolveProbeRecord]>([])

  var records: [ResolveProbeRecord] {
    recordsStorage.value
  }

  func record(_ record: ResolveProbeRecord) {
    recordsStorage.withLock {
      $0.append(record)
    }
  }
}

@MainActor
private func resolvedProbeTextNode(
  _ content: String,
  in context: ResolveContext
) -> ResolvedNode {
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

  @Test("default renderer reuses measurement and placement work across ScrollView position changes")
  func defaultRendererReusesMeasurementsAcrossScrollPositionChanges() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let box = LockedBox(ScrollPosition.zero)

    func makeView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
          Text("Row 4")
          Text("Row 5")
          Text("Row 6")
          Text("Row 7")
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    let first = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )

    box.withLock {
      $0.scrollBy(y: 1)
    }

    let second = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )

    #expect(second.diagnostics.measuredNodesComputed == 0)
    #expect(second.diagnostics.measuredNodesReused > 0)
    #expect(second.diagnostics.placedNodesComputed < first.diagnostics.placedNodesComputed)
    #expect(second.diagnostics.placedNodesReused > 0)
  }

  @Test("retained placement respects ScrollView position changes")
  func retainedPlacementRespectsScrollViewPositionChanges() {
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let box = LockedBox(ScrollPosition.zero)

    func makeView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { box.value },
          set: { box.value = $0 }
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
      .id(testIdentity("Scrollable"))
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    _ = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )

    box.withLock {
      $0.scrollBy(y: 1)
    }

    let second = renderer.render(
      makeView(),
      context: .init(identity: testIdentity("Root"))
    )
    let rendered = second.rasterSurface.lines.joined(separator: "\n")

    #expect(rendered.contains("Row 1"))
    #expect(rendered.contains("Row 2"))
    #expect(rendered.contains("Row 3"))
    #expect(!rendered.contains("Row 0"))
  }

  @Test("lazy stacks reduce placement work across scroll position changes")
  func lazyStacksReducePlacementWorkAcrossScrollPositionChanges() {
    let eagerRenderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let lazyRenderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let eagerBox = LockedBox(ScrollPosition.zero)
    let lazyBox = LockedBox(ScrollPosition.zero)

    func makeEagerView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { eagerBox.value },
          set: { eagerBox.value = $0 }
        )
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
          Text("Row 4")
          Text("Row 5")
          Text("Row 6")
          Text("Row 7")
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    func makeLazyView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { lazyBox.value },
          set: { lazyBox.value = $0 }
        )
      ) {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
          Text("Row 4")
          Text("Row 5")
          Text("Row 6")
          Text("Row 7")
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    _ = eagerRenderer.render(
      makeEagerView(),
      context: .init(identity: testIdentity("EagerRoot"))
    )
    _ = lazyRenderer.render(
      makeLazyView(),
      context: .init(identity: testIdentity("LazyRoot"))
    )

    eagerBox.withLock { $0.scrollBy(y: 1) }
    lazyBox.withLock { $0.scrollBy(y: 1) }

    let eagerSecond = eagerRenderer.render(
      makeEagerView(),
      context: .init(identity: testIdentity("EagerRoot"))
    )
    let lazySecond = lazyRenderer.render(
      makeLazyView(),
      context: .init(identity: testIdentity("LazyRoot"))
    )

    #expect(eagerSecond.diagnostics.measuredNodesComputed == 0)
    #expect(lazySecond.diagnostics.measuredNodesComputed == 0)
    #expect(lazySecond.diagnostics.measuredNodesReused > 0)
    #expect(eagerSecond.diagnostics.placedNodesReused > 0)
    #expect(lazySecond.diagnostics.placedNodeCount < eagerSecond.diagnostics.placedNodeCount)
  }

  @Test("single-ForEach lazy stacks lower off-screen resolution and measurement work on scroll")
  func singleForEachLazyStacksLowerOffScreenWorkOnScroll() {
    let stableRenderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let lazyRenderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )
    let stableBox = LockedBox(ScrollPosition.zero)
    let lazyBox = LockedBox(ScrollPosition.zero)

    func makeStableView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { stableBox.value },
          set: { stableBox.value = $0 }
        )
      ) {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("Row 0")
          Text("Row 1")
          Text("Row 2")
          Text("Row 3")
          Text("Row 4")
          Text("Row 5")
          Text("Row 6")
          Text("Row 7")
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    func makeLazyView() -> some View {
      ScrollView(
        .vertical,
        position: Binding(
          get: { lazyBox.value },
          set: { lazyBox.value = $0 }
        )
      ) {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(0..<8) { index in
            Text("Row \(index)")
          }
        }
      }
      .frame(width: 12, height: 3, alignment: .topLeading)
    }

    _ = stableRenderer.render(
      makeStableView(),
      context: .init(identity: testIdentity("StableRoot"))
    )
    _ = lazyRenderer.render(
      makeLazyView(),
      context: .init(identity: testIdentity("LazyRoot"))
    )

    stableBox.withLock { $0.scrollBy(y: 1) }
    lazyBox.withLock { $0.scrollBy(y: 1) }

    let stableSecond = stableRenderer.render(
      makeStableView(),
      context: .init(identity: testIdentity("StableRoot"))
    )
    let lazySecond = lazyRenderer.render(
      makeLazyView(),
      context: .init(identity: testIdentity("LazyRoot"))
    )

    #expect(lazySecond.diagnostics.resolvedNodeCount < stableSecond.diagnostics.resolvedNodeCount)
    #expect(lazySecond.diagnostics.measuredNodeCount < stableSecond.diagnostics.measuredNodeCount)
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
    // Of the 5 lookups, 2 found a cached entry that failed
    // `isEquivalentForMeasurement` (the invalidated Text subtree and its
    // VStack ancestor whose content recursively changed) and are now
    // reported as invalidations rather than misses.  The remaining 3 are
    // true cold misses.
    #expect(secondMetrics.misses == 3)
    #expect(secondMetrics.invalidations == 2)
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

  @Test("selective dirty frames preserve local action and key handlers on reused controls")
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

    _ = renderer.render(
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

    #expect(dispatched)
    #expect(box.value == 1)
    #expect(keyRegistry.dispatch(identity: testIdentity("CountStepper"), event: .arrowRight))
    #expect(box.value == 2)
  }

  @Test("selective dirty frames preserve focused value publishers on reused controls")
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

    var updatedContext = ResolveContext(
      identity: testIdentity("Root"),
      environmentValues: environmentValues,
      invalidatedIdentities: [testIdentity("Root", "VStack[1]")]
    )
    updatedContext.localFocusedValuesRegistry = focusedValuesRegistry

    _ = renderer.render(
      makeRoot(secondLine: "Planet!"),
      context: updatedContext
    )

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

    #expect(
      recorder.identities == [
        testIdentity("Root", "Branches[1]")
      ]
    )
    #expect(updated.diagnostics.resolvedNodesComputed == 4)
    #expect(updated.diagnostics.resolvedNodesReused == 1)
  }

  @Test("draw-only style changes reuse measurement and placement work")
  func drawOnlyStyleChangesReuseLayoutWork() {
    let box = LockedBox(false)
    let renderer = DefaultRenderer(
      layoutEngine: .init(cache: MeasurementCache())
    )

    func makeRoot() -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text("Stable")
        Text("Accent")
          .foregroundStyle(
            box.value
              ? AnyShapeStyle(.success)
              : AnyShapeStyle(.muted)
          )
      }
    }

    let first = renderer.render(
      makeRoot(),
      context: .init(identity: testIdentity("Root"))
    )

    box.value = true

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
    let box = LockedBox("Accent")
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
    #expect(inserted.rasterSurface.lines.joined(separator: "\n").contains("Extra"))
    #expect(removed.measuredTree.measuredSize == .init(width: 6, height: 1))
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
