import Core
import View

/// A declarative command record used inside ``Scene/commands(_:)``.
///
/// `CommandItem` carries the same semantic fields as ``Command`` plus an
/// action closure that runs when the command is activated. It is used only
/// as a literal inside the scene-level ``Scene/commands(_:)`` slot — the
/// primary registration site for always-on actions (Quit, Palette, Toggle
/// Theme, New Window, …).
///
/// Commands declared here flow into the same ``CommandPreferenceKey`` and
/// ``HotkeyRegistry`` that view-level ``View/command(id:title:key:…)``
/// writes into, so every help/palette lens picks them up without
/// distinguishing their source.
///
/// `CommandItem` does **not** conform to `Hashable`: the action closure is
/// not hashable. `CommandItem` is a value type that describes an authored
/// declaration, not a data type that can participate in equality.
public struct CommandItem: Sendable {
  public let id: String
  public let title: String
  public let key: KeyPress?
  public let group: String?
  public let detail: String?
  public let keywords: [String]
  public let kind: Command.Kind
  public let isDisabled: Bool
  public let action: @MainActor @Sendable () -> Void

  public init(
    id: String,
    title: String,
    key: KeyPress? = nil,
    group: String? = nil,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Command.Kind = .action,
    isDisabled: Bool = false,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.id = id
    self.title = title
    self.key = key
    self.group = group
    self.detail = detail
    self.keywords = keywords
    self.kind = kind
    self.isDisabled = isDisabled
    self.action = action
  }
}

/// Builds flat `[CommandItem]` arrays from authored
/// ``Scene/commands(_:)`` literals.
///
/// The builder accepts single `CommandItem` expressions as well as nested
/// `[CommandItem]` arrays, so authors may mix individual items with
/// sub-blocks and conditional branches. All branches flatten into one
/// flat registration order; the runtime reduces them into the existing
/// ``CommandPreferenceKey`` exactly like view-level commands.
@resultBuilder
public enum CommandsBuilder {
  public static func buildBlock() -> [CommandItem] {
    []
  }

  public static func buildBlock(_ components: CommandItem...) -> [CommandItem] {
    components
  }

  public static func buildBlock(_ components: [CommandItem]...) -> [CommandItem] {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ component: [CommandItem]?) -> [CommandItem] {
    component ?? []
  }

  public static func buildEither(first: [CommandItem]) -> [CommandItem] {
    first
  }

  public static func buildEither(second: [CommandItem]) -> [CommandItem] {
    second
  }

  public static func buildArray(_ components: [[CommandItem]]) -> [CommandItem] {
    components.flatMap { $0 }
  }

  public static func buildLimitedAvailability(_ component: [CommandItem]) -> [CommandItem] {
    component
  }

  public static func buildExpression(_ expression: CommandItem) -> [CommandItem] {
    [expression]
  }

  public static func buildExpression(_ expression: [CommandItem]) -> [CommandItem] {
    expression
  }
}
