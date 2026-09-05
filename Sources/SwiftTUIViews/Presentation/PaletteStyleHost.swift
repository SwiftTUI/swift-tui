import SwiftTUICore

/// The declaration supplies command data and source styling; this primitive
/// owns pointer handlers beneath its own lifetime and resolves one typed body.
struct PaletteStyleHost: PrimitiveView, ResolvableView {
  let style: AnyPaletteStyle
  let title: String
  let commands: [ActivePaletteCommand]
  let terminalSize: CellSize
  let prominence: ControlProminence
  let styleEnvironment: StyleEnvironmentSnapshot
  let isPresented: @MainActor @Sendable () -> Bool
  let dismiss: @MainActor @Sendable () -> Void

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let owner = ViewNodeContext.current?.stateOwnerHandle
    let isPresented = self.isPresented
    let dismiss = self.dismiss
    let dismissLive: @MainActor @Sendable () -> Void = {
      guard owner == nil || owner.flatMap(LiveViewGraphRegistry.node(for:)) != nil,
        isPresented()
      else { return }
      dismiss()
    }
    let intake = HandlerDescriptorIntake(context: context)
    let values = commands.map { command in
      let routeIdentity = Identity(
        components: context.identity.components + ["PaletteCommand"] + command.identity.components)
      let activate: @MainActor @Sendable () -> Void = {
        guard command.isEnabled,
          owner == nil || owner.flatMap(LiveViewGraphRegistry.node(for:)) != nil,
          isPresented()
        else { return }
        command.action()
        dismiss()
      }
      if command.isEnabled {
        intake.registerPointerHandler(routeID: runtimePrimaryRouteID(for: routeIdentity)) { event in
          switch event.kind {
          case .down(.primary):
            activate()
            return .claimed
          case .up(.primary): return .claimed
          default: return .ignored
          }
        }
      }
      return PaletteStyleConfiguration.Command(
        contribution: command, routeIdentity: routeIdentity, activation: activate)
    }
    var configuration = PaletteStyleConfiguration(
      title: title, commands: values, terminalSize: terminalSize,
      controlProminence: prominence, styleEnvironment: styleEnvironment)
    configuration.bindDismissal(dismissLive)
    let body = style.resolveBody(
      configuration: configuration, in: context.child(component: .named("PaletteBody")))
    return [
      ResolvedNode(
        identity: context.identity, kind: .view("PaletteStyleHost"), children: [body],
        environmentSnapshot: context.environment, transactionSnapshot: context.transaction)
    ]
  }
}
