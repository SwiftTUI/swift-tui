import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// F136 — the silent-default ambient-scope class.
///
/// `@Environment` reads resolve through the `EnvironmentValuesStorage`
/// task-local; when it is unbound the wrapper silently produces
/// `EnvironmentValues()` defaults. Outside any scene that is the documented
/// behavior, but *inside* an authoring/dispatch scope it is the observable
/// signature of a capture seam that failed to establish the
/// registration-time environment (the "`@Environment` in action closures
/// sees DEFAULTS" bug family). These suites pin the two halves of the
/// contract: the probe counter on in-scope fallback reads, and the
/// capture-preference orders of the four `HandlerDescriptorIntake`
/// initializers that exist to prevent the class.
@MainActor
@Suite("Ambient environment fallback probe")
struct AmbientEnvironmentFallbackProbeTests {
  private func makeAuthoringContext(_ name: String) -> AuthoringContext {
    AuthoringContext(
      viewIdentity: Identity(components: [IdentityComponent(rawValue: name)]),
      focusedValues: FocusedValues()
    )
  }

  @Test("an @Environment read inside a dispatch scope without environment counts")
  func inScopeFallbackReadCounts() {
    let snapshot = ImperativeAuthoringContextSnapshot(makeAuthoringContext("owner"))
    #expect(snapshot?.environmentValues == nil)

    let baseline = SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount
    let roots = withImperativeAuthoringContext(snapshot) {
      Environment(\.imageResourceRoots).wrappedValue
    }
    #expect(roots == [])
    #expect(SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount == baseline + 1)
    #expect(
      SoundnessProbeConfiguration.lastViolationDetail?.contains("imageResourceRoots") == true
    )
  }

  @Test("an @Environment read outside any authoring scope does not count")
  func outOfScopeFallbackReadDoesNotCount() {
    #expect(currentAuthoringContext() == nil)
    let baseline = SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount
    let roots = Environment(\.imageResourceRoots).wrappedValue
    #expect(roots == [])
    #expect(SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount == baseline)
  }

  @Test("a dispatch under an intake-stamped scope reads the stamp and does not count")
  func stampedDispatchDoesNotCount() {
    var environmentValues = EnvironmentValues()
    environmentValues.imageResourceRoots = ["stamped"]
    let context = ResolveContext(environmentValues: environmentValues)
    let intake = HandlerDescriptorIntake(
      context: context,
      preferringAuthoringScope: makeAuthoringContext("owner")
    )

    let baseline = SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount
    let roots = intake.wrapping {
      Environment(\.imageResourceRoots).wrappedValue
    }()
    #expect(roots == ["stamped"])
    #expect(SoundnessProbeConfiguration.ambientEnvironmentFallbackReadCount == baseline)
  }
}

/// The four `HandlerDescriptorIntake` initializers encode two load-bearing
/// capture-preference orders (control-family: construction scope wins;
/// modifier-family: resolve-time ambient wins). Nothing but call-site
/// discipline kept them straight — this contract pins which scope wins in
/// each initializer when BOTH are available, and that the resolve context's
/// authoritative environment is stamped over every winner.
@MainActor
@Suite("HandlerDescriptorIntake capture-preference order")
struct HandlerDescriptorIntakeOrderTests {
  private let ownerIdentity = Identity(components: [IdentityComponent(rawValue: "owner")])
  private let ambientIdentity = Identity(components: [IdentityComponent(rawValue: "ambient")])

  private var context: ResolveContext {
    var environmentValues = EnvironmentValues()
    environmentValues.imageResourceRoots = ["stamped"]
    return ResolveContext(environmentValues: environmentValues)
  }

  private func authoringContext(_ identity: Identity) -> AuthoringContext {
    AuthoringContext(viewIdentity: identity, focusedValues: FocusedValues())
  }

  private func withAmbientScope<Result>(_ body: () -> Result) -> Result {
    withAuthoringContext(authoringContext(ambientIdentity)) {
      body()
    }
  }

  @Test("preferringAuthoringScope: the construction scope beats the ambient")
  func preferringAuthoringScopeOrder() {
    let intake = withAmbientScope {
      HandlerDescriptorIntake(
        context: context,
        preferringAuthoringScope: authoringContext(ownerIdentity)
      )
    }
    #expect(intake.dispatchScope?.viewIdentity == ownerIdentity)

    let fallback = withAmbientScope {
      HandlerDescriptorIntake(context: context, preferringAuthoringScope: nil)
    }
    #expect(fallback.dispatchScope?.viewIdentity == ambientIdentity)
  }

  @Test("fallbackAuthoringScope: the ambient beats the construction scope")
  func fallbackAuthoringScopeOrder() {
    let intake = withAmbientScope {
      HandlerDescriptorIntake(
        context: context,
        fallbackAuthoringScope: authoringContext(ownerIdentity)
      )
    }
    #expect(intake.dispatchScope?.viewIdentity == ambientIdentity)

    let fallback = HandlerDescriptorIntake(
      context: context,
      fallbackAuthoringScope: authoringContext(ownerIdentity)
    )
    #expect(fallback.dispatchScope?.viewIdentity == ownerIdentity)
  }

  @Test("fallbackSnapshot: the ambient beats the stored snapshot")
  func fallbackSnapshotOrder() {
    let snapshot = ImperativeAuthoringContextSnapshot(authoringContext(ownerIdentity))
    let intake = withAmbientScope {
      HandlerDescriptorIntake(context: context, fallbackSnapshot: snapshot)
    }
    #expect(intake.dispatchScope?.viewIdentity == ambientIdentity)

    let fallback = HandlerDescriptorIntake(context: context, fallbackSnapshot: snapshot)
    #expect(fallback.dispatchScope?.viewIdentity == ownerIdentity)
  }

  @Test("preferringSnapshot: the stored snapshot beats the ambient")
  func preferringSnapshotOrder() {
    let snapshot = ImperativeAuthoringContextSnapshot(authoringContext(ownerIdentity))
    let intake = withAmbientScope {
      HandlerDescriptorIntake(context: context, preferringSnapshot: snapshot)
    }
    #expect(intake.dispatchScope?.viewIdentity == ownerIdentity)

    let fallback = withAmbientScope {
      HandlerDescriptorIntake(context: context, preferringSnapshot: nil)
    }
    #expect(fallback.dispatchScope?.viewIdentity == ambientIdentity)
  }

  @Test("every initializer stamps the resolve context's environment over the winner")
  func everyInitializerStampsTheContextEnvironment() {
    let context = context
    let owner = authoringContext(ownerIdentity)
    let snapshot = ImperativeAuthoringContextSnapshot(owner)
    let intakes: [HandlerDescriptorIntake] = withAmbientScope {
      [
        HandlerDescriptorIntake(context: context, preferringAuthoringScope: owner),
        HandlerDescriptorIntake(context: context, fallbackAuthoringScope: owner),
        HandlerDescriptorIntake(context: context, fallbackSnapshot: snapshot),
        HandlerDescriptorIntake(context: context, preferringSnapshot: snapshot),
      ]
    }
    for intake in intakes {
      #expect(intake.dispatchScope?.environmentValues == context.environmentValues)
    }
  }
}
