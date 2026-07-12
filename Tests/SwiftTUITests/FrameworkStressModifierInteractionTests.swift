import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI modifier interaction stress behavior", .serialized)
struct FrameworkStressModifierInteractionTests {}

private enum ModifierInteractionStringKey: EnvironmentKey {
  static let defaultValue = "default"
}

extension EnvironmentValues {
  fileprivate var modifierInteractionString: String {
    get { self[ModifierInteractionStringKey.self] }
    set { self[ModifierInteractionStringKey.self] = newValue }
  }
}

private enum ModifierInteractionIntPreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

@MainActor
private final class ModifierInteractionProbe {
  var events: [String] = []
}

private struct ModifierInteractionEnvironmentPrefix: ViewModifier {
  @Environment(\.modifierInteractionString) private var value

  func body(content: Content) -> some View {
    HStack(spacing: 1) {
      Text(value)
      content
    }
  }
}

private struct ModifierInteractionEnabledPrefix: ViewModifier {
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    HStack(spacing: 1) {
      Text(isEnabled ? "enabled" : "disabled")
      content
    }
  }
}

private struct ModifierInteractionFocusEffectPrefix: ViewModifier {
  @Environment(\.isFocusEffectEnabled) private var isFocusEffectEnabled

  func body(content: Content) -> some View {
    HStack(spacing: 1) {
      Text(isFocusEffectEnabled ? "focus-effect" : "no-focus-effect")
      content
    }
  }
}

private struct ModifierInteractionButtonStyle: ButtonStyle {
  let marker: String

  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    HStack(spacing: 1) {
      Text(marker)
      Text(configuration.isEnabled ? "enabled" : "disabled")
      Text(configuration.controlProminence == .increased ? "increased" : "standard")
      Text(configuration.buttonBorderShape == .roundedRectangle ? "rounded" : "automatic")
      configuration.label
    }
  }
}

@MainActor
private func verifyModifierInteractionRetainedMatchesFresh<Content: View>(
  _ name: String,
  generations: Range<Int> = 0..<18,
  @ViewBuilder content: (Int) -> Content
) {
  let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
  let identity = testIdentity(name)
  for generation in generations {
    let root = content(generation)
    let retained = renderer.render(
      root,
      context: .init(identity: identity, invalidatedIdentities: [identity])
    )
    let fresh = DefaultRenderer().render(root, context: .init(identity: identity))
    #expect(retained.rasterSurface == fresh.rasterSurface)
    #expect(retained.semanticSnapshot == fresh.semanticSnapshot)
  }
}

private func modifierInteractionText(_ snapshot: RenderSnapshot) -> String {
  snapshot.rasterSurface.lines.joined(separator: "\n")
}

private func modifierInteractionDescendant(
  _ node: ResolvedNode,
  containingText marker: String
) -> ResolvedNode? {
  if case .text(let value) = node.drawPayload, value.contains(marker) {
    return node
  }
  for child in node.children {
    if let match = modifierInteractionDescendant(child, containingText: marker) {
      return match
    }
  }
  return nil
}

