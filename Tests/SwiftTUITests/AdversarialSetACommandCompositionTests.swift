@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetACommandCompositionTests {
  @Test func setA801RebindingAShortcutRetiresItsPreviousKey() throws {
    // Hypothesis: a scope's merged command table retains the old key when one declaration rebinds.
    let model = SetACommandModel()
    let h = try make("801") {
      Text("Command target").focusable().panel(id: "commands")
        .keyCommand("Rebound", key: .functionKey(model.number), modifiers: []) {
          model.events.append("command")
        }
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.functionKey(5)))
    try #require(model.events == ["command"])
    model.number = 6
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.functionKey(5)))
    #expect(model.events == ["command"])
    try h.pressKey(.init(.functionKey(6)))
    #expect(model.events == ["command", "command"])
    #expect(h.keyCommandRegistrationCount == 1)
  }

  @Test func setA802RefreshingOneCommandPreservesItsScopesOtherBinding() throws {
    // Hypothesis: replacing one contribution publishes its partial table over another live binding.
    let model = SetACommandModel()
    let h = try make("802") {
      let revision = model.number
      Text("Two bindings").focusable().panel(id: "commands")
        .keyCommand("First", key: .functionKey(3), modifiers: []) {
          model.events.append("first")
        }
        .keyCommand("Second \(revision)", key: .functionKey(4), modifiers: []) {
          model.events.append("second:\(revision)")
        }
    }
    defer { h.shutdown() }
    model.number = 9
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.functionKey(3)))
    try h.pressKey(.init(.functionKey(4)))
    #expect(model.events == ["first", "second:9"])
    #expect(h.keyCommandRegistrationCount == 2)
  }

  @Test func setA803SameScopeDuplicateBindingUsesTheOuterRegistration() throws {
    // Hypothesis: snapshot merging reverses same-scope replacement order or runs both registrations.
    let model = SetACommandModel()
    let h = try make("803") {
      Text("Duplicate binding").focusable().panel(id: "commands")
        .keyCommand("Inner", key: .functionKey(7), modifiers: []) {
          model.events.append("inner")
        }
        .keyCommand("Outer", key: .functionKey(7), modifiers: []) {
          model.events.append("outer")
        }
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.functionKey(7)))
    try h.pressKey(.init(.functionKey(7)))
    #expect(model.events == ["outer", "outer"])
    #expect(h.keyCommandRegistrationCount == 1)
  }

  @Test func setA804ScopeCommandPrecedesAFocusedLocalInterceptor() throws {
    // Hypothesis: local interception consumes a modified key before the scope command arbitration.
    let model = SetACommandModel()
    let h = try make("804") {
      Text("Intercepted target").focusable()
        .onKeyPress(.character("k"), modifiers: .ctrl) { _ in
          model.events.append("local")
          return .handled
        }
        .panel(id: "commands")
        .keyCommand("Scope wins", key: .character("k"), modifiers: .ctrl) {
          model.events.append("scope")
        }
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.character("k"), modifiers: .ctrl))
    #expect(model.events == ["scope"])
  }

  @Test func setA805RejectedModifierlessCommandLeavesTabTraversalAvailable() throws {
    // Hypothesis: an ignored modifierless registration still reserves Tab before built-in traversal.
    let model = SetACommandModel()
    let h = try make("805") {
      VStack {
        Button("First target") { model.events.append("first") }
        Button("Second target") { model.events.append("second") }
      }
      .panel(id: "commands")
      .keyCommand("Forbidden Tab", key: .tab, modifiers: []) {
        model.events.append("tab")
      }
    }
    defer { h.shutdown() }
    try h.focusText("First target")
    try h.pressKey(.init(.tab))
    try h.pressKey(.init(.return))
    #expect(model.events == ["second"])
    #expect(h.keyCommandRegistrationCount == 0)
  }

  @Test func setA806CommandBackstopPublishesUntrackedWritesInItsOwnFrame() throws {
    // Hypothesis: command dispatch omits its backstop when an action changes nonreactive model data.
    let model = SetACommandModel()
    let h = try make("806") {
      Text("Untracked value \(model.number)").focusable().panel(id: "commands")
        .keyCommand("Increment", key: .functionKey(8), modifiers: []) { model.number += 1 }
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Untracked value 5"))
    try h.pressKey(.init(.functionKey(8)))
    #expect(model.number == 6)
    #expect(h.frame.contains("Untracked value 6"), "\(h.frame)")
  }

  @Test func setA807HandledAncestorInterceptionStopsFocusedButtonActivation() throws {
    // Hypothesis: a handled ancestor Return still falls through to the focused primitive's action.
    let model = SetACommandModel()
    let h = try make("807") {
      VStack {
        Button("Protected action") { model.events.append("button") }
      }
      .onKeyPress(.return) { _ in
        model.events.append("ancestor")
        return .handled
      }
    }
    defer { h.shutdown() }
    try h.focusText("Protected action")
    try h.pressKey(.init(.return))
    #expect(model.events == ["ancestor"])
    try h.clickText("Protected action")
    #expect(model.events == ["ancestor", "button"])
  }

  @Test func setA808IgnoredStackedInterceptorsRunBeforeOnePrimitiveActivation() throws {
    // Hypothesis: same-node handler composition reverses outer precedence or duplicates default action.
    let model = SetACommandModel()
    let h = try make("808") {
      Button("Ordered action") { model.events.append("button") }
        .onKeyPress(.return) { _ in
          model.events.append("inner")
          return .ignored
        }
        .onKeyPress(.return) { _ in
          model.events.append("outer")
          return .ignored
        }
    }
    defer { h.shutdown() }
    try h.focusText("Ordered action")
    try h.pressKey(.init(.return))
    #expect(model.events == ["outer", "inner", "button"])
  }

  @Test func setA809DirectionalCommandLeavesModifiedArrowsForTheirExactHandler() throws {
    // Hypothesis: directional command matching discards modifiers and swallows a distinct key envelope.
    let model = SetACommandModel()
    let h = try make("809") {
      Text("Directional target").focusable()
        .onKeyPress(.arrowLeft, modifiers: .shift) { _ in
          model.events.append("shift-left")
          return .handled
        }
        .onMoveCommand { direction in
          model.events.append(direction == .left ? "left" : "other")
          return .handled
        }
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.arrowLeft))
    try h.pressKey(.init(.arrowLeft, modifiers: .shift))
    #expect(model.events == ["left", "shift-left"])
  }

  @Test func setA810ExitInterceptionCanChangeItsDecisionWhileAMenuStaysOpen() throws {
    // Hypothesis: an open menu either outranks authored Exit handling or freezes its handled decision.
    let model = SetACommandModel()
    let h = try make("810") {
      Menu("Exit guarded menu") {
        Button("Exit guarded item") { model.events.append("item") }
          .onExitCommand {
            model.events.append("exit")
            return model.flag ? .handled : .ignored
          }
      }
    }
    defer { h.shutdown() }
    try h.clickText("Exit guarded menu")
    try h.focusText("Exit guarded item")
    try h.pressKey(.init(.escape))
    try #require(model.events == ["exit"])
    #expect(h.frame.contains("Exit guarded item"))
    model.flag = false
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.escape))
    #expect(model.events == ["exit", "exit"])
    #expect(!h.frame.contains("Exit guarded item"))
  }

  @Test func setA811DuplicateToolbarTitlesKeepDistinctActionOccurrences() throws {
    // Hypothesis: toolbar action routing keys by display title and aliases repeated item occurrences.
    let model = SetACommandModel()
    let h = try make("811") {
      Panel(id: "tools") {
        Text("Tool source")
          .toolbarItem(.init(title: "Shared tool") { model.events.append("first") })
          .toolbarItem(.init(title: "Shared tool") { model.events.append("second") })
      }.toolbar()
    }
    defer { h.shutdown() }
    let buttons = nodes("Shared tool", in: h)
    try #require(buttons.count == 2)
    for button in buttons.sorted(by: { $0.rect.origin.x < $1.rect.origin.x }) {
      try h.click(
        Point(
          x: Double(button.rect.origin.x) + 0.5,
          y: Double(button.rect.origin.y) + 0.5))
    }
    #expect(model.events == ["first", "second"])
  }

  @Test func setA812DisabledToolbarPrefixCannotShiftAReusedActionsOwner() throws {
    // Hypothesis: strip refresh zips enabled action identities with a list containing a disabled prefix.
    let model = SetACommandModel()
    let h = try make("812") {
      let revision = model.number
      Panel(id: "tools") {
        Text("Tool source")
          .toolbarItem(
            .init(title: "Prefix tool", isEnabled: model.flag) {
              model.events.append("prefix:\(revision)")
            }
          )
          .toolbarItem(
            .init(title: "Surviving tool") {
              model.events.append("survivor:\(revision)")
            })
      }.toolbar()
    }
    defer { h.shutdown() }
    try h.clickText("Surviving tool")
    try #require(model.events == ["survivor:5"])
    model.flag = false
    try h.renderAfterExternalMutation()
    model.number = 8
    try h.renderAfterExternalMutation()
    try h.clickText("Surviving tool")
    #expect(model.events == ["survivor:5", "survivor:8"])
    #expect(nodes("Prefix tool", in: h).first?.isEnabled == false)
  }

  @Test func setA813RemovingTheLastToolbarItemRetiresItsWorkingAction() throws {
    // Hypothesis: an empty toolbar keeps its last cached strip's action registry entries live.
    let model = SetACommandModel()
    let h = try make("813") {
      Panel(id: "tools") {
        if model.flag {
          Text("Tool source").toolbarItem(
            .init(title: "Departing tool") {
              model.events.append("tool")
            })
        } else {
          Text("No tools")
        }
      }.toolbar()
    }
    defer { h.shutdown() }
    let button = try #require(nodes("Departing tool", in: h).first)
    let action = button.actionIdentity ?? button.identity
    try h.clickText("Departing tool")
    try #require(model.events == ["tool"])
    model.flag = false
    try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("Departing tool"))
    #expect(!h.runLoop.localActionRegistry.hasHandler(identity: action))
    #expect(!h.runLoop.focusTracker.focusRegions.contains { $0.identity == button.identity })
  }

  @Test func setA814NestedToolbarsAbsorbOnlyTheirOwnContributions() throws {
    // Hypothesis: an inner toolbar's consumed preference re-bubbles and installs a duplicate outer item.
    let model = SetACommandModel()
    let h = try make("814") {
      Panel(id: "outer") {
        VStack(spacing: 1) {
          Text("Outer source").toolbarItem(
            .init(title: "Outer tool") {
              model.events.append("outer")
            })
          Panel(id: "inner") {
            Text("Inner source").toolbarItem(
              .init(title: "Inner tool") {
                model.events.append("inner")
              })
          }.toolbar().frame(height: 5)
        }
      }.toolbar()
    }
    defer { h.shutdown() }
    #expect(nodes("Outer tool", in: h).count == 1)
    #expect(nodes("Inner tool", in: h).count == 1)
    try h.clickText("Inner tool")
    try h.clickText("Outer tool")
    #expect(model.events == ["inner", "outer"])
  }

  @Test func setA815LateGeometryToolbarContributionRefreshesItsActionCapture() throws {
    // Hypothesis: late preference reconciliation updates toolbar paint but not its closure publication.
    let model = SetACommandModel()
    let h = try make("815") {
      let revision = model.number
      Panel(id: "tools") {
        GeometryReader { _ in
          Text("Late source \(revision)").toolbarItem(
            .init(title: "Late tool") {
              model.events.append("late:\(revision)")
            })
        }.frame(height: 2)
      }.toolbar()
    }
    defer { h.shutdown() }
    try h.clickText("Late tool")
    try #require(model.events == ["late:5"])
    model.number = 11
    try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Late source 11"))
    try h.clickText("Late tool")
    #expect(model.events == ["late:5", "late:11"])
  }

  @Test func setA816DiscardedLayoutCandidateCannotPublishAToolbarAction() throws {
    // Hypothesis: toolbar preference publication includes an unplaced candidate's late contribution.
    let model = SetACommandModel()
    let h = try make("816") {
      Panel(id: "tools") {
        ViewThatFits {
          GeometryReader { _ in
            Text("Wide candidate").toolbarItem(
              .init(title: "Rejected tool") {
                model.events.append("rejected")
              })
          }.frame(width: 30, height: 1)
          Text("Fits").toolbarItem(
            .init(title: "Chosen tool") {
              model.events.append("chosen")
            })
        }.frame(width: 8, height: 1)
      }.toolbar()
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Fits"))
    #expect(nodes("Rejected tool", in: h).isEmpty)
    #expect(!h.frame.contains("Rejected tool"))
    try h.clickText("Chosen tool")
    #expect(model.events == ["chosen"])
  }

  @Test func setA817DuplicatePaletteNamesRemainIndependentlyActivatable() throws {
    // Hypothesis: default palette selection deduplicates equal names instead of contribution IDs.
    let model = SetACommandModel()
    model.entries = [.init(1, "Identical command"), .init(2, "Identical command")]
    let h = try palette("817", model)
    defer { h.shutdown() }
    try #require(nodes("Identical command", in: h).count == 2)
    try h.pressKey(.init(.arrowDown))
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:2"])
    #expect(!model.presented)
  }

  @Test func setA818RenamingASelectedPaletteContributionPreservesItsSelection() throws {
    // Hypothesis: mutable command display text becomes the selected row's effective identity.
    let model = SetACommandModel()
    let h = try palette("818", model)
    defer { h.shutdown() }
    try h.pressKey(.init(.arrowDown))
    try #require(h.frame.contains("> Bravo command"))
    model.entries[1].name = "Renamed command"
    try h.renderAfterExternalMutation()
    #expect(h.frame.contains("> Renamed command"), "\(h.frame)")
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:2"])
  }

  @Test func setA819PaletteSearchDoesNotMatchDescriptionOnlyText() throws {
    // Hypothesis: filtering searches the rendered row rather than the documented command-name field.
    let model = SetACommandModel()
    model.entries = [.init(1, "Unrelated command", description: "needle")]
    let h = try palette("819", model)
    defer { h.shutdown() }
    try #require(h.frame.contains("Unrelated command"))
    try h.paste("needle")
    #expect(h.frame.contains("No matches."), "\(h.frame)")
    try h.pressKey(.init(.return))
    #expect(model.events.isEmpty && model.presented)
  }

  @Test func setA820FilteringOutTheSelectionChoosesTheFirstSurvivingContribution() throws {
    // Hypothesis: selection retains an out-of-filter index and activates a different hidden command.
    let model = SetACommandModel()
    let h = try palette("820", model)
    defer { h.shutdown() }
    try h.pressKey(.init(.arrowDown))
    try #require(h.frame.contains("> Bravo command"))
    try h.paste("Alpha")
    try #require(h.frame.contains("> Alpha command"), "\(h.frame)")
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:1"])
  }

  @Test func setA821DisabledSelectedPaletteCommandCannotDismissOnReturn() throws {
    // Hypothesis: the default Return path dismisses before checking the selected contribution's policy.
    let model = SetACommandModel()
    model.entries[0].enabled = false
    let h = try palette("821", model)
    defer { h.shutdown() }
    try #require(h.frame.contains("> Alpha command"))
    try h.pressKey(.init(.return))
    #expect(model.events.isEmpty && model.presented)
    #expect(h.frame.contains("> Alpha command") && h.frame.contains("Bravo command"))
    try h.pressKey(.init(.arrowDown))
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:2"] && !model.presented)
  }

  @Test func setA822ReopeningPaletteClearsItsPreviousFilterQuery() throws {
    // Hypothesis: retained presentation content carries its previous query into a new activation.
    let model = SetACommandModel()
    let h = try palette("822", model)
    defer { h.shutdown() }
    try h.paste("Bravo")
    try #require(!h.frame.contains("Alpha command"))
    try h.pressKey(.init(.escape))
    try #require(!model.presented)
    try h.clickText("Open command palette")
    #expect(h.frame.contains("Alpha command") && h.frame.contains("Bravo command"), "\(h.frame)")
    try h.clickText("Alpha command")
    #expect(model.events == ["command:1"])
  }

  @Test func setA823FuzzyPaletteRankingUsesLeadingAndInteriorGapCosts() throws {
    // Hypothesis: case folding or gap scoring orders a loose earlier contribution before a tight match.
    let model = SetACommandModel()
    model.entries = [.init(1, "A---B"), .init(2, "xAB"), .init(3, "AB")]
    let h = try palette("823", model)
    defer { h.shutdown() }
    try h.paste("ab")
    let rows = h.frame.split(whereSeparator: \.isNewline).map(String.init)
    let order = rows.compactMap { row in
      model.entries.first { row.contains($0.name) }?.id
    }
    #expect(order == [3, 2, 1], "\(h.frame)")
    // Filtering preserves a still-matching selection, so explicitly move to the ranked first row.
    try h.pressKey(.init(.arrowUp))
    try h.pressKey(.init(.arrowUp))
    try #require(h.frame.contains("> AB"), "\(h.frame)")
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:3"])
  }

  @Test func setA824RemovingSelectedPaletteCommandRetiresItsPublishedTarget() throws {
    // Hypothesis: a live contribution removal keeps its old target and selected key in the palette body.
    let model = SetACommandModel()
    let h = try palette("824", model)
    defer { h.shutdown() }
    try h.pressKey(.init(.arrowDown))
    try #require(h.frame.contains("> Bravo command"))
    let removed = try #require(nodes("Bravo command", in: h).first)
    let target = try #require(removed.actionTarget)
    model.entries.remove(at: 1)
    try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("Bravo command"))
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .activate)) == .staleTarget)
    #expect(model.events.isEmpty)
    try h.pressKey(.init(.return))
    #expect(model.events == ["command:1"])
  }

  @Test func setA825ClosedNestedPaletteStillAbsorbsItsOwnCommands() throws {
    // Hypothesis: command absorption depends on presentation visibility and leaks dormant inner commands.
    let model = SetACommandModel()
    let h = try make("825") {
      Panel(id: "outer") {
        Panel(id: "inner") { Text("Inner source") }
          .paletteCommand(name: "Inner private command") { model.events.append("inner") }
          .paletteSheet("Inner palette", isPresented: .constant(false))
      }
      .paletteCommand(name: "Outer public command") { model.events.append("outer") }
      .paletteSheet("Outer palette", isPresented: model.presentedBinding)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("Outer public command"))
    #expect(!h.frame.contains("Inner private command"))
    try h.pressKey(.init(.return))
    #expect(model.events == ["outer"])
  }

  private func make<V: View>(_ name: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetACommandComposition", name),
      size: .init(width: 76, height: 26), content: content)
  }

  private func palette(_ name: String, _ model: SetACommandModel) throws
    -> StressRuntimeHarness<SetACommandPaletteFixture>
  {
    try make(name) { SetACommandPaletteFixture(model: model) }
  }

  private func nodes<V: View>(_ title: String, in h: StressRuntimeHarness<V>) -> [AccessibilityNode]
  {
    h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
      $0.role == .button && $0.label == title
    }
  }
}

@MainActor
private final class SetACommandModel {
  var events: [String] = []
  var number = 5
  var flag = true
  var presented = true
  var entries = [SetACommandEntry(1, "Alpha command"), SetACommandEntry(2, "Bravo command")]

  var presentedBinding: Binding<Bool> {
    Binding(get: { self.presented }, set: { self.presented = $0 })
  }
}

private struct SetACommandEntry: Identifiable, Sendable {
  let id: Int
  var name: String
  var description: String?
  var enabled = true

  init(_ id: Int, _ name: String, description: String? = nil) {
    self.id = id
    self.name = name
    self.description = description
  }
}

@MainActor
private struct SetACommandPaletteFixture: View {
  let model: SetACommandModel

  var body: some View {
    Panel(id: "palette-source") {
      VStack {
        Button("Open command palette") { model.presented = true }
        ForEach(model.entries) { entry in
          Panel(id: entry.id) { EmptyView() }
            .paletteCommand(
              name: entry.name, description: entry.description, isEnabled: entry.enabled
            ) { model.events.append("command:\(entry.id)") }
        }
      }
    }
    .paletteSheet("Set A commands", isPresented: model.presentedBinding)
  }
}
