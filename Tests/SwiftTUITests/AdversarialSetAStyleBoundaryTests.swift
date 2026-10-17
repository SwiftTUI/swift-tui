@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAStyleBoundaryTests {
  @Test func setA851EqualDiagnosticLabelsDoNotAliasErasedConcreteStyles() throws {
    // Hypothesis: erased style reuse keys on snapshotLabel and retains a different concrete body's paint.
    let changed = StyleBoundaryValue(false)
    let h = try harness(851) {
      Label("Authored") { Text("*") }
        .labelStyle(
          changed.value
            ? AnyLabelStyle(StyleBoundarySecondLabel()) : AnyLabelStyle(StyleBoundaryFirstLabel()))
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("First body"))
    changed.value = true
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Second body"))
    #expect(!h.frame.contains("First body"))
  }

  @Test func setA852StyleValueRefreshKeepsItsOwnStateOwner() throws {
    // Hypothesis: changing a stored style parameter either reuses stale chrome or replaces the style's state lifetime.
    let prefix = StyleBoundaryValue("Before")
    let h = try harness(852) {
      Label("Authored") { Text("*") }.labelStyle(StyleBoundaryCountingLabel(prefix: prefix.value))
    }
    defer { h.shutdown() }
    try h.clickText("Before count 0")
    #expect(h.frame.contains("Before count 1"))
    prefix.value = "After"
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("After count 1"))
    try h.clickText("After count 1")
    #expect(h.frame.contains("After count 2"))
  }

  @Test func setA853NearestStyleOverrideDoesNotEscapeIntoASibling() throws {
    // Hypothesis: resolving a nested style environment mutates the inherited erased style for later siblings.
    let h = try harness(853) {
      VStack(alignment: .leading, spacing: 0) {
        Label("Inner") { Text("*") }.labelStyle(StyleBoundaryPrefixLabel(prefix: "Local"))
        Label("Sibling") { Text("*") }
      }.labelStyle(StyleBoundaryPrefixLabel(prefix: "Outer"))
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("Local Inner"))
    #expect(h.frame.contains("Outer Sibling"))
    #expect(!h.frame.contains("Local Sibling"))
  }

  @Test func setA854ProminenceResolutionPrecedesTheStyleConfiguration() throws {
    // Hypothesis: the primitive passes inherited prominence to makeBody before applying the style's override.
    let probe = StyleBoundaryProbe()
    let h = try harness(854) {
      Button("Prominence") {}.buttonStyle(StyleBoundaryProminentButton(probe: probe))
        .controlProminence(.standard)
    }
    defer { h.shutdown() }
    #expect(probe.baseProminence == .standard)
    #expect(probe.bodyProminence == .increased)
    #expect(h.frame.contains("Prominence"))
  }

  @Test func setA855ForwardedConfigurationFlagsCannotEnableThePrimitive() throws {
    // Hypothesis: mutating a style's configuration copy changes primitive-owned enablement and permits activation.
    let calls = StyleBoundaryValue(0)
    let h = try harness(855) {
      Button("Disabled authored") { calls.value += 1 }
        .buttonStyle(StyleBoundaryForgedEnabledButton()).disabled(true)
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("Enabled copy"))
    try h.clickText("Enabled copy")
    try h.pressKey(.init(.return))
    #expect(calls.value == 0)
    let node = try node("Disabled authored", in: h)
    #expect(node.isEnabled == false)
  }

  @Test func setA856OmittingButtonLabelPreservesAuthoredNameAndAction() throws {
    // Hypothesis: accessibility naming and activation are extracted only from the replacement style's painted label.
    let calls = StyleBoundaryValue(0)
    let h = try harness(856) {
      Button("Authored operation") { calls.value += 1 }.buttonStyle(StyleBoundaryChromeButton())
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("Chrome only"))
    #expect(!h.frame.contains("Authored operation"))
    let button = try node("Authored operation", in: h)
    #expect(try send(.activate, to: button, in: h) == .accepted)
    #expect(calls.value == 1)
  }

  @Test func setA857ChangingConfigurationEnablementCannotBypassTheGuardedBinding() throws {
    // Hypothesis: the configuration's mutable isEnabled flag is consulted by its binding instead of captured primitive policy.
    let value = StyleBoundaryValue(false)
    let probe = StyleBoundaryProbe()
    let h = try harness(857) {
      Toggle("Guarded", isOn: value.binding).toggleStyle(StyleBoundaryCapturingToggle(probe: probe))
        .disabled(true)
    }
    defer { h.shutdown() }
    var configuration = try #require(probe.toggle)
    configuration.isEnabled = true
    configuration.isOn = true
    #expect(value.value == false)
    #expect(value.writes == 0)
    #expect(configuration.isOn == false)
  }

  @Test func setA858GuardedStyleProjectionPreservesBindingMetadata() throws {
    // Hypothesis: wrapping a style-writable binding loses its source identity or stored transaction before write-through.
    let value = StyleBoundaryValue(false)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    let binding = value.binding.transaction(transaction).withBindingSource("SetA858Source")
    let probe = StyleBoundaryProbe()
    let h = try harness(858) {
      Toggle("Projected", isOn: binding).toggleStyle(StyleBoundaryCapturingToggle(probe: probe))
    }
    defer { h.shutdown() }
    let configuration = try #require(probe.toggle)
    #expect(configuration.$isOn.bindingSourceID == binding.bindingSourceID)
    #expect(configuration.$isOn.transaction.disablesAnimations)
    configuration.isOn = true
    #expect(value.value && value.writes == 1)
  }

  @Test func setA859OneInheritedStyleValueDoesNotShareStateBetweenControls() throws {
    // Hypothesis: preparing the same environment style value binds both controls to its last updated State box.
    let h = try harness(859) {
      VStack(alignment: .leading, spacing: 0) {
        Label("First") { Text("*") }
        Label("Second") { Text("*") }
      }.labelStyle(StyleBoundaryCountingLabel(prefix: "Shared"))
    }
    defer { h.shutdown() }
    try h.clickText("Shared count 0")
    #expect(h.frame.contains("Shared count 1"))
    #expect(h.frame.contains("Shared count 0"))
    try h.clickText("Shared count 0")
    let counters = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.compactMap(\.label)
      .filter { $0.hasPrefix("Shared count ") }.sorted()
    #expect(counters == ["Shared count 1", "Shared count 1"])
    #expect(
      h.frame.split(whereSeparator: \.isNewline).filter { $0.contains("Shared count 1") }.count
        == 2,
      "Rendered counters: \(h.frame)")
    #expect(!h.frame.contains("Shared count 0"))
  }

  @Test func setA860StyleEnvironmentPropertyRefreshesBeforeMakeBody() throws {
    // Hypothesis: erased style preparation retains an Environment wrapper from the previous enablement generation.
    let disabled = StyleBoundaryValue(false)
    let h = try harness(860) {
      Button("Environment") {}.buttonStyle(StyleBoundaryEnvironmentButton()).disabled(
        disabled.value)
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("wrapper:true configuration:true"))
    disabled.value = true
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("wrapper:false configuration:false"))
    disabled.value = false
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("wrapper:true configuration:true"))
  }

  @Test func setA861AlternativeStyleRoutesPublishOnlyThePlacedCandidate() throws {
    // Hypothesis: route claims from a rejected ViewThatFits candidate suppress the chosen route or publish duplicate hit regions.
    let value = StyleBoundaryValue(0)
    let h = try harness(861) {
      Slider("Alternatives", value: value.binding, in: 0...10)
        .sliderStyle(StyleBoundaryAlternativeSlider()).frame(width: 7, height: 1)
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("short"))
    #expect(!h.frame.contains("long candidate"))
    let routes = h.runLoop.latestSemanticSnapshot.interactionRegions.filter {
      $0.identity.description.contains("SliderTrack")
    }
    #expect(routes.count == 1)
    try h.clickText("short")
    #expect(value.value > 0)
    #expect(value.writes == 1)
  }

  @Test func setA862SliderPointerMappingUsesThePlacedCustomTrackWidth() throws {
    // Hypothesis: custom track input still divides by the eight-cell preferred width or ignores its leading inset.
    let value = StyleBoundaryValue(0)
    let h = try harness(862) {
      Slider("Placed track", value: value.binding, in: 0...10)
        .sliderStyle(StyleBoundaryWideSlider())
    }
    defer { h.shutdown() }
    try h.clickText("5")
    #expect(value.value == 5)
    try h.clickText("0")
    #expect(value.value == 0)
    try h.clickText("X")
    #expect(value.value == 10)
    #expect(value.writes == 3)
  }

  @Test func setA863DisabledStepperHalfConsumesItsPointerSequence() throws {
    // Hypothesis: the lower-bound decrement route declines input and lets its parent Stepper increment instead.
    let value = StyleBoundaryValue(0)
    let h = try harness(863) {
      Stepper("Bounded", value: value.binding, in: 0...2).stepperStyle(StyleBoundaryStepper())
    }
    defer { h.shutdown() }
    try h.clickText("Less")
    #expect(value.value == 0 && value.writes == 0)
    try h.clickText("More")
    #expect(value.value == 1 && value.writes == 1)
    try h.clickText("Less")
    #expect(value.value == 0 && value.writes == 2)
  }

  @Test func setA864PickerUsesCustomKeyboardDeltaInsteadOfBuiltInArrowPolicy() throws {
    // Hypothesis: a custom style's nonunit delta is ignored or the primitive still applies built-in arrow selection.
    let selection = StyleBoundaryValue(0)
    let h = try harness(864) {
      Picker("Custom keys", selection: selection.binding) {
        Text("Zero").tag(0)
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }.pickerStyle(StyleBoundaryPicker(mode: .jump))
    }
    defer { h.shutdown() }
    try h.focusText("Custom keys")
    try h.pressKey(.init(.arrowDown))
    #expect(selection.value == 0 && selection.writes == 0)
    try h.pressKey(.init(.character("j")))
    #expect(selection.value == 2 && selection.writes == 1)
  }

  @Test func setA865IdenticallyLabeledPickerOptionsKeepSeparateRoutes() throws {
    // Hypothesis: a custom option route derives its target from visible text and aliases another option with the same label.
    let selection = StyleBoundaryValue(1)
    let h = try harness(865) {
      Picker("Duplicates", selection: selection.binding) {
        Text("Same").tag(1)
        Text("Same").tag(2)
      }.pickerStyle(StyleBoundaryPicker(mode: .rows))
    }
    defer { h.shutdown() }
    try h.clickText("Same", chooseLast: true)
    #expect(selection.value == 2)
    try h.clickText("Same")
    #expect(selection.value == 1 && selection.writes == 2)
  }

  @Test func setA866AnOmittedPickerOptionRetainsItsAssistiveSelectionToken() throws {
    // Hypothesis: accessibility choices are harvested from custom style rows rather than all authored options.
    let selection = StyleBoundaryValue(1)
    let h = try harness(866) {
      Picker("Windowed choices", selection: selection.binding) {
        Text("Visible").tag(1)
        Text("Hidden choice").tag(2)
      }.pickerStyle(StyleBoundaryPicker(mode: .labelOnly))
    }
    defer { h.shutdown() }
    #expect(!h.frame.contains("Hidden choice"))
    let picker = try node("Windowed choices", in: h)
    let option = try #require(
      picker.control?.selection?.options.first { $0.label == "Hidden choice" })
    #expect(try send(.setValue(.text(option.id)), to: picker, in: h) == .accepted)
    #expect(selection.value == 2 && selection.writes == 1)
  }

  @Test func setA867ExplicitEmptyGroupBoxLabelStillHasAnAuthoredSlot() throws {
    // Hypothesis: optional GroupBox label presence is inferred from rendered emptiness instead of the selected initializer.
    let h = try harness(867) {
      VStack(alignment: .leading, spacing: 0) {
        GroupBox { Text("Unlabeled") }
        GroupBox(content: { Text("Explicit empty") }, label: { EmptyView() })
      }.groupBoxStyle(StyleBoundaryPresenceGroupBox())
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("absent Unlabeled"))
    #expect(h.frame.contains("present Explicit empty"))
  }

  @Test func setA868EmptyProgressLabelsDoNotCreatePresentConfigurationSlots() throws {
    // Hypothesis: ProgressView inherits GroupBox's initializer-based optional-slot rule and exposes explicit EmptyView labels.
    let h = try harness(868) {
      ProgressView(value: 0.5, label: { EmptyView() }, currentValueLabel: { EmptyView() })
        .progressViewStyle(StyleBoundaryProgressSlots())
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("label:false value:false"))
  }

  @Test func setA869TextFieldDistinguishesStringTitleAndAuthoredLabel() throws {
    // Hypothesis: style configuration treats a string accessibility title as a visible authored label or hides an explicit label.
    let h = try harness(869) {
      VStack(alignment: .leading, spacing: 0) {
        TextField("String title", text: .constant("First")).textFieldStyle(
          StyleBoundaryFieldMetadata())
        TextField(text: .constant("Second")) { Text("Visible label") }
          .textFieldStyle(StyleBoundaryFieldMetadata())
      }
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("shows:false First"))
    #expect(h.frame.contains("shows:true Second"))
  }

  @Test func setA870ProtectedFieldContentKeepsEditingUnderCustomChrome() throws {
    // Hypothesis: replacing text-field chrome turns the protected editing slot into inert display text.
    let text = StyleBoundaryValue("ab")
    let h = try harness(870) {
      TextField("Protected field", text: text.binding).textFieldStyle(StyleBoundaryPaddedField())
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("prefix ab_ suffix"))
    let field = try node("Protected field", in: h)
    #expect(try send(.focus, to: field, in: h) == .accepted)
    try h.pressKey(.init(.character("!")))
    #expect(text.value == "ab!" && text.writes == 1)
    // The focused field draws a caret after the inserted text, before the suffix.
    #expect(h.frame.contains("prefix ab!") && h.frame.contains("suffix"))
  }

  @Test func setA871OmittedControlGroupContentRetainsStateButNotLiveTargets() throws {
    // Hypothesis: a style's omitted retained slot either loses its dormant state or leaves its old actions published.
    let shown = StyleBoundaryValue(true)
    let h = try harness(871) {
      ControlGroup { StyleBoundaryCounter() }
        .controlGroupStyle(StyleBoundaryConditionalControlGroup(shown: shown.value))
    }
    defer { h.shutdown() }
    try h.clickText("Child 0")
    let old = try node("Child 1", in: h)
    shown.value = false
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Omitted"))
    #expect(
      !h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Child 1"
      })
    #expect(try send(.activate, to: old, in: h) != .accepted)
    shown.value = true
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Child 1"))
    try h.clickText("Child 1")
    #expect(h.frame.contains("Child 2"))
  }

  @Test func setA872PassiveGroupBoxDoesNotArchiveOmittedContentState() throws {
    // Hypothesis: retained-slot machinery unintentionally grants passive GroupBox the ControlGroup dormancy contract.
    let shown = StyleBoundaryValue(true)
    let h = try harness(872) {
      GroupBox { StyleBoundaryCounter() }.groupBoxStyle(
        StyleBoundaryConditionalGroupBox(shown: shown.value))
    }
    defer { h.shutdown() }
    try h.clickText("Child 0")
    #expect(h.frame.contains("Child 1"))
    shown.value = false
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Omitted"))
    shown.value = true
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("Child 0"))
    #expect(!h.frame.contains("Child 1"))
  }

  @Test func setA873CapturedTitleKeepsItsAuthoredEnvironmentOverride() throws {
    // Hypothesis: hosting a captured title beneath style-authored modifiers replaces the title's nearer authored environment.
    let h = try harness(873) {
      Label {
        StyleBoundaryTokenText().environment(\.styleBoundaryToken, "Authored")
      } icon: {
        Text("*")
      }
      .labelStyle(StyleBoundaryHostingLabel())
      .environment(\.styleBoundaryToken, "Outer")
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("token:Authored"))
    #expect(h.frame.contains("token:Host"))
    #expect(!h.frame.contains("token:Outer"))
  }

  @Test func setA874LinkPresentationCannotReplaceThePrimitiveDestination() throws {
    // Hypothesis: custom presentation merging drops the hyperlink target or installs a second style-owned activation.
    let probe = StyleBoundaryProbe()
    let h = try harness(874) {
      Link("Styled guide", destination: "https://example.invalid/guide?q=one")
        .linkStyle(StyleBoundaryLink())
        .openLinkAction(
          OpenLinkAction { destination in
            probe.destinations.append(destination.rawValue)
            return true
          })
    }
    defer { h.shutdown() }
    let link = try node("Styled guide", in: h)
    #expect(link.control?.value == .text("https://example.invalid/guide?q=one"))
    #expect(try send(.activate, to: link, in: h) == .accepted)
    #expect(probe.destinations == ["https://example.invalid/guide?q=one"])
  }

  @Test func setA875ProgressConfigurationNormalizesGeometryAndMotionPolicy() throws {
    // Hypothesis: a custom style receives raw out-of-range fraction/width or starts indeterminate work despite reduced motion.
    let probe = StyleBoundaryProbe()
    let h = try harness(875) {
      VStack {
        ProgressView(value: 2, total: 1, barWidth: 0).progressViewStyle(
          StyleBoundaryProgressProbe(probe: probe))
        ProgressView("Working", barWidth: -1).progressViewStyle(
          StyleBoundaryProgressProbe(probe: probe))
      }.environment(\.accessibilityReduceMotion, true)
    }
    defer { h.shutdown() }
    #expect(probe.progress.contains { $0.fractionCompleted == 1 && $0.barWidth == 1 })
    #expect(probe.progress.contains { $0.fractionCompleted == nil && $0.barWidth == 1 })
    #expect(
      probe.progress.allSatisfy { $0.accessibilityReduceMotion && $0.indeterminatePhase == 0 })
    #expect(h.activeTaskDescriptorCount == 0)
  }

  private func harness<V: View>(_ number: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAStyle\(number)"), size: .init(width: 72, height: 24),
      content: content)
  }

  private func node<V: View>(_ label: String, in h: StressRuntimeHarness<V>) throws
    -> AccessibilityNode
  {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label })
  }

  private func send<V: View>(
    _ action: AccessibilityAction, to node: AccessibilityNode, in h: StressRuntimeHarness<V>
  ) throws -> AccessibilityActionResult {
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: try #require(node.actionTarget), action: action))
    try h.render()
    return result
  }
}

