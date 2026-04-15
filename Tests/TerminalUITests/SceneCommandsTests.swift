import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
@testable import View

@MainActor
@Suite
struct SceneCommandsTests {
  @Test("scene-level command registers a hotkey binding on the root view")
  func sceneLevelCommandRegistersHotkey() throws {
    final class Capture {
      var fired = false
    }
    let capture = Capture()
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
    }
    .commands {
      CommandItem(id: "quit", title: "Quit", key: .ctrl("q"), group: "App") {
        capture.fired = true
      }
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    _ = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.contains { $0.commandID == "quit" })
    #expect(bindings.contains { $0.key == .ctrl("q") })
    #expect(bindings.contains { $0.label == "Quit" })
    #expect(bindings.contains { $0.group == "App" })

    // Dispatching the keypress through the registry fires the action.
    #expect(hotkeyRegistry.dispatch(.ctrl("q")))
    #expect(capture.fired)
  }

  @Test("chained .commands applications register all items on the root view")
  func chainedCommandsApplicationsComposeRegistrations() throws {
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
    }
    .commands {
      CommandItem(id: "a", title: "A", key: .ctrl("a")) {}
    }
    .commands {
      CommandItem(id: "b", title: "B", key: .ctrl("b")) {}
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    let selection = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    // Both hotkeys are registered on the same root view.
    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.contains { $0.commandID == "a" })
    #expect(bindings.contains { $0.commandID == "b" })

    // Both items also surface in the command preference value via the
    // same reduction path as view-level `.command(…)`.
    let rootIdentity = selection.rootIdentity
    let commandIDs = collectCommandIDs(
      in: selection.resolvedTree,
      rootIdentity: rootIdentity
    )
    #expect(commandIDs.contains("a"))
    #expect(commandIDs.contains("b"))
  }

  @Test("conditional scene commands honor builder optionality")
  func conditionalSceneCommandsHonorBuilderOptionality() throws {
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
    }
    .commands {
      if false {
        CommandItem(id: "hidden", title: "Hidden", key: .ctrl("h")) {}
      } else {
        CommandItem(id: "shown", title: "Shown", key: .ctrl("s")) {}
      }
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    _ = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    let commandIDs = hotkeyRegistry.registeredBindings().compactMap(\.commandID)
    #expect(commandIDs.contains("shown"))
    #expect(!commandIDs.contains("hidden"))
  }

  @Test("scene-level command dispatches through the registry")
  func sceneLevelCommandDispatchesThroughTheRegistry() throws {
    final class Capture {
      var firedCount = 0
    }
    let capture = Capture()
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
    }
    .commands {
      CommandItem(id: "increment", title: "Increment", key: .ctrl("i")) {
        capture.firedCount += 1
      }
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    _ = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    #expect(hotkeyRegistry.dispatch(.ctrl("i")))
    #expect(hotkeyRegistry.dispatch(.ctrl("i")))
    #expect(capture.firedCount == 2)
  }

  @Test("empty .commands { } leaves the root view untouched by injection")
  func emptyCommandsBlockLeavesRootViewUntouched() throws {
    let hotkeyRegistry = HotkeyRegistry()

    let scene = WindowGroup(id: "primary") {
      Text("Root")
    }
    .commands {
      // intentionally empty
    }

    var visitor = SceneCommandsCaptureVisitor(hotkeyRegistry: hotkeyRegistry)
    _ = try #require(
      withFirstWindowSceneConfiguration(
        in: scene,
        visitor: &visitor
      )
    )

    // An empty `.commands` block still resolves cleanly, with no extra
    // bindings registered.
    #expect(hotkeyRegistry.registeredBindings().isEmpty)
  }
}

// MARK: - Shared test helpers

@MainActor
struct SceneCommandsCaptureSelection {
  let rootIdentity: Identity
  let resolvedTree: ResolvedNode
}

@MainActor
struct SceneCommandsCaptureVisitor: WindowSceneConfigurationVisitor {
  let hotkeyRegistry: HotkeyRegistry

  mutating func visit<Content: View>(
    descriptor _: TerminalUISceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<SceneCommandsCaptureSelection> {
    var context = ResolveContext(identity: configuration.rootIdentity)
    context.hotkeyRegistry = hotkeyRegistry

    let artifacts = DefaultRenderer().render(
      configuration.makeScopedRootView(),
      context: context,
      proposal: .init(width: 40, height: 10)
    )

    return .finish(
      SceneCommandsCaptureSelection(
        rootIdentity: configuration.rootIdentity,
        resolvedTree: artifacts.resolvedTree
      )
    )
  }
}

/// Recursively walks the resolved tree collecting every command id
/// that has been merged into its `CommandPreferenceKey` value. Used by
/// the scene-command tests to assert that the scene-level injection
/// writes through the same preference reduction path as view-level
/// `.command(...)`.
@MainActor
func collectCommandIDs(
  in node: ResolvedNode,
  rootIdentity _: Identity
) -> Set<String> {
  var ids: Set<String> = []
  walk(node, collecting: &ids)
  return ids
}

@MainActor
private func walk(_ node: ResolvedNode, collecting ids: inout Set<String>) {
  let value = node.preferenceValues[CommandPreferenceKey.self]
  for registration in value.registrations {
    ids.insert(registration.command.id)
  }
  for child in node.children {
    walk(child, collecting: &ids)
  }
}