extension FrameworkStressModifierInteractionTests {
  @Test("stress modifier interaction 001 environment writer order reaches modifier reader")
  func modifierInteraction001EnvironmentWriterOrderReachesModifierReader() {
    // Hypothesis: moving an environment writer across a composed modifier can leave the modifier
    // reading the writer from its previous side of the boundary.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-001")
            .modifier(ModifierInteractionEnvironmentPrefix())
            .environment(\.modifierInteractionString, "value-\(generation)")
        } else {
          Text("target-001")
            .environment(\.modifierInteractionString, "value-\(generation)")
            .modifier(ModifierInteractionEnvironmentPrefix())
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction001") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 002 disabled and explicit enablement honor authored order")
  func modifierInteraction002DisabledAndExplicitEnablementHonorAuthoredOrder() {
    // Hypothesis: the isEnabled transform installed by disabled can be replayed after a later
    // explicit writer when their structural modifier order reverses.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-002")
            .modifier(ModifierInteractionEnabledPrefix())
            .disabled(true)
            .environment(\.isEnabled, true)
        } else {
          Text("target-002")
            .modifier(ModifierInteractionEnabledPrefix())
            .environment(\.isEnabled, true)
            .disabled(true)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction002") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 003 focus effect writer order reaches modifier reader")
  func modifierInteraction003FocusEffectWriterOrderReachesModifierReader() {
    // Hypothesis: focusEffectDisabled and a direct environment writer can collapse to one stale
    // snapshot when their order alternates around a stable reader.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-003")
            .modifier(ModifierInteractionFocusEffectPrefix())
            .focusEffectDisabled()
            .environment(\.isFocusEffectEnabled, true)
        } else {
          Text("target-003")
            .modifier(ModifierInteractionFocusEffectPrefix())
            .environment(\.isFocusEffectEnabled, true)
            .focusEffectDisabled()
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction003") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 004 stacked accessibility labels keep current precedence")
  func modifierInteraction004StackedAccessibilityLabelsKeepCurrentPrecedence() {
    // Hypothesis: same-field semantic metadata can retain the former outer label when two label
    // modifiers exchange order without changing their stable content.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-004")
            .accessibilityLabel("first-\(generation)")
            .accessibilityLabel("second-\(generation)")
        } else {
          Text("target-004")
            .accessibilityLabel("second-\(generation)")
            .accessibilityLabel("first-\(generation)")
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction004") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 005 hidden and role metadata survive order reversal")
  func modifierInteraction005HiddenAndRoleMetadataSurviveOrderReversal() {
    // Hypothesis: reversing two distinct semantic modifiers can replace the whole metadata value,
    // dropping either the current hidden bit or role instead of merging both.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-005")
            .accessibilityRole(.heading(level: 2))
            .accessibilityHidden(!generation.isMultiple(of: 4))
        } else {
          Text("target-005")
            .accessibilityHidden(!generation.isMultiple(of: 3))
            .accessibilityRole(.link)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction005") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 006 focus and hit testing metadata merge in either order")
  func modifierInteraction006FocusAndHitTestingMetadataMergeInEitherOrder() {
    // Hypothesis: allowsHitTesting and focusable can overwrite one another's interaction fields
    // after their modifier nodes exchange structural positions.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-006")
            .focusable(interactions: .edit)
            .allowsHitTesting(!generation.isMultiple(of: 4))
        } else {
          Text("target-006")
            .allowsHitTesting(!generation.isMultiple(of: 3))
            .focusable(interactions: .activate)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction006") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 007 opacity churn preserves accessibility metadata")
  func modifierInteraction007OpacityChurnPreservesAccessibilityMetadata() {
    // Hypothesis: moving a draw-metadata modifier across semantic metadata can reuse the visible
    // subtree while leaving its accessibility label one generation behind.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-007")
            .opacity(Double(generation % 5) / 4)
            .accessibilityLabel("label-\(generation)")
        } else {
          Text("target-007")
            .accessibilityLabel("label-\(generation)")
            .opacity(Double(generation % 5) / 4)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction007") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 008 foreground and opacity order publish current style")
  func modifierInteraction008ForegroundAndOpacityOrderPublishCurrentStyle() {
    // Hypothesis: environment-backed foreground style and node-local opacity can be restored from
    // different generations when their retained wrappers reverse order.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-008")
            .foregroundStyle(generation.isMultiple(of: 4) ? Color.red : Color.blue)
            .opacity(Double((generation % 3) + 1) / 3)
        } else {
          Text("target-008")
            .opacity(Double((generation % 3) + 1) / 3)
            .foregroundStyle(generation.isMultiple(of: 3) ? Color.green : Color.yellow)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction008") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 009 button style and disabled order stay coherent")
  func modifierInteraction009ButtonStyleAndDisabledOrderStayCoherent() {
    // Hypothesis: a custom style body and the control action can observe different isEnabled
    // snapshots when buttonStyle crosses disabled during retained reconciliation.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Button("target-009") {}
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
            .disabled(!generation.isMultiple(of: 4))
        } else {
          Button("target-009") {}
            .disabled(!generation.isMultiple(of: 3))
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction009") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 010 prominence and border shape update as one style tuple")
  func modifierInteraction010ProminenceAndBorderShapeUpdateAsOneStyleTuple() {
    // Hypothesis: independent style environment fields can be combined from adjacent generations
    // when their writers reverse around a retained custom button style.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Button("target-010") {}
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
            .controlProminence(.increased)
            .buttonBorderShape(.automatic)
        } else {
          Button("target-010") {}
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
            .buttonBorderShape(.roundedRectangle)
            .controlProminence(.standard)
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction010") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 011 custom button style preserves authored accessibility")
  func modifierInteraction011CustomButtonStylePreservesAuthoredAccessibility() {
    // Hypothesis: rebuilding style-generated children after modifier reordering can strand the
    // accessibility label on the style wrapper instead of the live control semantic node.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Button("target-011") {}
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
            .accessibilityLabel("accessible-\(generation)")
        } else {
          Button("target-011") {}
            .accessibilityLabel("accessible-\(generation)")
            .buttonStyle(ModifierInteractionButtonStyle(marker: "style-\(generation)"))
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction011") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 012 preference overlay follows its environment boundary")
  func modifierInteraction012PreferenceOverlayFollowsEnvironmentBoundary() {
    // Hypothesis: an overlayPreferenceValue transform can keep the environment from the former
    // side of a writer when the writer crosses the late-preference modifier.
    struct Overlay: View {
      let value: Int
      @Environment(\.modifierInteractionString) private var environmentValue

      var body: some View {
        Text("overlay-012 \(environmentValue) \(value)")
      }
    }

    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("source-012")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Overlay(value: value)
            }
            .environment(\.modifierInteractionString, "env-\(generation)")
        } else {
          Text("source-012")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .environment(\.modifierInteractionString, "env-\(generation)")
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Overlay(value: value)
            }
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction012") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 013 preference background and opacity stay synchronized")
  func modifierInteraction013PreferenceBackgroundAndOpacityStaySynchronized() {
    // Hypothesis: a late preference background can bypass the current opacity wrapper after the
    // two modifiers exchange order, mixing current text with prior compositing metadata.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("source-013")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .backgroundPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("background-013-\(value)")
            }
            .opacity(Double((generation % 4) + 1) / 4)
        } else {
          Text("source-013")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .opacity(Double((generation % 4) + 1) / 4)
            .backgroundPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("background-013-\(value)")
            }
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction013") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 014 preference transform preserves semantic visibility")
  func modifierInteraction014PreferenceTransformPreservesSemanticVisibility() {
    // Hypothesis: a preference transform and accessibilityHidden can each reuse the same child
    // while only one publishes current metadata after their order reverses.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("source-014")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: 1)
            .transformPreference(ModifierInteractionIntPreferenceKey.self) { $0 += generation }
            .accessibilityHidden(!generation.isMultiple(of: 4))
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("overlay-014-\(value)")
            }
        } else {
          Text("source-014")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: 1)
            .accessibilityHidden(!generation.isMultiple(of: 3))
            .transformPreference(ModifierInteractionIntPreferenceKey.self) { $0 += generation }
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("overlay-014-\(value)")
            }
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction014") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 015 preference publication survives disabled order churn")
  func modifierInteraction015PreferencePublicationSurvivesDisabledOrderChurn() {
    // Hypothesis: disabled's environment transform can cause preference reduction to reuse a
    // pre-transform subtree and publish the preceding generation's value.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("source-015")
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .disabled(!generation.isMultiple(of: 4))
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("overlay-015-\(value)")
            }
        } else {
          Text("source-015")
            .disabled(!generation.isMultiple(of: 3))
            .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
            .overlayPreferenceValue(ModifierInteractionIntPreferenceKey.self) { value in
              Text("overlay-015-\(value)")
            }
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction015") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 016 transaction and disabled order remain generation coherent")
  func modifierInteraction016TransactionAndDisabledOrderRemainGenerationCoherent() throws {
    // Hypothesis: transaction and environment-transform nodes can reuse independently, pairing a
    // current enabled snapshot with the previous animation policy after their order changes.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-016-\(generation)")
            .modifier(ModifierInteractionEnabledPrefix())
            .transaction { $0.disablesAnimations = generation.isMultiple(of: 4) }
            .disabled(!generation.isMultiple(of: 3))
        } else {
          Text("target-016-\(generation)")
            .modifier(ModifierInteractionEnabledPrefix())
            .disabled(!generation.isMultiple(of: 3))
            .transaction { $0.disablesAnimations = generation.isMultiple(of: 4) }
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ModifierInteraction016")
    for generation in 0..<18 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: identity))
      let retainedNode = try #require(
        modifierInteractionDescendant(retained.resolvedTree, containingText: "target-016")
      )
      let freshNode = try #require(
        modifierInteractionDescendant(fresh.resolvedTree, containingText: "target-016")
      )
      #expect(retainedNode.transactionSnapshot == freshNode.transactionSnapshot)
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }

  @Test("stress modifier interaction 017 transaction churn preserves accessibility metadata")
  func modifierInteraction017TransactionChurnPreservesAccessibilityMetadata() {
    // Hypothesis: moving transaction across semantic metadata can refresh the resolved child while
    // the semantic extractor continues to publish the old label.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-017")
            .transaction { $0.disablesAnimations = generation.isMultiple(of: 4) }
            .accessibilityLabel("label-017-\(generation)")
        } else {
          Text("target-017")
            .accessibilityLabel("label-017-\(generation)")
            .transaction { $0.disablesAnimations = generation.isMultiple(of: 3) }
        }
      }
    }

    verifyModifierInteractionRetainedMatchesFresh("ModifierInteraction017") { generation in
      Root(generation: generation)
    }
  }

  @Test("stress modifier interaction 018 value animation follows environment writer reordering")
  func modifierInteraction018ValueAnimationFollowsEnvironmentWriterReordering() throws {
    // Hypothesis: a value-animation baseline can stay attached to the previous environment-writer
    // position, applying current visible text with stale transaction intent.
    struct Root: View {
      let generation: Int

      @ViewBuilder var body: some View {
        if generation.isMultiple(of: 2) {
          Text("target-018-\(generation)")
            .modifier(ModifierInteractionEnvironmentPrefix())
            .animation(.linear(duration: .milliseconds(100)), value: generation)
            .environment(\.modifierInteractionString, "env-\(generation)")
        } else {
          Text("target-018-\(generation)")
            .modifier(ModifierInteractionEnvironmentPrefix())
            .environment(\.modifierInteractionString, "env-\(generation)")
            .animation(nil, value: generation)
        }
      }
    }

    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("ModifierInteraction018")
    for generation in 0..<18 {
      let root = Root(generation: generation)
      let retained = renderer.render(
        root,
        context: .init(identity: identity, invalidatedIdentities: [identity])
      )
      let fresh = DefaultRenderer().render(root, context: .init(identity: identity))
      let retainedNode = try #require(
        modifierInteractionDescendant(retained.resolvedTree, containingText: "target-018")
      )
      let freshNode = try #require(
        modifierInteractionDescendant(fresh.resolvedTree, containingText: "target-018")
      )
      #expect(retainedNode.transactionSnapshot == freshNode.transactionSnapshot)
      #expect(retained.rasterSurface == fresh.rasterSurface)
    }
  }
}

