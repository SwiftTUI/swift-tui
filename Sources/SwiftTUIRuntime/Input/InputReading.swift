import SwiftTUICore

/// Produces keyboard events from an input source.
public protocol InputReading: AnyObject {
  func events() -> AsyncStream<KeyPress>
}

/// Produces keyboard and mouse events from an input source.
public protocol TerminalInputReading: AnyObject {
  func inputEvents() -> AsyncStream<InputEvent>
}
