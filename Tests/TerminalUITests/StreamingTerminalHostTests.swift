import Synchronization
import Testing

@testable import TerminalUI

@Suite
struct StreamingTerminalHostTests {
  @Test("streaming terminal host writes terminal control sequences to its output handler")
  func streamingTerminalHostWritesToOutputHandler() throws {
    let writes = Mutex<[String]>([])
    let host = StreamingTerminalHost(
      surfaceSize: .init(width: 10, height: 4),
      outputHandler: { output in
        writes.withLock { capturedWrites in
          capturedWrites.append(output)
        }
      }
    )

    try host.enableRawMode()
    try host.write("Hello")
    host.updateSurfaceSize(.init(width: 12, height: 6))
    let updatedAppearance = TerminalAppearance(
      foregroundColor: .black,
      backgroundColor: .white,
      tintColor: .blue,
      source: .override
    )
    host.updateAppearance(updatedAppearance)
    try host.disableRawMode()

    let output = writes.withLock { $0.joined() }

    #expect(output.contains("\u{001B}[?1049h"))
    #expect(output.contains("\u{001B}[?1049l"))
    #expect(output.contains("Hello"))
    #expect(host.surfaceSize == .init(width: 12, height: 6))
    #expect(host.appearance == updatedAppearance)
  }

  @Test("streaming terminal host toggles SGR-Pixels for terminal-pixel input")
  func streamingTerminalHostTogglesSGRPixelsForTerminalPixelInput() throws {
    let writes = Mutex<[String]>([])
    let host = StreamingTerminalHost(
      surfaceSize: .init(width: 10, height: 4),
      pointerInputCapabilities: .init(
        precision: .subCell(
          source: .terminalPixels,
          metrics: CellPixelMetrics(width: 8, height: 16, source: .reported)
        )
      ),
      outputHandler: { output in
        writes.withLock { capturedWrites in
          capturedWrites.append(output)
        }
      }
    )

    try host.enableRawMode()
    try host.disableRawMode()

    let output = writes.withLock { $0.joined() }
    #expect(output.contains("\u{001B}[?1006h\u{001B}[?1016h\u{001B}[?1002h"))
    #expect(output.contains("\u{001B}[?1002l\u{001B}[?1016l\u{001B}[?1006l"))
  }

  @Test("streaming terminal host toggles all-motion mode for hover")
  func streamingTerminalHostTogglesAllMotionModeForHover() throws {
    let writes = Mutex<[String]>([])
    let host = StreamingTerminalHost(
      surfaceSize: .init(width: 10, height: 4),
      outputHandler: { output in
        writes.withLock { capturedWrites in
          capturedWrites.append(output)
        }
      }
    )

    try host.setPointerHoverEnabled(true)
    try host.setPointerHoverEnabled(false)

    let output = writes.withLock { $0.joined() }
    #expect(output.contains("\u{001B}[?1006h\u{001B}[?1002h\u{001B}[?1003h"))
    #expect(output.contains("\u{001B}[?1003l\u{001B}[?1006h\u{001B}[?1002h"))
  }

  @Test("streaming terminal host stores host-owned theme updates")
  func streamingTerminalHostStoresThemeUpdates() {
    let host = StreamingTerminalHost(
      surfaceSize: .init(width: 10, height: 4),
      outputHandler: { _ in }
    )

    let updatedTheme = Theme(
      foreground: .hex("#102030"),
      background: .hex("#F8FAFC"),
      tint: .hex("#1D4ED8"),
      separator: .hex("#CBD5E1"),
      selection: .hex("#DBEAFE"),
      placeholder: .hex("#94A3B8"),
      link: .hex("#1D4ED8"),
      fill: .hex("#EFF6FF"),
      windowBackground: .hex("#E2E8F0"),
      success: .hex("#16A34A"),
      warning: .hex("#D97706"),
      danger: .hex("#DC2626"),
      info: .hex("#0284C7"),
      muted: .hex("#64748B")
    )
    host.updateTheme(updatedTheme)

    #expect(host.theme?.style(for: .warning) == .color(updatedTheme.warning))

    let updatedStyle = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: .black,
        backgroundColor: .white,
        tintColor: .blue,
        source: .override
      ),
      theme: updatedTheme
    )
    host.updateStyle(updatedStyle)

    #expect(host.appearance == updatedStyle.appearance)
    #expect(host.theme == updatedTheme)
  }
}
