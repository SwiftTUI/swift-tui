import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// Plan-tier pins for the dynamic-property update pass's offset plans: struct
// containers with statically wrapper-typed fields take the offset tier;
// shapes the static field metadata cannot prove (existential-typed fields,
// class and enum containers) keep the per-instance `Mirror` walk with
// identical discovery semantics. Behavioral equivalence of the two extraction
// mechanisms is pinned here via update() event logs; the pass's ordering,
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

  init(log: PlanEventLog, tag: String) {
    self.log = log
    self.tag = tag
  }

  mutating func update() {
    log.append("update:\(tag)")
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
private final class ClassContainer {
  @PlanRecorder var stored: String

  init(log: PlanEventLog) {
    _stored = PlanRecorder(log: log, tag: "class-stored")
  }
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

  @Test("a class container keeps the Mirror walk and still updates")
  func classContainerFallsBackToMirrorWalk() {
    let log = PlanEventLog()
    let container = ClassContainer(log: log)
    #expect(
      DynamicPropertyDescriptorCache.diagnosticPlanKind(reflecting: container) == .mirrorWalk
    )
    runDynamicPropertyUpdatePass(on: container)
    #expect(log.events == ["update:class-stored"])
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
}
