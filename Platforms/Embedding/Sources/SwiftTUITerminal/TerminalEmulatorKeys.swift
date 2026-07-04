import SwiftTUICore

public struct TerminalEmulatorKey: Sendable, Equatable, Hashable {
  public enum Code: Sendable, Equatable, Hashable {
    case character(Character)
    case enter
    case backspace
    case escape
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case insert
    case delete
    case pageUp
    case pageDown
    case function(Int)
  }

  public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
  }

  public var code: Code
  public var modifiers: Modifiers

  public init(code: Code, modifiers: Modifiers = []) {
    self.code = code
    self.modifiers = modifiers
  }

  public init?(
    event: KeyEvent,
    modifiers: EventModifiers = []
  ) {
    self.init(keyPress: KeyPress(event, modifiers: modifiers))
  }

  public init?(keyPress: KeyPress) {
    guard let code = Code(event: keyPress.key) else {
      return nil
    }
    self.init(
      code: code,
      modifiers: Modifiers(eventModifiers: keyPress.modifiers)
    )
  }

  public var legacyByteSequence: [UInt8] {
    switch code {
    case .character(let character):
      return Array(String(character).utf8)
    case .enter:
      return [0x0D]
    case .backspace:
      return [0x7F]
    case .escape:
      return [0x1B]
    case .tab:
      return [0x09]
    case .arrowUp:
      return [0x1B, 0x5B, 0x41]
    case .arrowDown:
      return [0x1B, 0x5B, 0x42]
    case .arrowRight:
      return [0x1B, 0x5B, 0x43]
    case .arrowLeft:
      return [0x1B, 0x5B, 0x44]
    case .home:
      return [0x1B, 0x5B, 0x48]
    case .end:
      return [0x1B, 0x5B, 0x46]
    case .insert:
      return [0x1B, 0x5B, 0x32, 0x7E]
    case .delete:
      return [0x1B, 0x5B, 0x33, 0x7E]
    case .pageUp:
      return [0x1B, 0x5B, 0x35, 0x7E]
    case .pageDown:
      return [0x1B, 0x5B, 0x36, 0x7E]
    case .function(let number) where (1...4).contains(number):
      return [0x1B, 0x4F, UInt8(0x50 + number - 1)]
    case .function(let number):
      let codes: [Int: [UInt8]] = [
        5: [0x31, 0x35, 0x7E],
        6: [0x31, 0x37, 0x7E],
        7: [0x31, 0x38, 0x7E],
        8: [0x31, 0x39, 0x7E],
        9: [0x32, 0x30, 0x7E],
        10: [0x32, 0x31, 0x7E],
        11: [0x32, 0x33, 0x7E],
        12: [0x32, 0x34, 0x7E],
      ]
      return [0x1B, 0x5B] + (codes[number] ?? [])
    }
  }
}

extension TerminalEmulatorKey.Code {
  fileprivate init?(event: KeyEvent) {
    switch event {
    case .character(let character):
      self = .character(character)
    case .return:
      self = .enter
    case .space:
      self = .character(" ")
    case .tab:
      self = .tab
    case .arrowLeft:
      self = .arrowLeft
    case .arrowRight:
      self = .arrowRight
    case .arrowUp:
      self = .arrowUp
    case .arrowDown:
      self = .arrowDown
    case .backspace:
      self = .backspace
    case .escape:
      self = .escape
    case .home:
      self = .home
    case .end:
      self = .end
    case .insert:
      self = .insert
    case .delete:
      self = .delete
    case .pageUp:
      self = .pageUp
    case .pageDown:
      self = .pageDown
    case .functionKey(let number):
      self = .function(number)
    }
  }
}

extension TerminalEmulatorKey.Modifiers {
  fileprivate init(eventModifiers: EventModifiers) {
    var modifiers: Self = []
    if eventModifiers.contains(.ctrl) {
      modifiers.insert(.control)
    }
    if eventModifiers.contains(.alt) {
      modifiers.insert(.option)
    }
    if eventModifiers.contains(.shift) {
      modifiers.insert(.shift)
    }
    self = modifiers
  }
}
