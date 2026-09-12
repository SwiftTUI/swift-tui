import SwiftTUICore

/// A typed child result and its explicit continuation. Scheduling never invokes
/// another work item inline: the driver owns every descent and resume step.
@MainActor
package struct ResolveWork<Value> {
  private let scope: ResolveContinuationScope
  private let start: (ResolveWorkDriver, @escaping @MainActor (Value) -> Void) -> Void

  private init(
    _ start:
      @escaping @MainActor (
        ResolveWorkDriver, @escaping @MainActor (Value) -> Void
      ) -> Void
  ) {
    scope = ResolveContinuationScope()
    self.start = start
  }

  package static func value(_ value: Value) -> Self {
    Self { _, complete in complete(value) }
  }

  package static func deferred(_ build: @escaping @MainActor () -> Self) -> Self {
    Self { driver, complete in build().enqueue(on: driver, complete: complete) }
  }

  package func map<Next>(
    _ transform: @escaping @MainActor (Value) -> Next
  ) -> ResolveWork<Next> {
    let continuationScope = ResolveContinuationScope()
    return ResolveWork<Next> { driver, complete in
      enqueue(on: driver) { value in
        driver.enqueue(scope: continuationScope) { complete(transform(value)) }
      }
    }
  }

  package func flatMap<Next>(
    _ transform: @escaping @MainActor (Value) -> ResolveWork<Next>
  ) -> ResolveWork<Next> {
    let continuationScope = ResolveContinuationScope()
    return ResolveWork<Next> { driver, complete in
      enqueue(on: driver) { value in
        driver.enqueue(scope: continuationScope) {
          transform(value).enqueue(on: driver, complete: complete)
        }
      }
    }
  }

  private func enqueue(
    on driver: ResolveWorkDriver,
    complete: @escaping @MainActor (Value) -> Void
  ) {
    driver.enqueue(scope: scope) { start(driver, complete) }
  }

  package func run() -> Value {
    ResolveWorkDiagnostics.activeDrains += 1
    ResolveWorkDiagnostics.maximumDrains = max(
      ResolveWorkDiagnostics.maximumDrains, ResolveWorkDiagnostics.activeDrains)
    defer { ResolveWorkDiagnostics.activeDrains -= 1 }
    if FeatureFlags.environmentValue(named: "SWIFTTUI_ASSERT_ITERATIVE_RESOLVE") == "1" {
      precondition(ResolveWorkDiagnostics.activeDrains == 1, "Nested synchronous resolve drain")
    }
    let driver = ResolveWorkDriver()
    var result: Value?
    var completed = false
    enqueue(on: driver) { value in
      result = value
      completed = true
    }
    driver.drain()
    precondition(completed, "Resolve work did not complete")
    return result!
  }
}

@MainActor
private final class ResolveWorkDriver {
  private var jobs: [@MainActor () -> Void] = []

  func enqueue(scope: ResolveContinuationScope, _ job: @escaping @MainActor () -> Void) {
    jobs.append { scope.run(job) }
  }

  func drain() {
    while let job = jobs.popLast() { job() }
  }
}

/// Only the effective scope is reinstalled for a step. Ancestral scopes do not
/// add native stack frames; their mutable ledgers remain owned by continuations.
@MainActor
private struct ResolveContinuationScope {
  let node = ViewNodeContext.current
  let authoring = currentAuthoringContext()
  let environment = EnvironmentValuesStorage.current
  let entity = ResolveEntityRouteStorage.current
  let lifetime = ResolveLifetimeScopeContext.current
  let styleLedger = StyleRouteInstallationLedgerStorage.current
  let forksStyles = StyleRouteInstallationLedgerStorage.forksPerDeclaredChild
  let observation = MemoObservationCertificateScope.current
  let dormantPolicy = DormantStateSlotPolicyScope.current

  func run(_ body: () -> Void) {
    let priorForks = StyleRouteInstallationLedgerStorage.forksPerDeclaredChild
    StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = forksStyles
    defer { StyleRouteInstallationLedgerStorage.forksPerDeclaredChild = priorForks }
    ViewNodeContext.withCurrentValue(node) {
      withAuthoringContext(authoring) {
        EnvironmentValuesStorage.binding(environment) {
          withResolveEntityRoute(entity) {
            ResolveLifetimeScopeContext.$current.withValue(lifetime) {
              StyleRouteInstallationLedgerStorage.$current.withValue(styleLedger) {
                MemoObservationCertificateScope.$current.withValue(observation) {
                  DormantStateSlotPolicyScope.$current.withValue(dormantPolicy) {
                    ViewUpdateGuard.withViewUpdate(body)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Main-actor diagnostic only; no graph or continuation survives a completed run.
@MainActor
package enum ResolveWorkDiagnostics {
  package static var activeDrains = 0
  package static var maximumDrains = 0
  package static func reset() {
    precondition(activeDrains == 0)
    maximumDrains = 0
  }
}
