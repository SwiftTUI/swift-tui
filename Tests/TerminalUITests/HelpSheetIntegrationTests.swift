import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
@testable import View

@MainActor
@Suite
struct HelpSheetIntegrationTests {
  @Test(".helpSheet initially dismissed renders nothing extra")
  func helpSheetInitiallyDismissed() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s")
        ) {}
        .helpSheet(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 10)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    // Body text from the primary content renders.
    #expect(surface.contains("Body"))
    // The sheet has not been triggered, so the "Help" header and
    // dismiss hint must not be present.
    #expect(!surface.contains("Press Esc"))
  }

  @Test("?-triggered help sheet surfaces registered commands when presented")
  func helpSheetDispatchShowsRegisteredCommands() {
    // Use the package-internal `_helpSheet(isPresented:)` seam to
    // flip the presentation state directly. The default
    // `.helpSheet()` entry point registers `?` on the hotkey registry
    // and flips an internal `@State` flag on dispatch; that full
    // round-trip is exercised by the explicit registration check
    // below. The sheet's content-rendering path is tested here with
    // a caller-owned binding so we don't need to invalidate and
    // re-resolve the containing view between renders.
    let view = Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s"),
        group: "Document"
      ) {}
      ._helpSheet(isPresented: .constant(true))

    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 12)
    )
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Help"))
    #expect(surface.contains("Save"))
    #expect(surface.contains("Document"))

    // Separately verify the default entry point still registers the
    // trigger hotkey at the registry.
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(identity: testIdentity("Trigger"))
    context.hotkeyRegistry = hotkeyRegistry
    _ = DefaultRenderer().render(
      Text("Body").helpSheet(),
      context: context,
      proposal: .init(width: 40, height: 5)
    )
    #expect(
      hotkeyRegistry.registeredBindings().contains {
        $0.key == KeyPress(.character("?"))
      }
    )
  }

  @Test("help sheet groups commands by Command.group with Other last")
  func helpSheetGroupsCommandsByGroup() {
    let view = Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s"),
        group: "Document"
      ) {}
      .command(
        id: "loose",
        title: "Loose End",
        key: .ctrl("l")
      ) {}
      .command(
        id: "palette",
        title: "Palette",
        key: .ctrl("p"),
        group: "Session"
      ) {}
      ._helpSheet(isPresented: .constant(true))

    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 60, height: 20)
    )
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Document"))
    #expect(surface.contains("Session"))
    #expect(surface.contains("Other"))
    #expect(surface.contains("Save"))
    #expect(surface.contains("Palette"))
    #expect(surface.contains("Loose End"))
  }

  @Test("dispatching the trigger key flips the internal presentation state")
  func dispatchingTriggerKeyFlipsPresentationState() {
    // Round-trip test: using an external `isPresented` binding lets
    // us assert that the trigger handler, when fired via the real
    // ``HotkeyRegistry.dispatch`` path, toggles the author-owned
    // state. The matching production path uses an internal @State
    // that persists across renders via the same handler shape.
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(identity: testIdentity("Root"))
    context.hotkeyRegistry = hotkeyRegistry

    var isPresented = false
    let binding = Binding<Bool>(
      mainActorGet: { isPresented },
      set: { isPresented = $0 }
    )

    _ = DefaultRenderer().render(
      Text("Body")._helpSheet(isPresented: binding),
      context: context,
      proposal: .init(width: 40, height: 5)
    )

    // The trigger key is registered and dispatching it flips the
    // binding. Handler order does not matter here — there is only
    // this one handler on the registry.
    #expect(hotkeyRegistry.dispatch(KeyPress(.character("?"))))
    #expect(isPresented == true)
  }

  @Test("help sheet accepts a custom trigger key")
  func helpSheetAcceptsCustomTriggerKey() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(identity: testIdentity("Root"))
    context.hotkeyRegistry = hotkeyRegistry

    let triggerKey = KeyPress(.character("?"), modifiers: .ctrl)
    let view = Text("Body")
      .helpSheet(triggeredBy: triggerKey)

    _ = DefaultRenderer().render(
      view,
      context: context,
      proposal: .init(width: 40, height: 12)
    )

    // Verify the custom trigger is carried on a registered binding
    // and that the default `?` is not.
    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.contains { $0.key == triggerKey })
    #expect(!bindings.contains { $0.key == KeyPress(.character("?")) })
  }

  @Test(".help and .helpSheet compose and read the same command data")
  func helpAndHelpSheetCompose() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(identity: testIdentity("Root"))
    context.hotkeyRegistry = hotkeyRegistry

    // Dormant sheet path: strip renders the token, sheet is hidden.
    let dormant = Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .help()
      .helpSheet()
    let dormantArtifacts = DefaultRenderer().render(
      dormant,
      context: context,
      proposal: .init(width: 40, height: 10)
    )
    let dormantSurface = dormantArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(dormantSurface.contains("Save"))
    #expect(dormantSurface.contains("[^S]"))
    // Help sheet header should NOT appear while dormant.
    #expect(!dormantSurface.contains("Press Esc"))

    // And the sheet-on path — both surfaces read the same registered
    // command.
    let presented = Text("Body")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {}
      .help()
      ._helpSheet(isPresented: .constant(true))
    let presentedArtifacts = DefaultRenderer().render(
      presented,
      context: context,
      proposal: .init(width: 40, height: 12)
    )
    let presentedSurface = presentedArtifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(presentedSurface.contains("Save"))
  }
}
