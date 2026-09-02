import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// The draft-survival contract for registries that outlive the frame head's
/// draft swap.
///
/// A draft-surviving registry has three obligations, and `F179`'s storage
/// totality suite enforces only the first:
///
/// 1. it is classified `.survives`, so `replacingRuntimeRegistrations` leaves
///    it alone — already covered by `ResolveContextStorageTotalityTests`;
/// 2. it is *seeded* from its pre-draft counterpart at the frame head;
/// 3. its consumers read it through an accessor that prefers the live instance
///    over the draft one.
///
/// Obligations 2 and 3 had no guard. Missing either is silent in the worst
/// way: an unseeded `live*` stays `nil`, the `?? local*` accessor falls through
/// to the draft registry, and imperative bridges resume writing to an instance
/// discarded at the end of the frame — the stale-draft-registry class, back by
/// omission, with every existing test still green.
@MainActor
struct ResolveContextDraftSurvivalTests {
  @Test("captured pre-draft registries survive the draft swap")
  func seedingCarriesRegistriesAcrossTheDraftSwap() {
    var context = ResolveContext(identity: testIdentity("DraftSurvival", "Seed"))
    let liveScroll = LocalScrollPositionRegistry()
    let liveFocus = LocalFocusBindingRegistry()
    let liveGesture = LocalGestureRegistry()
    context.localScrollPositionRegistry = liveScroll
    context.localFocusBindingRegistry = liveFocus
    context.localGestureRegistry = liveGesture

    let captured = context.capturingDraftSurvivingRegistries()
    let swapped =
      context
      .replacingRuntimeRegistrations(.scratch())
      .seedingDraftSurvivingRegistries(from: captured)

    // The draft swap installed fresh registration instances...
    #expect(swapped.localScrollPositionRegistry !== liveScroll)
    #expect(swapped.localFocusBindingRegistry !== liveFocus)
    #expect(swapped.localGestureRegistry !== liveGesture)
    // ...while the live companions still point at the pre-draft instances.
    #expect(swapped.liveScrollPositionRegistry === liveScroll)
    #expect(swapped.liveFocusBindingRegistry === liveFocus)
    #expect(swapped.liveGestureRegistry === liveGesture)
  }

  @Test("imperative accessors prefer the live instance over the draft")
  func accessorsPreferTheLiveInstance() {
    var context = ResolveContext(identity: testIdentity("DraftSurvival", "Accessor"))
    let liveScroll = LocalScrollPositionRegistry()
    let liveFocus = LocalFocusBindingRegistry()
    let liveGesture = LocalGestureRegistry()
    context.localScrollPositionRegistry = liveScroll
    context.localFocusBindingRegistry = liveFocus
    context.localGestureRegistry = liveGesture

    let captured = context.capturingDraftSurvivingRegistries()
    let swapped =
      context
      .replacingRuntimeRegistrations(.scratch())
      .seedingDraftSurvivingRegistries(from: captured)

    // This is the assertion the whole mechanism exists for: an imperative
    // bridge resolving under a replayed context reaches the instance the
    // commit publishes into, not the draft that is about to be discarded.
    #expect(swapped.scrollCommandRegistry === liveScroll)
    #expect(swapped.focusArrivalRegistry === liveFocus)
    #expect(swapped.gestureDispatchRegistry === liveGesture)
  }

  @Test("seeding never displaces an already-captured live instance")
  func seedingKeepsTheOldestLiveInstance() {
    // Nested frame heads: the outer capture is the older instance and must win,
    // otherwise a nested seed would re-point live bridges at a newer draft.
    var context = ResolveContext(identity: testIdentity("DraftSurvival", "Nested"))
    let outerScroll = LocalScrollPositionRegistry()
    let outerFocus = LocalFocusBindingRegistry()
    let outerGesture = LocalGestureRegistry()
    context.liveScrollPositionRegistry = outerScroll
    context.liveFocusBindingRegistry = outerFocus
    context.liveGestureRegistry = outerGesture
    context.localScrollPositionRegistry = LocalScrollPositionRegistry()
    context.localFocusBindingRegistry = LocalFocusBindingRegistry()
    context.localGestureRegistry = LocalGestureRegistry()

    let seeded = context.seedingDraftSurvivingRegistries(
      from: context.capturingDraftSurvivingRegistries()
    )

    #expect(seeded.liveScrollPositionRegistry === outerScroll)
    #expect(seeded.liveFocusBindingRegistry === outerFocus)
    #expect(seeded.liveGestureRegistry === outerGesture)
  }

  @Test("every live registry is covered by capture, seeding, and an accessor")
  func liveRegistryRosterIsFullyCovered() {
    // The roster check. `live*` stored properties are the draft-surviving
    // registries; each one needs a capture field, a seeding branch, and a
    // preferring accessor. A new one that skips any of those is silent, so
    // this count forces this file to be revisited.
    let mirror = Mirror(reflecting: ResolveContext.PropagatedRegistries())
    let liveMembers = mirror.children.compactMap { child -> String? in
      guard let label = child.label, label.hasPrefix("live") else {
        return nil
      }
      return label
    }

    #expect(
      liveMembers.sorted()
        == ["liveFocusBindingRegistry", "liveGestureRegistry", "liveScrollPositionRegistry"],
      """
      the draft-surviving roster changed (\(liveMembers.sorted())). A new live \
      registry needs: a field in ResolveContext.DraftSurvivingRegistries, a \
      branch in seedingDraftSurvivingRegistries(from:), a `?? local*` accessor, \
      and cases in this suite — otherwise it stays nil and its accessor \
      silently returns the discarded draft registry.
      """
    )
  }
}
