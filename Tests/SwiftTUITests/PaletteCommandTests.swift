import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct PaletteCommandTests {
  @Test("duplicate labels have distinct structural contribution identities")
  func duplicateIdentities() {
    let view = Panel(id: "editor") { EmptyView() }
      .paletteCommand(name: "Same", description: "Same", action: {})
      .paletteCommand(name: "Same", description: "Same", action: {})
    let resolved = Resolver().resolve(
      AnyView(view), in: .init(identity: testIdentity("Contributions")))
    let commands = resolved.preferenceValues[PaletteCommandsPreferenceKey.self]
    #expect(commands.count == 2)
    #expect(Set(commands.map(\.identity)).count == 2)
  }

  @Test("renaming commands preserves their contribution identities")
  func renamedIdentities() {
    func commands(_ name: String) -> [ActivePaletteCommand] {
      let view = Panel(id: "editor") { EmptyView() }
        .paletteCommand(name: name, description: name, action: {})
        .paletteCommand(name: "Other", action: {})
      return Resolver().resolve(AnyView(view), in: .init(identity: testIdentity("Contributions")))
        .preferenceValues[PaletteCommandsPreferenceKey.self]
    }
    #expect(commands("Before").map(\.identity) == commands("After").map(\.identity))
  }

  @Test("changing a contribution's conditional branch changes its identity")
  func branchIdentity() {
    func commands(_ firstBranch: Bool) -> [ActivePaletteCommand] {
      let view = Panel(id: "editor") {
        if firstBranch {
          Panel(id: "same") { Text("Base") }
            .paletteCommand(name: "Same", action: {})
        } else {
          Panel(id: "same") { Text("Base") }
            .paletteCommand(name: "Same", action: {})
        }
      }
      return Resolver().resolve(AnyView(view), in: .init(identity: testIdentity("Contributions")))
        .preferenceValues[PaletteCommandsPreferenceKey.self]
    }
    #expect(commands(true).count == 1)
    #expect(commands(false).count == 1)
    #expect(commands(true).map(\.identity) != commands(false).map(\.identity))
  }

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

    let names =
      resolved
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
