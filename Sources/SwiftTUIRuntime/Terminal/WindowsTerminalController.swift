import SwiftTUICore

#if canImport(ucrt)
  import CRT
  import Synchronization
  import WinSDK

  /// Win32 console implementation of ``TerminalControlling`` (Stage 4 of the
  /// Windows plan).
  ///
  /// Input is read as `INPUT_RECORD`s via `ReadConsoleInputW` and re-linearized
  /// into the UTF-8/VT byte stream `TerminalInputParser` already understands —
  /// never via the byte-oriented `ReadFile` path, whose CP-65001 handling has
  /// been broken since Windows 10 shipped (microsoft/terminal#4551): non-ASCII
  /// arrives as 0x00 bytes there, so a hotkey-only smoke test false-greens
  /// while every non-English text field is broken. The record-filtering rules
  /// below are the set every production implementation converges on (libuv's
  /// `src/win/tty.c` is the reference).
  final class WindowsTerminalController: TerminalControlling, Sendable {
    /// Pump state that must survive across `read` calls: the console stores
    /// one `KEY_EVENT` per UTF-16 code unit, so a surrogate pair spans two
    /// records (and may span two reads); synthesized bytes beyond `maxBytes`
    /// wait here for the next call; mouse press/release detection needs the
    /// previous button state.
    private struct PumpState {
      var pendingHighSurrogate: UInt16?
      var pendingBytes: [UInt8] = []
      var lastMouseButtonState: DWORD = 0
    }

    private let pumpState = Mutex(PumpState())

    /// Probe-suspension depth (the F42 gate in polling-pump form): while
    /// nonzero the reader's pump parks without reading, so a capability
    /// probe's write-then-read cycle cannot lose its reply to the reader.
    let suspensionDepth = Mutex<Int>(0)

    /// Invoked by the pump when it consumes a `WINDOW_BUFFER_SIZE_EVENT`.
    /// Resize shares the console input queue with keystrokes — a second
    /// reader on the handle is unsupported and loses input — so the single
    /// pump dispatches resize out-of-band instead of surfacing it as bytes.
    /// The launch path points this at the session's injectable signal
    /// reader (the same "SIGWINCH" send the hosted sessions already use).
    let resizeObserver = Mutex<(@Sendable () -> Void)?>(nil)

    func isATTY(_ fileDescriptor: Int32) -> Bool {
      // GetConsoleMode failing is the reliable console test; _isatty alone
      // returns true for character devices that are not consoles.
      guard let handle = unsafe win32Handle(for: fileDescriptor) else { return false }
      var mode: DWORD = 0
      return unsafe GetConsoleMode(handle, &mode)
    }

    func windowSize(of fileDescriptor: Int32) throws -> CellSize {
      guard let handle = unsafe win32Handle(for: fileDescriptor) else {
        throw TerminalHostError.failedToReadWindowSize(errno: lastWin32Errno())
      }
      var info = CONSOLE_SCREEN_BUFFER_INFO()
      guard unsafe GetConsoleScreenBufferInfo(handle, &info) else {
        throw TerminalHostError.failedToReadWindowSize(errno: lastWin32Errno())
      }
      // srWindow is the visible viewport; dwSize is the scrollback buffer
      // (typically 9,001 rows tall) and must not be reported as the terminal.
      return CellSize(
        width: max(1, Int(info.srWindow.Right - info.srWindow.Left) + 1),
        height: max(1, Int(info.srWindow.Bottom - info.srWindow.Top) + 1)
      )
    }

    func enterRawMode(input: Int32, output: Int32) throws -> TerminalModeSnapshot {
      guard let inputHandle = unsafe win32Handle(for: input),
        let outputHandle = unsafe win32Handle(for: output)
      else {
        throw TerminalHostError.notATTY(fileDescriptor: input)
      }
      var inputMode: DWORD = 0
      var outputMode: DWORD = 0
      guard unsafe GetConsoleMode(inputHandle, &inputMode),
        unsafe GetConsoleMode(outputHandle, &outputMode)
      else {
        throw TerminalHostError.notATTY(fileDescriptor: input)
      }
      let snapshot = TerminalModeSnapshot(
        consoleInputMode: inputMode,
        consoleOutputMode: outputMode,
        inputCodePage: GetConsoleCP(),
        outputCodePage: GetConsoleOutputCP()
      )

      // ENABLE_VIRTUAL_TERMINAL_INPUT makes the console translate special
      // keys into the VT sequences TerminalInputParser already understands.
      // Clearing ENABLE_PROCESSED_INPUT delivers Ctrl+C as byte 0x03, which
      // is exactly what a POSIX raw-mode TUI expects. Clearing QuickEdit
      // (or mouse input is swallowed by the selection UI) requires
      // ENABLE_EXTENDED_FLAGS to be set in the same call.
      let rawInputMode =
        (inputMode
          & ~DWORD(
            ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT
              | ENABLE_QUICK_EDIT_MODE))
        | DWORD(
          ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT
            | ENABLE_EXTENDED_FLAGS)
      // ENABLE_PROCESSED_OUTPUT must stay set alongside VT processing or the
      // C0 controls (BS/TAB/CR/LF/BEL) are not interpreted.
      // DISABLE_NEWLINE_AUTO_RETURN is deferred end-of-line wrap (the xterm
      // "pending wrap"), which makes the bottom-right cell paintable.
      let rawOutputMode =
        outputMode
        | DWORD(
          ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING
            | DISABLE_NEWLINE_AUTO_RETURN)

      guard unsafe SetConsoleMode(inputHandle, rawInputMode),
        unsafe SetConsoleMode(outputHandle, rawOutputMode)
      else {
        throw TerminalHostError.failedToSetAttributes(errno: lastWin32Errno())
      }
      // Code pages are a property of the console object, not the process:
      // they outlive us and leak into the parent shell unless restored.
      SetConsoleCP(UINT(CP_UTF8))
      SetConsoleOutputCP(UINT(CP_UTF8))
      return snapshot
    }

    func restore(_ snapshot: TerminalModeSnapshot, input: Int32, output: Int32) throws {
      guard let inputHandle = unsafe win32Handle(for: input),
        let outputHandle = unsafe win32Handle(for: output)
      else {
        throw TerminalHostError.failedToSetAttributes(errno: lastWin32Errno())
      }
      var failed = false
      if unsafe !SetConsoleMode(inputHandle, snapshot.consoleInputMode) { failed = true }
      if unsafe !SetConsoleMode(outputHandle, snapshot.consoleOutputMode) { failed = true }
      if snapshot.inputCodePage != 0 {
        SetConsoleCP(snapshot.inputCodePage)
      }
      if snapshot.outputCodePage != 0 {
        SetConsoleOutputCP(snapshot.outputCodePage)
      }
      if failed {
        throw TerminalHostError.failedToSetAttributes(errno: lastWin32Errno())
      }
    }

    // MARK: - Write path

    func write(_ output: String, to fileDescriptor: Int32) throws {
      guard let handle = unsafe win32Handle(for: fileDescriptor) else {
        throw TerminalHostError.failedToWrite(errno: lastWin32Errno())
      }
      let bytes = Array(output.utf8)
      var offset = 0
      while offset < bytes.count {
        // Console writes travel through a shared 64 KB conhost heap; an
        // oversized call fails whole with ERROR_NOT_ENOUGH_MEMORY, and a
        // very large write holds the console lock for the whole parse.
        // Follow Rust std and libuv: <= 8 KiB per call, split only on
        // UTF-8 code-point boundaries (the console decodes the stream per
        // the output code page).
        var chunkEnd = min(offset + 8192, bytes.count)
        if chunkEnd < bytes.count {
          while chunkEnd > offset, bytes[chunkEnd] & 0xC0 == 0x80 {
            chunkEnd -= 1
          }
          if chunkEnd == offset {
            chunkEnd = min(offset + 8192, bytes.count)
          }
        }
        let written: Int = try unsafe bytes.withUnsafeBytes { rawBuffer in
          guard let base = rawBuffer.baseAddress else { return 0 }
          var chunkWritten: DWORD = 0
          let ok = unsafe WriteFile(
            handle,
            unsafe base.advanced(by: offset),
            DWORD(chunkEnd - offset),
            &chunkWritten,
            nil
          )
          if !ok {
            let code = GetLastError()
            // The hosting terminal or ConPTY went away: the EIO/EPIPE
            // analogue. Return cleanly and let input EOF drive the
            // orderly shutdown, matching the POSIX conformer.
            if code == DWORD(ERROR_NO_DATA) || code == DWORD(ERROR_BROKEN_PIPE) {
              return -1
            }
            throw TerminalHostError.failedToWrite(errno: Int32(bitPattern: code))
          }
          return Int(chunkWritten)
        }
        if written < 0 {
          return
        }
        offset += max(written, 1)
      }
    }

    // MARK: - The input pump

    func read(
      from fileDescriptor: Int32,
      maxBytes: Int,
      timeoutMilliseconds: Int
    ) throws -> [UInt8] {
      guard maxBytes > 0 else { return [] }

      // Serve bytes synthesized past a previous call's maxBytes first.
      let buffered = pumpState.withLock { state -> [UInt8] in
        guard !state.pendingBytes.isEmpty else { return [] }
        let served = Array(state.pendingBytes.prefix(maxBytes))
        state.pendingBytes.removeFirst(served.count)
        return served
      }
      if !buffered.isEmpty {
        return buffered
      }

      guard let handle = unsafe win32Handle(for: fileDescriptor) else {
        return []
      }
      guard unsafe WaitForSingleObject(handle, DWORD(max(0, timeoutMilliseconds))) == WAIT_OBJECT_0
      else {
        return []
      }

      var records = [INPUT_RECORD](repeating: INPUT_RECORD(), count: 128)
      var recordCount: DWORD = 0
      let ok = unsafe records.withUnsafeMutableBufferPointer { buffer in
        unsafe ReadConsoleInputW(handle, buffer.baseAddress, DWORD(buffer.count), &recordCount)
      }
      guard ok else { return [] }

      var bytes: [UInt8] = []
      var resized = false
      pumpState.withLock { state in
        for index in 0..<Int(recordCount) {
          let record = records[index]
          switch Int32(record.EventType) {
          case KEY_EVENT:
            unsafe appendKeyEventBytes(record.Event.KeyEvent, state: &state, into: &bytes)
          case WINDOW_BUFFER_SIZE_EVENT:
            resized = true
          case MOUSE_EVENT:
            unsafe appendSyntheticSGR(record.Event.MouseEvent, state: &state, into: &bytes)
          default:
            // FOCUS_EVENT / MENU_EVENT are documented as internal-use.
            break
          }
        }
        if bytes.count > maxBytes {
          state.pendingBytes.append(contentsOf: bytes[maxBytes...])
          bytes.removeLast(bytes.count - maxBytes)
        }
      }
      if resized {
        resizeObserver.withLock { $0 }?()
      }
      // A signaled wait that produced no bytes is a spurious wakeup, never
      // EOF — conhost had exactly this bug under Windows Terminal until
      // December 2024 (microsoft/terminal#18228). Callers poll again.
      return bytes
    }

    /// The record-filtering rules every production implementation converges
    /// on (libuv `tty.c`): key-downs only, except an Alt key-up carrying a
    /// character (the Alt+numpad composition result); surrogate pairs are
    /// combined across records; `wRepeatCount` expands.
    private func appendKeyEventBytes(
      _ key: KEY_EVENT_RECORD,
      state: inout PumpState,
      into bytes: inout [UInt8]
    ) {
      let isKeyDown = key.bKeyDown.boolValue
      let unit = unsafe key.uChar.UnicodeChar
      if !isKeyDown {
        guard key.wVirtualKeyCode == WORD(VK_MENU), unit != 0 else {
          return
        }
      }
      guard unit != 0 else {
        // With ENABLE_VIRTUAL_TERMINAL_INPUT, special keys arrive as runs
        // of character-bearing records; a bare virtual-key press with no
        // character (a lone modifier) contributes nothing to the stream.
        return
      }

      var scalars: [Unicode.Scalar] = []
      if let high = state.pendingHighSurrogate {
        state.pendingHighSurrogate = nil
        if unit >= 0xDC00, unit <= 0xDFFF {
          let combined = 0x10000 + (UInt32(high - 0xD800) << 10) + UInt32(unit - 0xDC00)
          if let scalar = Unicode.Scalar(combined) {
            scalars.append(scalar)
          }
        } else if let scalar = Unicode.Scalar(UInt32(unit)) {
          // Unpaired high surrogate: drop it, keep the new unit.
          scalars.append(scalar)
        }
      } else if unit >= 0xD800, unit <= 0xDBFF {
        state.pendingHighSurrogate = unit
        return
      } else if let scalar = Unicode.Scalar(UInt32(unit)) {
        scalars.append(scalar)
      }

      guard !scalars.isEmpty else { return }
      let repeatCount = max(1, Int(key.wRepeatCount))
      for _ in 0..<repeatCount {
        for scalar in scalars {
          bytes.append(contentsOf: Array(String(scalar).utf8))
        }
      }
    }

    /// Legacy conhost delivers mouse input as `MOUSE_EVENT_RECORD`s (Windows
    /// Terminal translates to VT itself); translate records into synthetic
    /// SGR sequences so `TerminalInputParser` stays the single decoder for
    /// both encodings — the libuv approach. A host that translates to VT
    /// does not also post records for the same event, so no deduplication.
    private func appendSyntheticSGR(
      _ mouse: MOUSE_EVENT_RECORD,
      state: inout PumpState,
      into bytes: inout [UInt8]
    ) {
      let column = Int(mouse.dwMousePosition.X) + 1
      let row = Int(mouse.dwMousePosition.Y) + 1
      let flags = mouse.dwEventFlags
      let buttons = mouse.dwButtonState

      func emit(_ code: Int, pressed: Bool) {
        let sequence = "\u{1B}[<\(code);\(column);\(row)\(pressed ? "M" : "m")"
        bytes.append(contentsOf: Array(sequence.utf8))
      }

      if flags & DWORD(MOUSE_WHEELED) != 0 {
        // Wheel delta rides the high word; positive scrolls up (SGR 64).
        let delta = Int16(truncatingIfNeeded: Int32(bitPattern: buttons) >> 16)
        emit(delta > 0 ? 64 : 65, pressed: true)
        return
      }
      if flags & DWORD(MOUSE_HWHEELED) != 0 {
        let delta = Int16(truncatingIfNeeded: Int32(bitPattern: buttons) >> 16)
        emit(delta > 0 ? 67 : 66, pressed: true)
        return
      }

      let previous = state.lastMouseButtonState
      state.lastMouseButtonState = buttons
      let changed = previous ^ buttons
      if changed != 0 {
        // Lowest three bits are left/right/middle in record order; SGR
        // numbers them left=0, middle=1, right=2.
        let recordToSGR: [(mask: DWORD, code: Int)] = [
          (DWORD(FROM_LEFT_1ST_BUTTON_PRESSED), 0),
          (DWORD(FROM_LEFT_2ND_BUTTON_PRESSED), 1),
          (DWORD(RIGHTMOST_BUTTON_PRESSED), 2),
        ]
        for entry in recordToSGR where changed & entry.mask != 0 {
          emit(entry.code, pressed: buttons & entry.mask != 0)
        }
        return
      }
      if flags & DWORD(MOUSE_MOVED) != 0 {
        // Motion reports: 32 + button (or 3 when no button is held).
        let held: Int
        if buttons & DWORD(FROM_LEFT_1ST_BUTTON_PRESSED) != 0 {
          held = 0
        } else if buttons & DWORD(FROM_LEFT_2ND_BUTTON_PRESSED) != 0 {
          held = 1
        } else if buttons & DWORD(RIGHTMOST_BUTTON_PRESSED) != 0 {
          held = 2
        } else {
          held = 3
        }
        emit(32 + held, pressed: true)
      }
    }
  }

  @inline(__always)
  func win32Handle(for fileDescriptor: Int32) -> HANDLE? {
    // _get_osfhandle returns INVALID_HANDLE_VALUE (-1) or -2 ("fd not
    // associated with a stream") — the shape swift-testing and
    // swift-corelibs-foundation use.
    let raw = _get_osfhandle(fileDescriptor)
    guard raw != -1, raw != -2 else { return nil }
    return unsafe HANDLE(bitPattern: raw)
  }

  @inline(__always)
  private func lastWin32Errno() -> Int32 {
    Int32(bitPattern: GetLastError())
  }
#endif
