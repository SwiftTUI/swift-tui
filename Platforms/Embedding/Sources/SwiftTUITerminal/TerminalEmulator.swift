import Foundation
import SwiftTUICore
@unsafe @preconcurrency import SwiftTerm

public actor TerminalEmulator {
  private let terminal: Terminal
  private let delegate: EmulatorDelegate

  public init(size: CellSize) {
    let delegate = EmulatorDelegate()
    self.delegate = delegate
    self.terminal = Terminal(
      delegate: delegate,
      options: TerminalOptions(cols: size.width, rows: size.height)
    )
    self.terminal.silentLog = true
    self.terminal.registerOscHandler(code: 133) { _ in }
  }

  public func feed(_ bytes: [UInt8]) -> [TerminalEmulatorEvent] {
    terminal.feed(byteArray: bytes)
    var events = delegate.drainEvents()
    events.append(contentsOf: Self.mouseProtocolEvents(in: bytes))
    return events
  }

  public func snapshot() -> ForeignGrid {
    let cols = terminal.cols
    let rows = terminal.rows
    var cells: [[RasterCell]] = []
    cells.reserveCapacity(rows)

    for y in 0..<rows {
      var row: [RasterCell] = []
      row.reserveCapacity(cols)
      for x in 0..<cols {
        guard let charData = terminal.getCharData(col: x, row: y) else {
          row.append(.empty)
          continue
        }
        row.append(Self.rasterCell(from: charData, terminal: terminal))
      }
      cells.append(row)
    }

    return ForeignGrid(size: CellSize(width: cols, height: rows), cells: cells)
  }

  public func resize(_ size: CellSize) {
    terminal.resize(cols: size.width, rows: size.height)
    delegate.record(.sizeReported(CellSize(width: terminal.cols, height: terminal.rows)))
  }

  public func encode(key: TerminalEmulatorKey) -> [UInt8] {
    key.legacyByteSequence
  }

  public func encode(paste: String) -> [UInt8] {
    let bytes = Array(paste.utf8)
    guard terminal.bracketedPasteMode else {
      return bytes
    }
    return EscapeSequences.bracketedPasteStart + bytes + EscapeSequences.bracketedPasteEnd
  }

  public func send(mouse: TerminalEmulatorMouse) -> [UInt8] {
    switch mouse.kind {
    case .down(let button):
      terminal.sendEvent(
        buttonFlags: buttonFlags(for: button, release: false, modifiers: mouse.modifiers),
        x: mouse.cell.x,
        y: mouse.cell.y
      )
    case .up(let button):
      terminal.sendEvent(
        buttonFlags: buttonFlags(for: button, release: true, modifiers: mouse.modifiers),
        x: mouse.cell.x,
        y: mouse.cell.y
      )
    case .dragged(let button):
      terminal.sendMotion(
        buttonFlags: buttonFlags(for: button, release: false, modifiers: mouse.modifiers),
        x: mouse.cell.x,
        y: mouse.cell.y,
        pixelX: mouse.cell.x,
        pixelY: mouse.cell.y
      )
    case .moved:
      terminal.sendMotion(
        buttonFlags: buttonFlags(for: .primary, release: true, modifiers: mouse.modifiers),
        x: mouse.cell.x,
        y: mouse.cell.y,
        pixelX: mouse.cell.x,
        pixelY: mouse.cell.y
      )
    case .scrolled(let deltaX, let deltaY):
      guard deltaX != 0 || deltaY != 0 else {
        return []
      }
      let button = scrollButton(deltaX: deltaX, deltaY: deltaY)
      terminal.sendEvent(
        buttonFlags: buttonFlags(for: button, release: false, modifiers: mouse.modifiers),
        x: mouse.cell.x,
        y: mouse.cell.y
      )
    }

    return delegate.drainClientReplyBytes()
  }

  private func buttonFlags(
    for button: TerminalEmulatorMouse.Button,
    release: Bool,
    modifiers: EventModifiers
  ) -> Int {
    terminal.encodeButton(
      button: buttonNumber(for: button),
      release: release,
      shift: modifiers.contains(.shift),
      meta: modifiers.contains(.alt),
      control: modifiers.contains(.ctrl)
    )
  }

  private func buttonNumber(for button: TerminalEmulatorMouse.Button) -> Int {
    switch button {
    case .primary:
      return 0
    case .middle:
      return 1
    case .secondary:
      return 2
    case .wheelUp:
      return 4
    case .wheelDown:
      return 5
    }
  }

  private func scrollButton(deltaX: Int, deltaY: Int) -> TerminalEmulatorMouse.Button {
    if deltaY < 0 || deltaX < 0 {
      return .wheelUp
    }
    return .wheelDown
  }

  private static func mouseProtocolEvents(in bytes: [UInt8]) -> [TerminalEmulatorEvent] {
    guard let text = String(bytes: bytes, encoding: .utf8) else {
      return []
    }

    var events: [TerminalEmulatorEvent] = []
    if text.contains("\u{1B}[?1006h") || text.contains("\u{1B}[?1016h") {
      events.append(.mouseModeChanged(.sgr))
    }
    if text.contains("\u{1B}[?1006l") || text.contains("\u{1B}[?1016l") {
      events.append(.mouseModeChanged(.disabled))
    }
    return events
  }

  private static func rasterCell(
    from charData: CharData,
    terminal: Terminal
  ) -> RasterCell {
    let attribute = charData.attribute
    let style = rasterStyle(from: attribute)
    let storedCharacter = terminal.getCharacter(for: charData)
    let character: Character =
      attribute.style.contains(.invisible) || isEmptyCellCharacter(storedCharacter)
      ? " "
      : storedCharacter

    return RasterCell(
      character: character,
      spanWidth: max(1, Int(charData.width)),
      style: style?.isDefault == true ? nil : style,
      hyperlink: charData.getPayload() as? String
    )
  }

  private static func isEmptyCellCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.count == 1
      && character.unicodeScalars.first?.value == 0
  }

  private static func rasterStyle(from attribute: Attribute) -> ResolvedTextStyle? {
    var foregroundColor = color(from: attribute.fg)
    var backgroundColor = color(from: attribute.bg)

    if attribute.style.contains(.inverse) {
      swap(&foregroundColor, &backgroundColor)
    }

    var emphasis = TextStyle.TextEmphasis()
    if attribute.style.contains(.bold) {
      emphasis.insert(.bold)
    }
    if attribute.style.contains(.italic) {
      emphasis.insert(.italic)
    }

    let underlineStyle: TextLineStyle? =
      attribute.style.contains(.underline)
      ? TextLineStyle(
        pattern: textLinePattern(from: attribute.underlineStyle),
        color: attribute.underlineColor.flatMap(color(from:))
      )
      : nil

    let strikethroughStyle: TextLineStyle? =
      attribute.style.contains(.crossedOut)
      ? TextLineStyle()
      : nil

    let style = ResolvedTextStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      emphasis: emphasis,
      underlineStyle: underlineStyle,
      strikethroughStyle: strikethroughStyle
    )
    return style.isDefault ? nil : style
  }

  private static func textLinePattern(from style: UnderlineStyle) -> TextLineStyle.Pattern {
    switch style {
    case .none, .single:
      return .solid
    case .double:
      return .double
    case .curly:
      return .curly
    case .dotted:
      return .dot
    case .dashed:
      return .dash
    }
  }

  private static func color(from color: SwiftTerm.Attribute.Color) -> SwiftTUICore.Color? {
    switch color {
    case .defaultColor, .defaultInvertedColor:
      return nil
    case .trueColor(let red, let green, let blue):
      return SwiftTUICore.Color(
        red: Double(red) / 255,
        green: Double(green) / 255,
        blue: Double(blue) / 255
      )
    case .ansi256(let code):
      return ansiColor(code)
    }
  }

  private static func ansiColor(_ code: UInt8) -> SwiftTUICore.Color {
    let base: [SwiftTUICore.Color] = [
      .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
      .gray, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
    ]
    if code < 16 {
      return base[Int(code)]
    }

    if code < 232 {
      let index = Int(code) - 16
      let red = index / 36
      let green = (index / 6) % 6
      let blue = index % 6
      return SwiftTUICore.Color(
        red: ansiCubeLevel(red),
        green: ansiCubeLevel(green),
        blue: ansiCubeLevel(blue)
      )
    }

    let shade = Double(8 + (Int(code) - 232) * 10) / 255
    return SwiftTUICore.Color(white: shade)
  }

  private static func ansiCubeLevel(_ component: Int) -> Double {
    component == 0 ? 0 : Double(55 + component * 40) / 255
  }
}