@MainActor
private struct ModifierInteraction019Fixture: View {
  let probe: ModifierInteractionProbe
  @State private var generation = 0
  @State private var isVisible = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle target 019") {
        if !isVisible {
          generation += 1
        }
        isVisible.toggle()
      }
      if isVisible {
        if generation.isMultiple(of: 2) {
          Text("target-019")
            .onAppear { probe.events.append("A-\(generation)") }
            .onAppear { probe.events.append("B-\(generation)") }
        } else {
          Text("target-019")
            .onAppear { probe.events.append("B-\(generation)") }
            .onAppear { probe.events.append("A-\(generation)") }
        }
      }
    }
  }
}

@MainActor
private struct ModifierInteraction020Fixture: View {
  let probe: ModifierInteractionProbe
  @State private var generation = 0
  @State private var isVisible = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle target 020") {
        if !isVisible {
          generation += 1
        }
        isVisible.toggle()
      }
      if isVisible {
        if generation.isMultiple(of: 2) {
          Text("target-020")
            .onDisappear { probe.events.append("A-\(generation)") }
            .onDisappear { probe.events.append("B-\(generation)") }
        } else {
          Text("target-020")
            .onDisappear { probe.events.append("B-\(generation)") }
            .onDisappear { probe.events.append("A-\(generation)") }
        }
      }
    }
  }
}

