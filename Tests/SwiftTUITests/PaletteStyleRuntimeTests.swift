import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct PaletteStyleRuntimeTests {
  @Test(
    "palette styles preserve activation, dismissal, focus, and command lifetime",
    arguments: 0..<3, [false, true])
  func interaction(styleIndex: Int, selective: Bool) throws {
    let probe = PaletteJourneyProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteJourney"), size: .init(width: 64, height: 24),
      selectiveEvaluation: selective
    ) { PaletteJourney(probe: probe, styleIndex: styleIndex) }
    defer { harness.shutdown() }
    for cycle in 1...2 {
      _ = try harness.clickText("Open palette")
      #expect(harness.frame.contains("Run command"))
      #expect(
        !harness.runLoop.focusTracker.focusRegions.contains { $0.identity == paletteLaunchID })
      if cycle == 1 {
        _ = try harness.clickText("Run command")
        if styleIndex == 2 {
          #expect(probe.activations == 0)
          #expect(harness.frame.contains("Run command"))
          let invoke = try harness.focusIdentity(forText: "Invoke")
          _ = try harness.focus(invoke)
          _ = try harness.pressKey(KeyPress(.return))
        }
      } else {
        if styleIndex != 0 {
          let invoke = try harness.focusIdentity(forText: "Invoke")
          _ = try harness.focus(invoke)
        }
        _ = try harness.pressKey(KeyPress(.return))
      }
      #expect(probe.activations == cycle)
      #expect(!harness.frame.contains("Run command"))
      #expect(probe.dismissals == cycle)
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == paletteLaunchID)
      #expect(
        !harness.runLoop.localPointerHandlerRegistry.snapshot().keys.contains {
          $0.identity.components.contains("PaletteCommand")
        })
      probe.configuration?.commands.first?.perform()
      probe.configuration?.dismiss()
      #expect(probe.activations == cycle)
      #expect(probe.dismissals == cycle)
    }
    _ = try harness.clickText("Open palette")
    if styleIndex == 0 {
      _ = try harness.pressKey(KeyPress(.escape))
    } else {
      _ = try harness.clickText("Cancel")
      #expect(probe.appearances == 3)
      #expect(probe.disappearances == 3)
    }
    #expect(probe.dismissals == 3)
    #expect(probe.activations == 2)
  }

  @Test("changing style-visible enabled data cannot activate a disabled contribution")
  func disabledAndExpiredCommands() throws {
    let probe = PaletteJourneyProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DisabledPalette"), size: .init(width: 64, height: 24)
    ) { PaletteJourney(probe: probe, styleIndex: 1) }
    _ = try harness.clickText("Open palette")
    var disabled = try #require(probe.configuration?.commands.last)
    disabled.isEnabled = true
    disabled.perform()
    _ = try harness.render()
    #expect(probe.activations == 0)
    #expect(harness.frame.contains("Run command"))
    _ = try harness.clickText("Disabled command")
    #expect(probe.activations == 0)
    #expect(probe.dismissals == 0)
    let retained = try #require(probe.configuration)
    _ = try harness.pressKey(KeyPress(.escape))
    harness.shutdown()
    retained.commands.first?.perform()
    retained.dismiss()
    #expect(probe.activations == 0)
  }

  @Test("retained palette configuration cannot reactivate a departed source")
  func departedSource() throws {
    let probe = PaletteJourneyProbe()
    defer { probe.configuration = nil }
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("PaletteSourceLifetime"))
    _ = renderer.render(
      Panel(id: "commands") { EmptyView() }
        .paletteCommand(name: "Run", action: { probe.activations += 1 })
        .paletteSheet("Commands", isPresented: .constant(true))
        .paletteStyle(PaletteJourneyStyle(probe: probe)),
      context: context,
      proposal: .init(width: 64, height: 24))
    weak let owner = probe.owner
    #expect(owner != nil)
    let retained = try #require(probe.configuration)
    let removed = renderer.render(
      Text("Removed"), context: context, proposal: .init(width: 64, height: 24))
    #expect(!removed.rasterSurface.lines.joined().contains("Run"))
    #expect(owner.flatMap { renderer.viewGraph.nodeForViewNodeID($0.viewNodeID) } == nil)
    retained.commands.first?.perform()
    retained.dismiss()
    #expect(probe.activations == 0)
  }

  @Test("duplicate command routes report misuse and activate only once")
  func duplicateRoutes() throws {
    let fixture = DefaultRenderer().render(
      Panel(id: "commands") { EmptyView() }
        .paletteCommand(name: "Run command", action: {})
        .paletteSheet("Commands", isPresented: .constant(true))
        .paletteStyle(PaletteJourneyStyle(probe: .init(), duplicateRoutes: true)),
      context: .init(identity: testIdentity("PaletteRouteMisuse")),
      proposal: .init(width: 64, height: 24))
    #expect(
      fixture.diagnostics.runtime.issues.filter { $0.code == "style.duplicateRoute" }.count == 1)
    let probe = PaletteJourneyProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DuplicatePaletteRoutes"), size: .init(width: 64, height: 24)
    ) { PaletteJourney(probe: probe, styleIndex: 3) }
    defer { harness.shutdown() }
    _ = try harness.clickText("Open palette")
    _ = try harness.clickText("Run command")
    #expect(probe.activations == 1)
    #expect(probe.dismissals == 1)
  }

  @Test("identical command labels remain independently keyboard-selectable")
  func duplicateLabels() throws {
    let probe = PaletteSelectionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DuplicatePaletteLabels"), size: .init(width: 64, height: 24)
    ) {
      Panel(id: "commands") { EmptyView() }
        .paletteCommand(name: "Same", description: "Same", action: { probe.selected = 1 })
        .paletteCommand(name: "Same", description: "Same", action: { probe.selected = 2 })
        .paletteSheet("Commands", isPresented: .constant(true))
    }
    defer { harness.shutdown() }
    _ = try harness.pressKey(KeyPress(.arrowDown))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(probe.selected == 2)
  }

  @Test("rename and reorder preserve selection by contribution identity", arguments: [false, true])
  func liveCommandSelection(selective: Bool) throws {
    let probe = PaletteSelectionProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LivePaletteSelection"), size: .init(width: 64, height: 24),
      selectiveEvaluation: selective
    ) { PaletteSelectionJourney(probe: probe) }
    defer { harness.shutdown() }
    _ = try harness.pressKey(KeyPress(.arrowDown))
    #expect(harness.frame.contains("> Command 2"))
    let label = try #require(probe.label)
    label.wrappedValue = "Renamed"
    _ = try harness.render()
    #expect(harness.frame.contains("> Renamed 2"))
    let items = try #require(probe.items)
    items.wrappedValue = [3, 2, 1]
    _ = try harness.render()
    #expect(harness.frame.contains("> Renamed 2"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(probe.selected == 2)
    items.wrappedValue = [3, 1]
    _ = try harness.render()
    #expect(harness.frame.contains("> Renamed 3"))
  }

  @Test("default fuzzy ranking preserves leading and interior gaps and case folding")
  func fuzzyRanking() throws {
    let names = ["xxac", "a---c", "abC", "AC", "only a"]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteRanking"), size: .init(width: 64, height: 24)
    ) { PaletteRankingJourney(names: names) }
    defer { harness.shutdown() }
    _ = try harness.paste("aC")
    let rows = harness.frame.split(whereSeparator: \.isNewline).map(String.init)
    let ranked = rows.compactMap { row in names.first { row.contains($0) } }
    #expect(ranked == ["AC", "abC", "xxac", "a---c"], "\(harness.frame)")
    _ = try harness.paste("zzz")
    #expect(harness.frame.contains("No matches."))
  }

  @Test("default selection keeps twelve rows visible and supports tab navigation")
  func visibleWindow() throws {
    let names = (0..<20).map { "Command \($0 < 10 ? "0" : "")\($0)" }
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PaletteWindow"), size: .init(width: 64, height: 30)
    ) { PaletteRankingJourney(names: names) }
    defer { harness.shutdown() }
    #expect(names.filter { harness.frame.contains($0) }.count == 12)
    #expect(harness.frame.contains("> Command 00"))
    for _ in 0..<19 { _ = try harness.pressKey(KeyPress(.tab)) }
    #expect(harness.frame.contains("> Command 19"))
    #expect(names.filter { harness.frame.contains($0) }.count == 12)
    #expect(!harness.frame.contains("Command 07"))
    _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
    #expect(harness.frame.contains("> Command 18"))
    _ = try harness.pressKey(KeyPress(.arrowUp))
    #expect(harness.frame.contains("> Command 17"))
  }
}

