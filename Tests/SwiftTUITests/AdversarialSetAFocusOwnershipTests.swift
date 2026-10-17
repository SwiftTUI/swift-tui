@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAFocusOwnershipTests {
  @Test func setA401NestedFocusedValueOverridesOnlyItsFocusedBranch() throws {
    // Hypothesis: ancestor registration order overwrites a deeper focused value after focus moves.
    let h = try make("401") {
      VStack {
        SetAFocusContextReadout()
        VStack {
          Button("Inner publisher") {}.focusedValue(\.setAFocusContext, "inner")
          Button("Outer publisher") {}
        }.focusedValue(\.setAFocusContext, "outer")
      }
    }
    defer { h.shutdown() }
    try h.focusText("Inner publisher")
    #expect(h.frame.contains("context=inner"), "\(h.frame)")
    try h.focusText("Outer publisher")
    #expect(h.frame.contains("context=outer"), "\(h.frame)")
  }

  @Test func setA402NilFocusedPublisherRevealsItsAncestorValue() throws {
    // Hypothesis: retiring an optional focused-value contribution leaves its previous inner shadow.
    let h = try make("402") { SetAOptionalFocusPublisher() }
    defer { h.shutdown() }
    try h.focusText("Optional publisher")
    try #require(h.frame.contains("context=inner"))
    try command("n", in: h)
    #expect(h.frame.contains("context=outer"), "\(h.frame)")
    try command("n", in: h)
    #expect(h.frame.contains("context=inner"), "\(h.frame)")
  }

  @Test func setA403EqualFocusedBindingValuesStillReplaceTheProjectedOwner() throws {
    // Hypothesis: value-only focus convergence treats equal bindings as interchangeable owners.
    let probe = SetAFocusOwnershipProbe()
    let h = try make("403") { SetAFocusedBindingSources(probe: probe, secondSeed: 0) }
    defer { h.shutdown() }
    try h.focusText("Binding owner A")
    try #require(probe.projected?.wrappedValue == 0)
    try h.focusText("Binding owner B")
    try requireFocus("Binding owner B", in: h)
    try #require(probe.projected?.wrappedValue == 0)
    // This is the projection exported by the latest rendered remote reader, not a saved old binding.
    try command("p", in: h)
    let first = try #require(probe.firstSource?.wrappedValue)
    let second = try #require(probe.secondSource?.wrappedValue)
    try #require(first + second == 1)
    try requireFocus("Binding owner B", in: h)
    #expect(h.frame.contains("ownerA=\(first);ownerB=\(second);"), "\(h.frame)")
    do {
      #expect(
        first == 0 && second == 1,
        "Focused owner B received projected write: source A=\(first), B=\(second); frame:\n\(h.frame)"
      )
    }
  }

  @Test func setA404FocusedPayloadChangeReachesRemoteReaderWithoutMovingFocus() throws {
    // Hypothesis: precise reader invalidation loses pure focused-value changes beneath a reused root.
    let h = try make("404") { SetAChangingFocusPublisher() }
    defer { h.shutdown() }
    try h.focusText("Changing publisher")
    let originalFocus = h.runLoop.focusTracker.currentFocusIdentity
    try #require(h.frame.contains("context=value0"))
    try command("v", in: h)
    #expect(h.frame.contains("context=value1"), "\(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == originalFocus)
  }

  @Test func setA405FocusedValueKeysMergeWithoutErasingUnchangedAncestorKeys() throws {
    // Hypothesis: merging a child's focused values replaces the entire ancestor dictionary.
    let h = try make("405") {
      VStack {
        SetATwoFocusKeysReadout()
        VStack {
          Button("Two keys") {}.focusedValue(\.setAFocusDetail, "detail")
          Button("One key") {}
        }.focusedValue(\.setAFocusContext, "context")
      }
    }
    defer { h.shutdown() }
    try h.focusText("Two keys")
    #expect(h.frame.contains("keys=context/detail"), "\(h.frame)")
    try h.focusText("One key")
    #expect(h.frame.contains("keys=context/none"), "\(h.frame)")
  }

  @Test func setA406AssigningNilThroughFocusedBindingDoesNotMutateItsSource() throws {
    // Hypothesis: optional reader assignment writes a fabricated default into a nonoptional source.
    let probe = SetAFocusOwnershipProbe()
    let h = try make("406") { SetAFocusedBindingSources(probe: probe, secondSeed: 20) }
    defer { h.shutdown() }
    try h.focusText("Binding owner B")
    try #require(probe.projected?.wrappedValue == 20)
    try command("n", in: h)
    #expect(h.frame.contains("ownerA=0;ownerB=20;"), "\(h.frame)")
    try h.focusText("Remote consumer")
    try #require(probe.projected == nil)
    try command("m", in: h)
    #expect(h.frame.contains("ownerA=0;ownerB=20;"), "\(h.frame)")
  }

  @Test func setA407LeavingPublisherClearsRemoteFocusedContext() throws {
    // Hypothesis: reader carry-forward retains context after traversal reaches an unpublishing control.
    let h = try make("407") {
      VStack {
        SetAFocusContextReadout()
        Button("Published context") {}.focusedValue(\.setAFocusContext, "published")
        Button("Plain context") {}
      }
    }
    defer { h.shutdown() }
    try h.focusText("Published context")
    try #require(h.frame.contains("context=published"))
    try h.pressKey(.init(.tab))
    try requireFocus("Plain context", in: h)
    #expect(h.frame.contains("context=none"), "\(h.frame)")
  }

  @Test func setA408PointerConsumerUsesThePublisherFocusedWhenTheClickBegan() throws {
    // Hypothesis: press-time focus on a remote action erases the originating focused-binding context.
    let probe = SetAFocusOwnershipProbe()
    let h = try make("408") { SetAFocusedBindingSources(probe: probe, secondSeed: 20) }
    defer { h.shutdown() }
    try h.focusText("Binding owner B")
    try #require(probe.projected?.wrappedValue == 20)
    try h.clickText("Remote consumer")
    #expect(h.frame.contains("ownerA=0;ownerB=21;"), "\(h.frame)")
  }

  @Test func setA409FocusRequestCanTargetContentInsertedByTheSameAction() throws {
    // Hypothesis: request arbitration runs before new focus registrations are published.
    let h = try make("409") { SetAInsertedFocusTarget() }
    defer { h.shutdown() }
    try command("i", in: h)
    try requireFocus("Inserted target", in: h)
    #expect(h.frame.contains("selection=new"), "\(h.frame)")
  }

  @Test func setA410IndependentBooleanFocusOwnersSynchronizeOnlyTheirOwnSlots() throws {
    // Hypothesis: two Boolean focus declarations share a registration key and both report focused.
    let h = try make("410") { SetABooleanFocusOwners() }
    defer { h.shutdown() }
    try h.focusText("Boolean owner A")
    #expect(h.frame.contains("flags=true/false"), "\(h.frame)")
    try h.focusText("Boolean owner B")
    #expect(h.frame.contains("flags=false/true"), "\(h.frame)")
  }

  @Test func setA411UnavailableRequestCannotBlockALaterLiveFocusOwner() throws {
    // Hypothesis: arbitration stops at an earlier pending binding whose target is not focusable.
    let h = try make("411") { SetACompetingFocusRequests() }
    defer { h.shutdown() }
    try command("r", in: h)
    try requireFocus("Live request target", in: h)
    #expect(h.frame.contains("requests=false/true"), "\(h.frame)")
  }

  @Test func setA412DisablingFocusEffectPreservesOwnershipAndKeyboardActivation() throws {
    // Hypothesis: focus-effect suppression accidentally removes the active region or its action route.
    let probe = SetAFocusOwnershipProbe()
    let h = try make("412") { SetAFocusEffectOwner(probe: probe) }
    defer { h.shutdown() }
    try h.focusText("Effect target")
    let before = h.runLoop.focusTracker.currentFocusIdentity
    try command("e", in: h)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == before)
    try h.pressKey(.init(.return))
    #expect(probe.events == ["activated"], "\(probe.events)")
  }

  @Test func setA413InitialFocusAdoptionPublishesTheFocusedEnvironmentCone() throws {
    // Hypothesis: initial focus adoption commits the pre-focus environment without a convergence pass.
    let h = try make("413") { SetAFocusConeRoot() }
    defer { h.shutdown() }
    try requireFocus("Cone left", in: h)
    do {
      #expect(
        h.frame.contains("parent=true") && h.frame.contains("left=true"),
        "Initial focused identity=\(String(describing: h.runLoop.focusTracker.currentFocusIdentity)); frame:\n\(h.frame)"
      )
    }
    #expect(h.frame.contains("right=false"), "\(h.frame)")
    try h.pressKey(.init(.tab))
    try requireFocus("Cone right", in: h)
    #expect(h.frame.contains("parent=true"), "\(h.frame)")
    #expect(h.frame.contains("left=false"), "\(h.frame)")
    #expect(h.frame.contains("right=true"), "\(h.frame)")
    try h.pressKey(.init(.tab, modifiers: .shift))
    try requireFocus("Cone left", in: h)
    #expect(h.frame.contains("parent=true"), "\(h.frame)")
    #expect(h.frame.contains("left=true"), "\(h.frame)")
    #expect(h.frame.contains("right=false"), "\(h.frame)")
  }

  @Test func setA414ResetFocusUsesTheCurrentPreferredCandidate() throws {
    // Hypothesis: namespace reset replays the initial candidate after its preference flag changes.
    let h = try make("414") { SetAResetFocusScope() }
    defer { h.shutdown() }
    try requireFocus("Scope preferred A", in: h)
    try command("s", in: h)
    try h.focusText("Scope ordinary")
    try command("r", in: h)
    try requireFocus("Scope preferred B", in: h)
  }

  @Test func setA415UnavailableDefaultCandidateFallsBackInsideItsNamespace() throws {
    // Hypothesis: an unavailable preferred region prevents reset from choosing the scope's live fallback.
    let h = try make("415") { SetADisabledDefaultScope() }
    defer { h.shutdown() }
    try h.focusText("Outside fallback scope")
    try command("r", in: h)
    try requireFocus("Inside fallback scope", in: h)
  }

  @Test func setA416ResettingOneNamespaceCannotChooseASiblingsPreferredTarget() throws {
    // Hypothesis: global candidate order wins over the namespace filter during reset arbitration.
    let h = try make("416") { SetASiblingDefaultScopes() }
    defer { h.shutdown() }
    try h.focusText("Left preferred")
    try command("r", in: h)
    try requireFocus("Right preferred", in: h)
    try command("l", in: h)
    try requireFocus("Left preferred", in: h)
  }

  @Test func setA417DefaultFocusSeedDoesNotRearmAfterExplicitClear() throws {
    // Hypothesis: a consumed defaultFocus seed is lost on selective reevaluation and steals cleared focus.
    let h = try make("417") { SetAOneShotDefaultFocus() }
    defer { h.shutdown() }
    try requireFocus("Seeded default", in: h)
    try command("u", in: h)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == nil)
    #expect(h.frame.contains("seed-focused=false"), "\(h.frame)")
    try h.render()
    #expect(h.runLoop.focusTracker.currentFocusIdentity == nil)
  }

  @Test func setA418SemanticLabelUpdatePreservesAssistiveFocusOwnership() throws {
    // Hypothesis: semantic payload replacement retires assistive focus despite an unchanged view owner.
    let h = try make("418") { SetAAssistiveFocusOwner() }
    defer { h.shutdown() }
    try send(.accessibilityFocus, to: "Review alpha", in: h)
    try #require(try node("Review alpha", in: h).isAccessibilityFocused)
    try command("l", in: h)
    #expect(try node("Review beta", in: h).isAccessibilityFocused)
    #expect(h.frame.contains("review=true"), "\(h.frame)")
  }

  @Test func setA419HiddenSemanticTargetClearsItsStillLiveAssistiveBinding() throws {
    // Hypothesis: hiding a semantic target clears the coordinator but leaves its owner's Boolean true.
    let h = try make("419") { SetAAssistiveFocusOwner() }
    defer { h.shutdown() }
    try send(.accessibilityFocus, to: "Review alpha", in: h)
    try #require(h.frame.contains("review=true"))
    try command("h", in: h)
    #expect(h.frame.contains("review=false"), "\(h.frame)")
    #expect(
      !h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
  }

  @Test func setA420NativeAssistiveFocusUpdatesOptionalSelectionWithoutKeyboardMovement() throws {
    // Hypothesis: native semantic focus feedback updates the keyboard domain or the wrong optional case.
    let h = try make("420") { SetAAssistiveOptionalOwners() }
    defer { h.shutdown() }
    try h.focusText("Keyboard anchor")
    let keyboard = h.runLoop.focusTracker.currentFocusIdentity
    try send(.accessibilityFocus, to: "Review second", in: h)
    #expect(h.frame.contains("review-selection=second"), "\(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == keyboard)
    try send(.accessibilityFocus, to: "Review first", in: h)
    #expect(h.frame.contains("review-selection=first"), "\(h.frame)")
  }

  @Test func setA421RepeatedAssistiveRequestAdvancesHostGeneration() throws {
    // Hypothesis: an equal authored focus value is deduplicated before a new host request is emitted.
    let h = try make("421") { SetAAssistiveFocusOwner() }
    defer { h.shutdown() }
    try command("f", in: h)
    let first = try #require(h.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest)
    try #require(first.target != nil)
    try command("f", in: h)
    let second = try #require(h.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest)
    #expect(second.generation > first.generation)
    #expect(second.target == (try node("Review alpha", in: h)).actionTarget)
  }

  @Test func setA422LateBlurFromAnotherLiveTargetCannotClearCurrentAssistiveFocus() throws {
    // Hypothesis: a valid but noncurrent semantic blur is treated as a global focus clear.
    let h = try make("422") { SetAAssistiveOptionalOwners() }
    defer { h.shutdown() }
    try send(.accessibilityFocus, to: "Review first", in: h)
    try send(.accessibilityFocus, to: "Review second", in: h)
    try send(.accessibilityBlur, to: "Review first", in: h)
    #expect(try node("Review second", in: h).isAccessibilityFocused)
    #expect(h.frame.contains("review-selection=second"), "\(h.frame)")
  }

  @Test func setA423AssistiveFocusStorageStaysIsolatedAcrossLiveGraphs() throws {
    // Hypothesis: identical structural declarations share an assistive focus slot across two runtimes.
    let first = try make("423") { SetAAssistiveFocusOwner() }
    let second = try make("423") { SetAAssistiveFocusOwner() }
    defer {
      first.shutdown()
      second.shutdown()
    }
    try send(.accessibilityFocus, to: "Review alpha", in: first)
    try #require(first.frame.contains("review=true"))
    try second.render()
    #expect(second.frame.contains("review=false"), "\(second.frame)")
    #expect(
      !second.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
    try command("f", in: second)
    first.shutdown()
    try second.render()
    #expect(try node("Review alpha", in: second).isAccessibilityFocused)
  }

  @Test func setA424AssistiveFocusDoesNotReplaceKeyboardFocusedValues() throws {
    // Hypothesis: semantic-review synchronization exports its target's context through keyboard focus.
    let h = try make("424") { SetASeparateFocusContexts() }
    defer { h.shutdown() }
    try h.focusText("Keyboard publisher")
    try #require(h.frame.contains("context=keyboard"))
    try send(.accessibilityFocus, to: "Review publisher", in: h)
    #expect(try node("Review publisher", in: h).isAccessibilityFocused)
    #expect(h.frame.contains("context=keyboard"), "\(h.frame)")
  }

  @Test func setA425AssistiveFocusModifierPreservesTypedControlMutation() throws {
    // Hypothesis: installing semantic-focus actions replaces a Toggle's existing typed value action.
    let h = try make("425") { SetAAssistiveToggleOwner() }
    defer { h.shutdown() }
    let initial = try node("Review toggle", in: h)
    #expect(initial.control?.actions.contains(.setValue) == true)
    #expect(initial.control?.actions.contains(.accessibilityFocus) == true)
    try send(.accessibilityFocus, to: "Review toggle", in: h)
    try send(.setValue(.boolean(true)), to: "Review toggle", in: h)
    #expect(h.frame.contains("toggle-value=true;toggle-review=true"), "\(h.frame)")
  }

  private func make<V: View>(_ id: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAFocusOwnership", id),
      size: .init(width: 80, height: 28), content: content)
  }

  private func command<V: View>(_ character: Character, in h: StressRuntimeHarness<V>) throws {
    try h.pressKey(.init(.character(character), modifiers: .ctrl))
  }

  private func requireFocus<V: View>(_ label: String, in h: StressRuntimeHarness<V>) throws {
    let expected = try h.focusIdentity(forText: label)
    try #require(h.runLoop.focusTracker.currentFocusIdentity == expected, "\(h.frame)")
  }

  private func node<V: View>(_ label: String, in h: StressRuntimeHarness<V>) throws
    -> AccessibilityNode
  {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label })
  }

  private func send<V: View>(
    _ action: AccessibilityAction, to label: String, in h: StressRuntimeHarness<V>
  ) throws {
    let target = try #require(try node(label, in: h).actionTarget)
    #expect(h.runLoop.handleAccessibilityAction(.init(target: target, action: action)) == .accepted)
    try h.render()
  }
}