@MainActor
private struct ModifierInteraction021Fixture: View {
  let probe: ModifierInteractionProbe
  @State private var generation = 0
  @State private var isVisible = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle target 021") {
        generation += 1
        isVisible.toggle()
      }
      if isVisible {
        if generation.isMultiple(of: 2) {
          Text("target-021")
            .onAppear { probe.events.append("appear-\(generation)") }
            .accessibilityHidden(true)
        } else {
          Text("target-021")
            .accessibilityHidden(true)
            .onAppear { probe.events.append("appear-\(generation)") }
        }
      }
    }
  }
}

@MainActor
private struct ModifierInteraction022Fixture: View {
  let probe: ModifierInteractionProbe
  @State private var generation = 0
  @State private var isVisible = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle target 022") {
        generation += 1
        isVisible.toggle()
      }
      if isVisible {
        if generation.isMultiple(of: 2) {
          Text("target-022")
            .onAppear { probe.events.append("appear-\(generation)") }
            .allowsHitTesting(false)
        } else {
          Text("target-022")
            .allowsHitTesting(false)
            .onAppear { probe.events.append("appear-\(generation)") }
        }
      }
    }
  }
}

@MainActor
private struct ModifierInteraction023Fixture: View {
  let probe: ModifierInteractionProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance target 023") { generation += 1 }
      Text("target-023-\(generation)")
        .preference(key: ModifierInteractionIntPreferenceKey.self, value: generation)
        .onPreferenceChange(ModifierInteractionIntPreferenceKey.self) { value in
          probe.events.append("preference-\(value)")
        }
        .onChange(of: generation) { _, value in
          probe.events.append("change-\(value)")
        }
        .opacity(Double((generation % 3) + 1) / 3)
        .accessibilityLabel("label-023-\(generation)")
    }
  }
}

