import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteCommandTests {
  @Test("paletteCommand contributes a value to PaletteCommandsPreferenceKey")
  func paletteCommandContributes() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Toggle theme", action: {})

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.count == 1)
    #expect(commands.first?.name == "Toggle theme")
    #expect(commands.first?.isEnabled == true)
    #expect(commands.first?.description == nil)
  }

  @Test("paletteCommand description survives the contribution")
  func paletteCommandPreservesDescription() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Toggle theme",
        description: "Switch between light and dark",
        action: {}
      )

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.first?.description == "Switch between light and dark")
  }

  @Test("Disabled paletteCommand is contributed but marked disabled")
  func paletteCommandDisabled() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(
        name: "Delete all",
        isEnabled: false,
        action: {}
      )

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.first?.isEnabled == false)
  }

  @Test("Multiple paletteCommands accumulate in declaration order")
  func paletteCommandsAccumulate() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Command A", action: {})
      .paletteCommand(name: "Command B", action: {})

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )

    let names = resolved
      .preferenceValues[PaletteCommandsPreferenceKey.self]
      .map(\.name)
    #expect(names == ["Command A", "Command B"])
  }

  @Test("paletteCommand action survives wrapping; invoking it fires the user action")
  func paletteCommandActionWrappedSafely() {
    let fired = PaletteActionFiredBox()
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Trigger", action: { fired.value = true })

    let resolved = Resolver().resolve(
      AnyView(view),
      in: ResolveContext(identity: testIdentity("palette-root"))
    )
    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    commands.first?.action()
    #expect(fired.value == true)
  }
}

@MainActor
private final class PaletteActionFiredBox {
  var value: Bool = false
}