private let paletteLaunchID = testIdentity("PaletteLauncher")

@MainActor
private final class PaletteJourneyProbe {
  weak var owner: SwiftTUICore.ViewNode?
  var configuration: PaletteStyleConfiguration?
  var activations = 0
  var dismissals = 0
  var appearances = 0
  var disappearances = 0
}

private struct PaletteJourney: View {
  let probe: PaletteJourneyProbe
  let styleIndex: Int
  @State private var presented = false
  @State private var counter = 0
  var body: some View {
    Button("Open palette") { presented = true }.id(paletteLaunchID)
      .panel(id: "commands")
      .paletteCommand(
        name: "Run command",
        action: {
          counter += 1
          probe.activations = counter
        }
      )
      .paletteCommand(
        name: "Disabled command", isEnabled: false,
        action: {
          probe.activations += 100
        }
      )
      .paletteSheet("Commands", isPresented: $presented, onDismiss: { probe.dismissals += 1 })
      .paletteStyle(
        styleIndex == 0
          ? AnyPaletteStyle.automatic
          : .init(
            PaletteJourneyStyle(
              probe: probe, omitRoutes: styleIndex == 2, duplicateRoutes: styleIndex == 3)))
  }
}

private struct PaletteJourneyStyle: PaletteStyle {
  let probe: PaletteJourneyProbe
  var omitRoutes = false
  var duplicateRoutes = false
  func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    let _ = probe.configuration = configuration
    let _ = probe.owner = ViewNodeContext.current
    return VStack(alignment: .leading, spacing: 0) {
      Text(configuration.title)
      ForEach(configuration.commands) { command in
        if omitRoutes {
          Text(command.name)
        } else {
          command.route { Text(command.name) }
          if duplicateRoutes { command.route { Text("Repeated \(command.name)") } }
        }
      }
      Button("Invoke") { configuration.commands.first?.perform() }
      Button("Cancel") { configuration.dismiss() }
    }
    .frame(minWidth: 44, alignment: .leading)
    .onAppear { probe.appearances += 1 }
    .onDisappear { probe.disappearances += 1 }
  }
}

@MainActor
private final class PaletteSelectionProbe {
  var selected = 0
  var label: Binding<String>?
  var items: Binding<[Int]>?
}

private struct PaletteSelectionJourney: View {
  let probe: PaletteSelectionProbe
  @State private var label = "Command"
  @State private var items = [1, 2, 3]
  var body: some View {
    Panel(id: "commands") {
      ForEach(items, id: \.self) { item in
        Panel(id: item) { EmptyView() }
          .paletteCommand(name: "\(label) \(item)", action: { probe.selected = item })
      }
    }
    .paletteSheet("Commands", isPresented: .constant(true))
    .onAppear {
      probe.label = $label
      probe.items = $items
    }
  }
}

private struct PaletteRankingJourney: View {
  let names: [String]
  var body: some View {
    Panel(id: "commands") {
      ForEach(Array(names.enumerated()), id: \.offset) { pair in
        Panel(id: pair.offset) { EmptyView() }
          .paletteCommand(name: pair.element, action: {})
      }
    }.paletteSheet("Commands", isPresented: .constant(true))
  }
}