@MainActor
private struct ModifierInteraction024Fixture: View {
  static let focusIdentity = testIdentity("ModifierInteraction024", "Focus")

  let probe: ModifierInteractionProbe
  @State private var generation = 0

  var body: some View {
    Panel(id: "modifier-interaction-024-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Text("focus-024")
          .focusable()
          .id(Self.focusIdentity)
        Text("generation-024-\(generation)")
      }
    }
    .keyCommand("Command 024", key: .character("k"), modifiers: .ctrl) {
      generation += 1
      probe.events.append("command-\(generation)")
    }
    .opacity(generation.isMultiple(of: 2) ? 1 : 0.5)
    .accessibilityLabel("panel-024-\(generation)")
  }
}

@MainActor
private struct ModifierInteraction025Fixture: View {
  static let focusIdentity = testIdentity("ModifierInteraction025", "Focus")

  let probe: ModifierInteractionProbe
  @State private var generation = 0
  @State private var commandEnabled = true

  var body: some View {
    let currentCommandEnabled = commandEnabled
    Panel(id: "modifier-interaction-025-panel") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Toggle command 025") { commandEnabled.toggle() }
        Text("focus-025")
          .focusable()
          .id(Self.focusIdentity)
        Text("generation-025-\(generation)")
      }
    }
    .keyCommand(
      "Command 025",
      key: .character("m"),
      modifiers: .ctrl,
      isEnabled: commandEnabled
    ) {
      generation += 1
      probe.events.append("command-\(generation)")
    }
    .transaction { $0.disablesAnimations = !currentCommandEnabled }
    .opacity(commandEnabled ? 1 : 0.75)
  }
}

