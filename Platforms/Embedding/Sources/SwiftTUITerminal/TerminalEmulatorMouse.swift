public import SwiftTUI

public struct TerminalEmulatorMouse: Sendable, Equatable, Hashable {
  public enum Button: Sendable, Equatable, Hashable {
    case primary
    case middle
    case secondary
    case wheelUp
    case wheelDown
  }

  public enum Kind: Sendable, Equatable, Hashable {
    case down(Button)
    case up(Button)
    case dragged(Button)
    case moved
    case scrolled(deltaX: Int, deltaY: Int)
  }

  public var kind: Kind
  public var cell: CellPoint
  public var modifiers: EventModifiers

  public init(
    kind: Kind,
    cell: CellPoint,
    modifiers: EventModifiers = []
  ) {
    self.kind = kind
    self.cell = cell
    self.modifiers = modifiers
  }

  public init(event: MouseEvent) {
    self.init(
      kind: Kind(eventKind: event.kind),
      cell: event.location.cell,
      modifiers: event.modifiers
    )
  }
}

extension TerminalEmulatorMouse.Kind {
  fileprivate init(eventKind: MouseEvent.Kind) {
    switch eventKind {
    case .down(let button):
      self = .down(.init(mouseButton: button))
    case .up(let button):
      self = .up(.init(mouseButton: button))
    case .dragged(let button):
      self = .dragged(.init(mouseButton: button))
    case .moved:
      self = .moved
    case .scrolled(let deltaX, let deltaY):
      self = .scrolled(deltaX: deltaX, deltaY: deltaY)
    }
  }
}

extension TerminalEmulatorMouse.Button {
  fileprivate init(mouseButton: MouseButton) {
    switch mouseButton {
    case .primary:
      self = .primary
    case .middle:
      self = .middle
    case .secondary:
      self = .secondary
    }
  }
}