@MainActor
private final class SetAFocusOwnershipProbe {
  var projected: Binding<Int>?
  var firstSource: Binding<Int>?
  var secondSource: Binding<Int>?
  var events: [String] = []
}

private enum SetAFocusContextKey: FocusedValueKey { typealias Value = String }
private enum SetAFocusDetailKey: FocusedValueKey { typealias Value = String }
private enum SetAFocusNumberKey: FocusedValueKey { typealias Value = Binding<Int> }

extension FocusedValues {
  var setAFocusContext: String? {
    get { self[SetAFocusContextKey.self] }
    set { self[SetAFocusContextKey.self] = newValue }
  }
  var setAFocusDetail: String? {
    get { self[SetAFocusDetailKey.self] }
    set { self[SetAFocusDetailKey.self] = newValue }
  }
  var setAFocusNumber: Binding<Int>? {
    get { self[SetAFocusNumberKey.self] }
    set { self[SetAFocusNumberKey.self] = newValue }
  }
}

@MainActor
private struct SetAFocusContextReadout: View {
  @FocusedValue(\.setAFocusContext) private var context
  var body: some View { Text("context=\(context ?? "none")") }
}

@MainActor
private struct SetATwoFocusKeysReadout: View {
  @FocusedValue(\.setAFocusContext) private var context
  @FocusedValue(\.setAFocusDetail) private var detail
  var body: some View { Text("keys=\(context ?? "none")/\(detail ?? "none")") }
}