extension FrameworkStressModifierInteractionTests {
  @Test("stress modifier interaction 019 stacked onAppear order follows current branch")
  func modifierInteraction019StackedOnAppearOrderFollowsCurrentBranch() throws {
    // Hypothesis: stacked appear handlers can keep their former ordinals when the modifier order
    // reverses between successive owner lifetimes.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction019"),
      size: .init(width: 50, height: 6)
    ) {
      ModifierInteraction019Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...10 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle target 019")
      let expected =
        generation.isMultiple(of: 2)
        ? ["A-\(generation)", "B-\(generation)"]
        : ["B-\(generation)", "A-\(generation)"]
      #expect(probe.events == expected)
      _ = try harness.clickText("Toggle target 019")
    }
  }

  @Test("stress modifier interaction 020 stacked onDisappear order follows current branch")
  func modifierInteraction020StackedOnDisappearOrderFollowsCurrentBranch() throws {
    // Hypothesis: stacked disappear handlers can dispatch the prior lifetime's order after the
    // stable branch is removed and recreated with reversed modifiers.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction020"),
      size: .init(width: 50, height: 6)
    ) {
      ModifierInteraction020Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 0..<10 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle target 020")
      let expected =
        generation.isMultiple(of: 2)
        ? ["A-\(generation)", "B-\(generation)"]
        : ["B-\(generation)", "A-\(generation)"]
      #expect(probe.events == expected)
      _ = try harness.clickText("Toggle target 020")
    }
  }

  @Test("stress modifier interaction 021 accessibility hiding does not suppress lifecycle")
  func modifierInteraction021AccessibilityHidingDoesNotSuppressLifecycle() throws {
    // Hypothesis: moving accessibilityHidden across onAppear can cause semantic pruning to erase
    // the lifecycle descriptor for a newly inserted owner.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction021"),
      size: .init(width: 50, height: 6)
    ) {
      ModifierInteraction021Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle target 021")
      if !generation.isMultiple(of: 2) {
        #expect(probe.events == ["appear-\(generation)"])
        #expect(
          !harness.runLoop.latestSemanticSnapshot.accessibilityNodes.contains {
            $0.label == "target-021"
          }
        )
      } else {
        #expect(probe.events.isEmpty)
      }
    }
  }

  @Test("stress modifier interaction 022 hit testing suppression does not suppress lifecycle")
  func modifierInteraction022HitTestingSuppressionDoesNotSuppressLifecycle() throws {
    // Hypothesis: moving allowsHitTesting(false) across onAppear can incorrectly prune lifecycle
    // intake together with interaction regions.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction022"),
      size: .init(width: 50, height: 6)
    ) {
      ModifierInteraction022Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle target 022")
      if !generation.isMultiple(of: 2) {
        #expect(probe.events == ["appear-\(generation)"])
      } else {
        #expect(probe.events.isEmpty)
      }
    }
  }

  @Test("stress modifier interaction 023 onChange and preference observation stay paired")
  func modifierInteraction023OnChangeAndPreferenceObservationStayPaired() throws {
    // Hypothesis: simultaneous draw and semantic churn can let a retained subtree update its
    // preference observer while skipping its sibling onChange registration, or vice versa.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction023"),
      size: .init(width: 56, height: 6)
    ) {
      ModifierInteraction023Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Advance target 023")
      #expect(Set(probe.events) == Set(["change-\(generation)", "preference-\(generation)"]))
      #expect(probe.events.count == 2)
      #expect(harness.preferenceObservationRegistrationCount == 1)
    }
  }

  @Test("stress modifier interaction 024 command remains live through draw and semantic churn")
  func modifierInteraction024CommandRemainsLiveThroughDrawAndSemanticChurn() throws {
    // Hypothesis: retained command intake can be skipped when only later opacity and accessibility
    // modifiers change, leaving the focused scope with a stale command closure.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction024"),
      size: .init(width: 58, height: 7)
    ) {
      ModifierInteraction024Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(ModifierInteraction024Fixture.focusIdentity)
    for generation in 1...14 {
      let frame = try harness.pressKey(KeyPress(.character("k"), modifiers: .ctrl))
      #expect(frame.contains("generation-024-\(generation)"))
      #expect(probe.events.last == "command-\(generation)")
      #expect(harness.keyCommandRegistrationCount == 1)
    }
  }

  @Test("stress modifier interaction 025 command enablement survives transaction churn")
  func modifierInteraction025CommandEnablementSurvivesTransactionChurn() throws {
    // Hypothesis: explicit command enablement can lag behind transaction and opacity changes on the
    // same retained ActionScope, either firing while disabled or staying inert after reenablement.
    let probe = ModifierInteractionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModifierInteraction025"),
      size: .init(width: 58, height: 8)
    ) {
      ModifierInteraction025Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.focus(ModifierInteraction025Fixture.focusIdentity)
    var expectedGeneration = 0
    for _ in 1...10 {
      _ = try harness.clickText("Toggle command 025")
      _ = try harness.focus(ModifierInteraction025Fixture.focusIdentity)
      var frame = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
      #expect(frame.contains("generation-025-\(expectedGeneration)"))

      _ = try harness.clickText("Toggle command 025")
      _ = try harness.focus(ModifierInteraction025Fixture.focusIdentity)
      frame = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
      expectedGeneration += 1
      #expect(frame.contains("generation-025-\(expectedGeneration)"))
      #expect(probe.events.last == "command-\(expectedGeneration)")
      #expect(harness.keyCommandRegistrationCount == 1)
    }
  }
}