@MainActor
private final class StyleBoundaryValue<Value> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}

@MainActor
private final class StyleBoundaryProbe {
  var baseProminence: ControlProminence?
  var bodyProminence: ControlProminence?
  var toggle: ToggleStyleConfiguration?
  var destinations: [String] = []
  var progress: [ProgressViewStyleConfiguration] = []
}

private struct StyleBoundaryFirstLabel: LabelStyle {
  var snapshotLabel: String { "same diagnostic label" }
  func makeBody(configuration: LabelStyleConfiguration) -> some View { Text("First body") }
}
private struct StyleBoundarySecondLabel: LabelStyle {
  var snapshotLabel: String { "same diagnostic label" }
  func makeBody(configuration: LabelStyleConfiguration) -> some View { Text("Second body") }
}
private struct StyleBoundaryCountingLabel: LabelStyle {
  var prefix: String
  @State private var count = 0
  @MainActor init(prefix: String) { self.prefix = prefix }
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.title
      Button("\(prefix) count \(count)") { count += 1 }
    }
  }
}
private struct StyleBoundaryPrefixLabel: LabelStyle {
  var prefix: String
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(prefix)
      configuration.title
    }
  }
}
private struct StyleBoundaryProminentButton: ButtonStyle {
  let probe: StyleBoundaryProbe
  func resolvedProminence(base: ControlProminence) -> ControlProminence {
    probe.baseProminence = base
    return .increased
  }
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    probe.bodyProminence = configuration.controlProminence
    return configuration.label
  }
}
private struct StyleBoundaryForgedEnabledButton: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    var copy = configuration
    copy.isEnabled = true
    return Text("Enabled copy \(copy.isEnabled)")
  }
}
private struct StyleBoundaryChromeButton: ButtonStyle {
  func makeBody(configuration: ButtonStyleConfiguration) -> some View { Text("Chrome only") }
}
private struct StyleBoundaryCapturingToggle: ToggleStyle {
  let probe: StyleBoundaryProbe
  func makeBody(configuration: ToggleStyleConfiguration) -> some View {
    probe.toggle = configuration
    return configuration.label
  }
}
private struct StyleBoundaryEnvironmentButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @MainActor init() {}
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    Text("wrapper:\(enabled) configuration:\(configuration.isEnabled)")
  }
}
private struct StyleBoundaryAlternativeSlider: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    ViewThatFits(in: .horizontal) {
      configuration.track { Text("long candidate") }
      configuration.track { Text("short") }
    }
  }
}
private struct StyleBoundaryWideSlider: SliderStyle {
  func makeBody(configuration: SliderStyleConfiguration) -> some View {
    configuration.track { Text("0123456789X") }.padding(.leading, 3)
  }
}
private struct StyleBoundaryStepper: StepperStyle {
  func makeBody(configuration: StepperStyleConfiguration) -> some View {
    HStack(spacing: 2) {
      configuration.decrement { Text("Less") }
      configuration.increment { Text("More") }
    }
  }
}
private struct StyleBoundaryPicker: PickerStyle {
  enum Mode: Sendable { case jump, rows, labelOnly }
  let mode: Mode
  func selectionDelta(for event: KeyEvent) -> Int? {
    mode == .jump && event == .character("j") ? 2 : nil
  }
  func makeBody(configuration: PickerStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.label
      if mode != .labelOnly {
        ForEach(0..<configuration.options.count) { index in
          configuration.options[index].route { Text(configuration.options[index].label) }
        }
      }
    }
  }
}
private struct StyleBoundaryPresenceGroupBox: GroupBoxStyle {
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(configuration.label == nil ? "absent" : "present")
      configuration.content
    }
  }
}
private struct StyleBoundaryProgressSlots: ProgressViewStyle {
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    Text("label:\(configuration.label != nil) value:\(configuration.currentValueLabel != nil)")
  }
}
private struct StyleBoundaryFieldMetadata: TextFieldStyle {
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text("shows:\(configuration.showsLabel)")
      configuration.fieldContent
    }
  }
}
private struct StyleBoundaryPaddedField: TextFieldStyle {
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text("prefix")
      configuration.fieldContent
      Text("suffix")
    }
  }
}
private struct StyleBoundaryCounter: View {
  @State private var count = 0
  var body: some View { Button("Child \(count)") { count += 1 } }
}
private struct StyleBoundaryConditionalControlGroup: ControlGroupStyle {
  var shown: Bool
  func makeBody(configuration: ControlGroupStyleConfiguration) -> some View {
    if shown { configuration.content } else { Text("Omitted") }
  }
}
private struct StyleBoundaryConditionalGroupBox: GroupBoxStyle {
  var shown: Bool
  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    if shown { configuration.content } else { Text("Omitted") }
  }
}
private enum StyleBoundaryTokenKey: EnvironmentKey { static let defaultValue = "Default" }
extension EnvironmentValues {
  fileprivate var styleBoundaryToken: String {
    get { self[StyleBoundaryTokenKey.self] }
    set { self[StyleBoundaryTokenKey.self] = newValue }
  }
}
private struct StyleBoundaryTokenText: View {
  @Environment(\.styleBoundaryToken) private var token
  var body: some View { Text("token:\(token)") }
}
private struct StyleBoundaryHostingLabel: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.title
      StyleBoundaryTokenText()
    }
    .environment(\.styleBoundaryToken, "Host")
  }
}
private struct StyleBoundaryLink: LinkStyle {
  func resolvePresentation(for configuration: LinkStyleConfiguration) -> LinkStylePresentation {
    .init(foregroundStyle: AnyShapeStyle(.red), emphasis: .italic, underline: .hidden, opacity: 0.6)
  }
}
private struct StyleBoundaryProgressProbe: ProgressViewStyle {
  let probe: StyleBoundaryProbe
  func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
    probe.progress.append(configuration)
    return Text("Progress config")
  }
}
