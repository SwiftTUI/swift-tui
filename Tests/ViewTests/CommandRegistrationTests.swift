import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct CommandRegistrationTests {
  @Test("command with key registers a hotkey binding with label/group/id")
  func commandWithKeyRegistersHotkey() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "CommandWithKey"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    _ =
      Text("hi")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s"),
        group: "Document"
      ) {
        // no-op
      }
      .resolve(in: context)

    let bindings = hotkeyRegistry.registeredBindings()
    #expect(bindings.count == 1)

    let binding = bindings[0]
    #expect(binding.key == .ctrl("s"))
    #expect(binding.label == "Save")
    #expect(binding.group == "Document")
    #expect(binding.commandID == "save")
  }

  @Test("command without key does not register a hotkey but still surfaces in the preference")
  func commandWithoutKeyIsSearchableButNotRegistered() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "NoKey"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    let node =
      Text("hi")
      .command(id: "foo", title: "Foo") {
        // no-op
      }
      .resolve(in: context)

    #expect(hotkeyRegistry.registeredBindings().isEmpty)

    let registrations = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(registrations.count == 1)
    #expect(registrations.first?.command.id == "foo")
    #expect(registrations.first?.command.key == nil)
  }

  @Test("disabled command with a key does not register a hotkey")
  func disabledCommandWithKeyIsNotRegistered() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "Disabled"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    let node =
      Text("hi")
      .command(
        id: "save",
        title: "Save",
        isDisabled: true,
        key: .ctrl("s")
      ) {
        // no-op
      }
      .resolve(in: context)

    #expect(hotkeyRegistry.registeredBindings().isEmpty)

    let registrations = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(registrations.count == 1)
    #expect(registrations.first?.command.id == "save")
    #expect(registrations.first?.command.isDisabled == true)
  }

  @Test("group flows into the Command stored in the preference value")
  func groupFlowsIntoPreferenceValue() {
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "Group"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    let node =
      Text("hi")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s"),
        group: "Document"
      ) {
        // no-op
      }
      .resolve(in: context)

    let registrations = node.preferenceValues[CommandPreferenceKey.self].registrations
    #expect(registrations.first?.command.group == "Document")
  }

  @Test("registered hotkey dispatches to the command's action")
  func registeredHotkeyDispatchesToAction() {
    final class Capture {
      var fired = false
    }
    let capture = Capture()
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "Dispatch"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    _ =
      Text("hi")
      .command(
        id: "save",
        title: "Save",
        key: .ctrl("s")
      ) {
        capture.fired = true
      }
      .resolve(in: context)

    let handled = hotkeyRegistry.dispatch(.ctrl("s"))
    #expect(handled)
    #expect(capture.fired)
  }

  @Test("each command's hotkey handler filters by its own binding's key")
  func handlerFiltersByBindingKey() {
    // Regression: HotkeyRegistry.dispatch iterates handlers and stops at the
    // first one that returns true. If a command's handler doesn't filter by
    // its own key, any dispatch fires the first-registered command. Found
    // while implementing Stage 3; pinned here so the invariant can't regress.
    final class Capture {
      var saveFired = false
      var quitFired = false
    }
    let capture = Capture()
    let hotkeyRegistry = HotkeyRegistry()
    var context = ResolveContext(
      identity: testIdentity("CommandRegistrationTests", "HandlerFilter"),
      applyEnvironmentValues: true
    )
    context.hotkeyRegistry = hotkeyRegistry

    _ =
      Text("hi")
      .command(id: "save", title: "Save", key: .ctrl("s")) {
        capture.saveFired = true
      }
      .command(id: "quit", title: "Quit", key: .ctrl("q")) {
        capture.quitFired = true
      }
      .resolve(in: context)

    // Dispatching Ctrl+S fires only save.
    #expect(hotkeyRegistry.dispatch(.ctrl("s")))
    #expect(capture.saveFired)
    #expect(!capture.quitFired)

    capture.saveFired = false

    // Dispatching Ctrl+Q fires only quit.
    #expect(hotkeyRegistry.dispatch(.ctrl("q")))
    #expect(!capture.saveFired)
    #expect(capture.quitFired)

    capture.quitFired = false

    // Dispatching a key with no registered command fires neither and returns false.
    #expect(!hotkeyRegistry.dispatch(.ctrl("x")))
    #expect(!capture.saveFired)
    #expect(!capture.quitFired)
  }
}
