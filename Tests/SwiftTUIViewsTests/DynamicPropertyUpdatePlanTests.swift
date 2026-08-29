import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Plan-tier pins for the dynamic-property update pass's offset plans: struct
// containers with statically wrapper-typed fields take the offset tier;
// shapes the static field metadata cannot prove (existential-typed fields,
// enum containers) keep the per-instance `Mirror` walk with identical
// discovery semantics. A class container is neither tier — it violates the
// value-type authoring invariant and traps. Behavioral equivalence of the two extraction
// mechanisms is pinned here via update(in:) event logs; the pass's ordering,
// nesting, and slot-identity contracts stay pinned by
// `DynamicPropertyUpdatePassTests`.
@MainActor
private final class PlanEventLog {
  private(set) var events: [String] = []

  func append(_ event: String) {
    events.append(event)
  }
}

@propertyWrapper
@MainActor
private struct PlanRecorder: DynamicProperty {
  private let log: PlanEventLog
  private let tag: String
  private let result: DynamicPropertyUpdateResult

  init(
    log: PlanEventLog,
    tag: String,
    result: DynamicPropertyUpdateResult = .unchanged
  ) {
    self.log = log
    self.tag = tag
    self.result = result
  }

  func update(in context: DynamicPropertyContext) -> DynamicPropertyUpdateResult {
    log.append("update:\(tag)")
    return result
  }

  var wrappedValue: String {
    tag
  }
}

/// Statically wrapper-typed fields interleaved with plain storage — the
/// universal authored shape, which must take the offset tier.
@MainActor
private struct StaticallyTypedContainer {
  var leadingPlain: Int = 0
  @PlanRecorder var first: String
  var middlePlain: String = "middle"
  @PlanRecorder var second: String

  init(log: PlanEventLog) {
    _first = PlanRecorder(log: log, tag: "first")
    _second = PlanRecorder(log: log, tag: "second")
  }
}

/// A wrapper boxed behind `Any`: `Mirror` discovers the conforming value but
/// the static field type proves nothing — the type must keep the walk.
@MainActor
private struct ExistentiallyTypedContainer {
  var boxed: Any

  init(log: PlanEventLog) {
    boxed = PlanRecorder(log: log, tag: "boxed")
  }
}

@MainActor
private struct PlainFirstExistentialContainer {
  var boxed: Any
}

@MainActor
private struct DynamicFirstExistentialContainer {
  var boxed: Any
}

@MainActor
private enum EnumContainer {
  case bare
  case carrying(PlanRecorder)
}

private struct PlainContainer {
  var value = 7
}

@MainActor
private struct UncertifiedProperty: DynamicProperty {}

@MainActor
private struct UncertifiedContainer {
  var property = UncertifiedProperty()
}

@MainActor
private struct ChangedContainer {
  var property: PlanRecorder

  init(log: PlanEventLog) {
    property = PlanRecorder(log: log, tag: "changed", result: .changed)
  }
}

@MainActor
struct DynamicPropertyUpdatePlanTests {
  @Test("statically wrapper-typed struct fields take the offset tier")
  func staticallyTypedStructGetsOffsetPlan() {
    let log = PlanEventLog()
    let container = StaticallyTypedContainer(log: log)
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: container) == .offsets
    )
  }

  @Test("offset extraction updates every discovered field in declaration order")
  func offsetExtractionMatchesMirrorDiscovery() {
    let log = PlanEventLog()
    let container = StaticallyTypedContainer(log: log)
    runDynamicPropertyUpdatePass(on: container)
    #expect(log.events == ["update:first", "update:second"])
  }

  @Test("an existential-typed field boxing a wrapper keeps the Mirror walk")
  func existentialFieldFallsBackToMirrorWalk() {
    let log = PlanEventLog()
    let container = ExistentiallyTypedContainer(log: log)
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: container) == .mirrorWalk
    )
    runDynamicPropertyUpdatePass(on: container)
    #expect(log.events == ["update:boxed"], "the fallback walk must still update the boxed wrapper")
  }

  @Test("a plain-first existential field discovers a later DynamicProperty value")
  func plainFirstExistentialDoesNotCacheAnEmptyPlan() {
    let log = PlanEventLog()

    runDynamicPropertyUpdatePass(
      on: PlainFirstExistentialContainer(boxed: "plain")
    )
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(
        reflecting: PlainFirstExistentialContainer(boxed: "plain")
      ) == .mirrorWalk
    )
    runDynamicPropertyUpdatePass(
      on: PlainFirstExistentialContainer(
        boxed: PlanRecorder(log: log, tag: "plain-first-dynamic")
      )
    )

    #expect(log.events == ["update:plain-first-dynamic"])
    #expect(
      DynamicPropertyDescriptorCache.hasCachedPlan(
        for: PlainFirstExistentialContainer.self
      )
    )
  }

  @Test("a dynamic-first existential plan tolerates plain values and updates later wrappers")
  func dynamicFirstExistentialPlanRemainsValueConditional() {
    let log = PlanEventLog()

    runDynamicPropertyUpdatePass(
      on: DynamicFirstExistentialContainer(
        boxed: PlanRecorder(log: log, tag: "dynamic-first")
      )
    )
    runDynamicPropertyUpdatePass(
      on: DynamicFirstExistentialContainer(boxed: 17)
    )
    runDynamicPropertyUpdatePass(
      on: DynamicFirstExistentialContainer(
        boxed: PlanRecorder(log: log, tag: "dynamic-again")
      )
    )

    #expect(log.events == ["update:dynamic-first", "update:dynamic-again"])
  }

  @Test("a class container traps: authored containers are value types")
  func classContainerTrapsOnPlanBuild() async {
    // Unreachable from Swift source since plan 2026-08-29-001 — `View`,
    // `ViewModifier`, the style protocols, `DynamicProperty`, `Scene`, and
    // `App` all reject class conformers at compile time — so the fixture
    // conforms to nothing and reaches the cold builder directly. This is the
    // runtime floor beneath the compile-time contract, not a second contract.
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        @MainActor final class ClassContainer {
          @State var value = "seed"
        }
        _ = DynamicPropertyDescriptorCache.diagnosticPlanKind(
          reflecting: ClassContainer()
        )
      }
    }
  }

  @Test("enum containers are classified per value and never cached")
  func enumContainersAreNeverCached() {
    let log = PlanEventLog()
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: EnumContainer.bare) == .empty
    )
    let carrying = EnumContainer.carrying(PlanRecorder(log: log, tag: "payload"))
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: carrying) == .mirrorWalk
    )
    #expect(!DynamicPropertyDescriptorCache.hasCachedPlan(for: EnumContainer.self))
  }

  @Test("wrapper-free types get the empty plan")
  func wrapperFreeTypeGetsEmptyPlan() {
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: PlainContainer()) == .empty
    )
    #expect(DynamicPropertyDescriptorCache.hasCachedPlan(for: PlainContainer.self))
  }

  @Test("update results aggregate conservatively")
  func updateResultsAggregateConservatively() {
    let log = PlanEventLog()
    #expect(runDynamicPropertyUpdatePass(on: ChangedContainer(log: log)) == .changed)
    #expect(runDynamicPropertyUpdatePass(on: UncertifiedContainer()) == .uncertified)
  }
}
