import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
@testable import View

@MainActor
@Suite
struct SceneCommandsCompositionTests {
  @Test("scene-level and view-level commands coexist in the registry")
  func sceneLevelAndViewLevelCommandsCoexist() throws {
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s"),
          group: "Document"
        ) {}
    }
    .commands {
      CommandItem(id: "quit", title: "Quit", key: .ctrl("q"), group: "App") {}
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    let selection = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    // Hotkey registry carries both tiers.
    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.contains { $0.commandID == "quit" })
    #expect(bindings.contains { $0.commandID == "save" })

    // Preference reduction at the root carries both tiers as well.
    let commandIDs = collectCommandIDs(
      in: selection.resolvedTree,
      rootIdentity: selection.rootIdentity
    )
    #expect(commandIDs.contains("quit"))
    #expect(commandIDs.contains("save"))
  }

  @Test(
    "scene-level and view-level commands with the same id both reduce into the preference value")
  func sceneLevelAndViewLevelCommandsOnSameIDBothReduce() throws {
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
        .command(
          id: "quit",
          title: "Close Document",
          key: .ctrl("q"),
          group: "Document"
        ) {}
    }
    .commands {
      CommandItem(id: "quit", title: "Quit", key: .ctrl("q"), group: "App") {}
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    let selection = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    // The preference reduction is an append-only flat list at this
    // stage; both entries with id `quit` must be present.
    // Innermost-wins dedup is a Stage 3/4 read-time concern.
    let registrations = collectCommandRegistrations(in: selection.resolvedTree)
    let quitEntries = registrations.filter { $0.command.id == "quit" }
    #expect(quitEntries.count == 2)

    // The two entries carry distinct titles, one from each tier.
    let titles = Set(quitEntries.map(\.command.title))
    #expect(titles.contains("Close Document"))
    #expect(titles.contains("Quit"))

    // Likewise, the hotkey registry has two bindings for the same
    // key — dispatch order is innermost-first, but the raw registry
    // accepts both.
    let bindings = hotkeyRegistry.registeredBindings()
    let quitBindings = bindings.filter { $0.commandID == "quit" }
    #expect(quitBindings.count == 2)
  }
}

@MainActor
private func collectCommandRegistrations(
  in node: ResolvedNode
) -> [CommandRegistration] {
  var registrations: [CommandRegistration] = []
  walk(node, collecting: &registrations)
  return registrations
}

@MainActor
private func walk(
  _ node: ResolvedNode,
  collecting registrations: inout [CommandRegistration]
) {
  let value = node.preferenceValues[CommandPreferenceKey.self]
  registrations.append(contentsOf: value.registrations)
  for child in node.children {
    walk(child, collecting: &registrations)
  }
}
