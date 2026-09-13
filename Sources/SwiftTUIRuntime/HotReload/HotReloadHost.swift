import SwiftTUICore
import SwiftTUIViews

/// One compiled root factory. The erasure stays inside the runtime boundary.
@MainActor
package final class HotReloadGeneration {
  // AnyView policy: independently compiled roots require private erasure. Keep
  // the root's concrete type out of its address; generations already isolate
  // lifetimes, and a wrapper edit must not change every descendant's prefix.
  private let resolve: @MainActor (ResolveContext) -> ResolveWork<[ResolvedNode]>

  package init<Content: View>(@ViewBuilder content: @escaping @MainActor () -> Content) {
    resolve = { context in
      scopedAnyView(authoringContext: nil, content).makeResolveWork(
        in: context, payloadIdentity: .named("ReloadContent"))
    }
  }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    resolve(context)
  }
}

@MainActor
package final class HotReloadSession {
  package private(set) var generation: UInt64 = 0
  package private(set) var content: HotReloadGeneration
  package private(set) var generationRoot: Identity?
  package private(set) var hostIdentity: Identity?
  package private(set) var lastReport: [HotReloadDiagnostic] = []
  package private(set) var awaitingCommit = false
  package var pendingFocus: Identity?
  private var isPreparing = false
  private weak var graph: ViewGraph?
  private var environment: EnvironmentSnapshot = .init()
  private var environmentValues: EnvironmentValues = .init()
  package var requestFrame: (() -> Void)?

  package init(content: HotReloadGeneration) { self.content = content }

  package func attach(context: ResolveContext, generationRoot: Identity) {
    graph = context.viewGraph
    hostIdentity = context.identity
    self.generationRoot = generationRoot
    environment = context.environment
    environmentValues = context.environmentValues
  }

  /// Rehearse state-dependent topology without publishing effects, then install.
  package func replace(
    with replacement: HotReloadGeneration, proposal: ProposedSize,
    focusedIdentity: Identity? = nil, maximumAttempts: Int = 4
  ) throws {
    guard !isPreparing, !awaitingCommit else { throw HotReloadSwapError.swapInProgress }
    isPreparing = true
    defer { isPreparing = false }
    guard let graph, let oldRoot = generationRoot, let hostIdentity,
      generation < UInt64.max, maximumAttempts > 0
    else { throw HotReloadSwapError.notMounted }
    let nextGeneration = generation + 1
    let newRoot = hostIdentity.child("Generation[\(nextGeneration)]")
    let snapshot = graph.captureHotReloadSnapshot(rootedAt: oldRoot)
    var schemas: [HotReloadOwnerSchema] = []
    var converged = false
    let invalidator = HotReloadProbeInvalidator()
    // Each pass owns a new graph: no seed, owner, memo result or registration
    // from a previous rehearsal can silently survive into another candidate.
    for _ in 0..<maximumAttempts {
      let renderer = DefaultRenderer()
      if !schemas.isEmpty {
        try renderer.viewGraph.installHotReloadReplay(snapshot, at: newRoot, owners: schemas)
      }
      let capture = HotReloadSchemaCapture()
      var context = ResolveContext(
        identity: hostIdentity, environment: environment, environmentValues: environmentValues)
      context.invalidationProxy = .init(invalidator: invalidator)
      _ = capture.collect {
        renderer.renderArtifacts(
          HotReloadProbeRoot(content: replacement, rootIdentity: newRoot),
          context: context, proposal: proposal)
      }
      let nextSchemas = capture.schemas(in: renderer.viewGraph, rootedAt: newRoot)
      if nextSchemas == schemas {
        converged = true
        break
      }
      schemas = nextSchemas
    }
    guard converged else { throw HotReloadSwapError.schemaDidNotConverge }
    lastReport = graph.finishHotReloadReplay()
    try graph.installHotReloadReplay(snapshot, at: newRoot, owners: schemas)
    content = replacement
    generation = nextGeneration
    generationRoot = newRoot
    if let focusedIdentity {
      pendingFocus = graph.hotReloadReplay?.rebasedIdentity(focusedIdentity, from: oldRoot)
    }
    awaitingCommit = true
    requestFrame?()
  }

  package func finishCommittedReplay() {
    guard awaitingCommit, let graph, let generationRoot,
      graph.liveIdentitySnapshot().contains(where: {
        $0 == generationRoot || $0.isDescendant(of: generationRoot)
      })
    else { return }
    lastReport = graph.finishHotReloadReplay(keepingDormant: true)
    awaitingCommit = false
  }
}

package enum HotReloadSwapError: Error {
  case swapInProgress
  case notMounted
  case schemaDidNotConverge
}

private final class HotReloadProbeInvalidator: Invalidating {
  func requestInvalidation(of identities: Set<Identity>) {}
}

package struct HotReloadHost: PrimitiveView, IterativeResolvableView {
  package let session: HotReloadSession
  // A fresh root value captures the generation, making the change visible to
  // value-based reuse checks even though the session object is stable.
  private let generation: UInt64

  @MainActor package init(session: HotReloadSession) {
    self.session = session
    generation = session.generation
  }

  package var body: Never { fatalError("HotReloadHost is a primitive view.") }

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let root = context.identity.child("Generation[\(generation)]")
    session.attach(context: context, generationRoot: root)
    return withAuthoringContext(nil) {
      session.content.makeResolveWork(
        in: context.child(
          component: .init(
            rawValue: "Generation[\(generation)]")))
    }
  }
}

private struct HotReloadProbeRoot: PrimitiveView, IterativeResolvableView {
  let content: HotReloadGeneration
  let rootIdentity: Identity
  var body: Never { fatalError("HotReloadProbeRoot is a primitive view.") }
  func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    withAuthoringContext(nil) {
      content.makeResolveWork(in: context.replacingIdentity(with: rootIdentity))
    }
  }
}