@MainActor
private struct SetAOptionalFocusPublisher: View {
  @State private var publishes = true
  var body: some View {
    VStack {
      SetAFocusContextReadout()
      VStack {
        Button("Optional publisher") {}
          .focusedValue(\.setAFocusContext, publishes ? "inner" : nil)
      }.focusedValue(\.setAFocusContext, "outer")
    }
    .onKeyPress(.character("n"), modifiers: .ctrl) { _ in
      publishes.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAFocusedBindingSources: View {
  let probe: SetAFocusOwnershipProbe
  @State private var first = 0
  @State private var second: Int
  @FocusedBinding(\.setAFocusNumber) private var selected

  init(probe: SetAFocusOwnershipProbe, secondSeed: Int) {
    self.probe = probe
    _second = State(initialValue: secondSeed)
  }

  var body: some View {
    probe.projected = $selected
    probe.firstSource = $first
    probe.secondSource = $second
    return VStack {
      Text("ownerA=\(first);ownerB=\(second);")
      Text("remote-number=\(selected.map(String.init) ?? "none")")
      Button("Binding owner A") {}.focusedValue(\.setAFocusNumber, $first)
      Button("Binding owner B") {}.focusedValue(\.setAFocusNumber, $second)
      Button("Remote consumer") {
        if let value = selected { selected = value + 1 }
      }
    }
    .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
      if let binding = probe.projected { binding.wrappedValue += 1 }
      return .handled
    }
    .onKeyPress(.character("n"), modifiers: .ctrl) { _ in
      selected = nil
      return .handled
    }
    .onKeyPress(.character("m"), modifiers: .ctrl) { _ in
      selected = 99
      return .handled
    }
  }
}

@MainActor
private struct SetAChangingFocusPublisher: View {
  @State private var value = 0
  var body: some View {
    VStack {
      SetAFocusContextReadout()
      Button("Changing publisher") {}.focusedValue(\.setAFocusContext, "value\(value)")
    }
    .onKeyPress(.character("v"), modifiers: .ctrl) { _ in
      value += 1
      return .handled
    }
  }
}

@MainActor
private struct SetAInsertedFocusTarget: View {
  @State private var inserted = false
  @FocusState private var selection: String?
  var body: some View {
    VStack {
      Text("selection=\(selection ?? "none")")
      Button("Existing target") {}.focused($selection, equals: "old")
      if inserted {
        Button("Inserted target") {}.focused($selection, equals: "new")
      }
    }
    .onKeyPress(.character("i"), modifiers: .ctrl) { _ in
      inserted = true
      selection = "new"
      return .handled
    }
  }
}

@MainActor
private struct SetABooleanFocusOwners: View {
  @FocusState private var first: Bool
  @FocusState private var second: Bool
  var body: some View {
    VStack {
      Text("flags=\(first)/\(second)")
      Button("Boolean owner A") {}.focused($first)
      Button("Boolean owner B") {}.focused($second)
    }
  }
}

@MainActor
private struct SetACompetingFocusRequests: View {
  @FocusState private var unavailable: Bool
  @FocusState private var available: Bool
  var body: some View {
    VStack {
      Text("requests=\(unavailable)/\(available)")
      Button("Initial request anchor") {}
      Button("Unavailable request target") {}.disabled(true).focused($unavailable)
      Button("Live request target") {}.focused($available)
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      unavailable = true
      available = true
      return .handled
    }
  }
}

@MainActor
private struct SetAFocusEffectOwner: View {
  let probe: SetAFocusOwnershipProbe
  @State private var disabled = false
  var body: some View {
    Button("Effect target") { probe.events.append("activated") }
      .focusEffectDisabled(disabled)
      .onKeyPress(.character("e"), modifiers: .ctrl) { _ in
        disabled.toggle()
        return .handled
      }
  }
}

@MainActor
private struct SetAFocusConeRoot: View {
  @Environment(\.isFocused) private var focused
  var body: some View {
    VStack {
      Text("parent=\(focused)")
      HStack {
        SetAFocusConeBranch(name: "left")
        SetAFocusConeBranch(name: "right")
      }
    }
  }
}

@MainActor
private struct SetAFocusConeBranch: View {
  let name: String
  @Environment(\.isFocused) private var focused
  var body: some View {
    VStack {
      Text("\(name)=\(focused)")
      Button("Cone \(name)") {}
    }
  }
}

@MainActor
private struct SetAResetFocusScope: View {
  @Namespace private var namespace
  @Environment(\.resetFocus) private var resetFocus
  @State private var prefersSecond = false
  var body: some View {
    VStack {
      Button("Scope preferred A") {}.prefersDefaultFocus(!prefersSecond, in: namespace)
      Button("Scope preferred B") {}.prefersDefaultFocus(prefersSecond, in: namespace)
      Button("Scope ordinary") {}
    }
    .focusScope(namespace)
    .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
      prefersSecond = true
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      _ = resetFocus(in: namespace)
      return .handled
    }
  }
}

@MainActor
private struct SetADisabledDefaultScope: View {
  @Namespace private var namespace
  @Environment(\.resetFocus) private var resetFocus
  var body: some View {
    VStack {
      Button("Outside fallback scope") {}
      VStack {
        Button("Unavailable preferred") {}.disabled(true).prefersDefaultFocus(in: namespace)
        Button("Inside fallback scope") {}
      }.focusScope(namespace)
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      _ = resetFocus(in: namespace)
      return .handled
    }
  }
}

@MainActor
private struct SetASiblingDefaultScopes: View {
  @Namespace private var left
  @Namespace private var right
  @Environment(\.resetFocus) private var resetFocus
  var body: some View {
    HStack {
      VStack {
        Button("Left ordinary") {}
        Button("Left preferred") {}.prefersDefaultFocus(in: left)
      }.focusScope(left)
      VStack {
        Button("Right ordinary") {}
        Button("Right preferred") {}.prefersDefaultFocus(in: right)
      }.focusScope(right)
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      _ = resetFocus(in: right)
      return .handled
    }
    .onKeyPress(.character("l"), modifiers: .ctrl) { _ in
      _ = resetFocus(in: left)
      return .handled
    }
  }
}

@MainActor
private struct SetAOneShotDefaultFocus: View {
  @FocusState private var focused: Bool
  @State private var generation = 0
  var body: some View {
    VStack {
      Text("seed-focused=\(focused);generation=\(generation)")
      Button("Seeded default") {}.focused($focused)
    }
    .defaultFocus($focused)
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      generation += 1
      focused = false
      return .handled
    }
  }
}