private final class EmulatorDelegate: TerminalDelegate {
  private var events: [TerminalEmulatorEvent] = []

  func record(_ event: TerminalEmulatorEvent) {
    events.append(event)
  }

  func drainEvents() -> [TerminalEmulatorEvent] {
    let drained = events
    events.removeAll(keepingCapacity: true)
    return drained
  }

  func drainClientReplyBytes() -> [UInt8] {
    var bytes: [UInt8] = []
    events.removeAll { event in
      guard case .clientReply(let replyBytes) = event else {
        return false
      }
      bytes.append(contentsOf: replyBytes)
      return true
    }
    return bytes
  }

  func setTerminalTitle(source: Terminal, title: String) {
    events.append(.titleChanged(title))
  }

  func hostCurrentDirectoryUpdated(source: Terminal) {
    if let directory = source.hostCurrentDirectory {
      events.append(.workingDirectoryChanged(directory))
    }
  }

  func send(source: Terminal, data: ArraySlice<UInt8>) {
    events.append(.clientReply(Array(data)))
  }

  func bell(source: Terminal) {
    events.append(.bell)
  }

  func bufferActivated(source: Terminal) {
    events.append(.bufferActivated(source.isCurrentBufferAlternate ? .alternate : .normal))
  }

  func mouseModeChanged(source: Terminal) {
    events.append(.mouseModeChanged(Self.mouseMode(from: source.mouseMode)))
  }

  func clipboardCopy(source: Terminal, content: Data) {
    events.append(.clipboardWriteRequested(Array(content)))
  }

  private static func mouseMode(from mode: Terminal.MouseMode) -> TerminalMouseMode {
    switch mode {
    case .off:
      return .disabled
    case .x10:
      return .x10
    case .vt200, .buttonEventTracking:
      return .button
    case .anyEvent:
      return .anyEvent
    }
  }
}
