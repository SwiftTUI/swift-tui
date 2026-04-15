import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite
struct CommandHotkeyIntegrationTests {
  @Test("command with key registers a hotkey through DefaultRenderer")
  func commandWithKeyRegistersHotkeyThroughDefaultRenderer() {
    let hotkeyRegistry = HotkeyRegistry()
    final class Capture {
      var fired = false
    }
    let capture = Capture()

    var context = ResolveContext(identity: testIdentity("Root"))
    context.hotkeyRegistry = hotkeyRegistry

    _ = DefaultRenderer().render(
      Text("Workspace")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s"),
          group: "Document"
        ) {
          capture.fired = true
        }
        .frame(width: 12, height: 1, alignment: .leading),
      context: context,
      proposal: .init(width: 40, height: 10)
    )

    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.contains { $0.commandID == "save" })
    #expect(bindings.contains { $0.key == .ctrl("s") })
    #expect(bindings.contains { $0.label == "Save" })
    #expect(bindings.contains { $0.group == "Document" })

    // Dispatching the matching key press fires the command's action.
    let handled = hotkeyRegistry.dispatch(.ctrl("s"))
    #expect(handled)
    #expect(capture.fired)
  }

  @Test("non-action command overload does not register a hotkey but still renders")
  func nonActionCommandOverloadRenders() {
    let hotkeyRegistry = HotkeyRegistry()

    var context = ResolveContext(identity: testIdentity("Root"))
    context.hotkeyRegistry = hotkeyRegistry

    let artifacts = DefaultRenderer().render(
      Text("Workspace")
        .command(id: "open-file", title: "Open File")
        .frame(width: 12, height: 1, alignment: .leading)
        .commandPalette(isPresented: .constant(true)),
      context: context,
      proposal: .init(width: 40, height: 10)
    )

    // The command has no key, so no hotkey binding is registered for it.
    // (The command palette's own shortcut is unset.)
    let commandBindings = hotkeyRegistry.registeredBindings().filter {
      $0.commandID == "open-file"
    }
    #expect(commandBindings.isEmpty)

    // The palette still renders so commands remain searchable.
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Command Palette"))
  }
}