@MainActor
private struct SetAAssistiveFocusOwner: View {
  @State private var renamed = false
  @State private var hidden = false
  @AccessibilityFocusState private var review: Bool
  var body: some View {
    VStack {
      Button("Keyboard anchor") {}
      Text("review=\(review)")
      Text(renamed ? "Review beta" : "Review alpha")
        .accessibilityLabel(renamed ? "Review beta" : "Review alpha")
        .accessibilityFocused($review)
        .accessibilityHidden(hidden)
    }
    .onKeyPress(.character("l"), modifiers: .ctrl) { _ in
      renamed = true
      return .handled
    }
    .onKeyPress(.character("h"), modifiers: .ctrl) { _ in
      hidden = true
      return .handled
    }
    .onKeyPress(.character("f"), modifiers: .ctrl) { _ in
      review = true
      return .handled
    }
  }
}

@MainActor
private struct SetAAssistiveOptionalOwners: View {
  @AccessibilityFocusState private var selection: String?
  var body: some View {
    VStack {
      Button("Keyboard anchor") {}
      Text("review-selection=\(selection ?? "none")")
      Text("Review first").accessibilityFocused($selection, equals: "first")
      Text("Review second").accessibilityFocused($selection, equals: "second")
    }
  }
}

@MainActor
private struct SetASeparateFocusContexts: View {
  @AccessibilityFocusState private var review: Bool
  var body: some View {
    VStack {
      SetAFocusContextReadout()
      Button("Keyboard publisher") {}.focusedValue(\.setAFocusContext, "keyboard")
      Text("Review publisher")
        .accessibilityFocused($review)
        .focusedValue(\.setAFocusContext, "assistive")
    }
  }
}

@MainActor
private struct SetAAssistiveToggleOwner: View {
  @State private var value = false
  @AccessibilityFocusState private var review: Bool
  var body: some View {
    VStack {
      Text("toggle-value=\(value);toggle-review=\(review)")
      Toggle("Review toggle", isOn: $value).accessibilityFocused($review)
    }
  }
}
