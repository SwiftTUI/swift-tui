// Windows-only (Windows plan, Stage 6 item 3): the Stage 0.4 input-injection
// spike, promoted to a swift-testing suite. Injects INPUT_RECORDs into the
// real console input buffer with WriteConsoleInputW and asserts what comes
// out of the PUBLIC InputReader.events() path — records → pump → parser.
// The throwaway harness and its VM results live in the coordination root at
// docs/reports/evidence/2026-08-17-windows-input-spike/.
#if os(Windows)

  import CRT
  import Synchronization
  import Testing
  import WinSDK

  @testable import SwiftTUIRuntime

  /// Serialized: the suite owns the process console's input buffer, and a
  /// second reader on the same console queue loses input (the single-reader
  /// rule the pump is built around).
  @Suite(.serialized)
  struct WindowsInputRecordPumpTests {
    private struct InjectionCase {
      var name: String
      var records: [INPUT_RECORD]
      var expected: [String]
    }

    private static func keyRecord(
      _ unit: UInt16, down: Bool = true, repeatCount: UInt16 = 1, vk: UInt16 = 0
    ) -> INPUT_RECORD {
      var record = INPUT_RECORD()
      record.EventType = WORD(KEY_EVENT)
      var key = KEY_EVENT_RECORD()
      key.bKeyDown = WindowsBool(down)
      key.wRepeatCount = repeatCount
      key.wVirtualKeyCode = vk
      unsafe key.uChar.UnicodeChar = unit
      unsafe record.Event.KeyEvent = key
      return record
    }

    private final class EventBox: Sendable {
      let events = Mutex<[String]>([])
    }

    @Test("console records reach InputReader.events() as decoded key presses")
    func recordPumpDecodesInjectedRecords() async throws {
      // A test runner may have no console at all (prlctl / CI service
      // context); the record queue only exists on a real console.
      if unsafe GetConsoleWindow() == nil {
        _ = AllocConsole()
      }
      // Open the console input buffer directly: stdin may be a pipe under a
      // non-interactive launcher, but CONIN$ is the real record queue.
      let coninHandle = unsafe "CONIN$".withCString(encodedAs: UTF16.self) { name in
        unsafe CreateFileW(
          name, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE),
          DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE),
          nil, DWORD(OPEN_EXISTING), 0, nil)
      }
      let conin = try unsafe #require(unsafe coninHandle)
      try #require(unsafe conin != INVALID_HANDLE_VALUE)
      let rawFD = _open_osfhandle(Int(bitPattern: conin), 0)
      try #require(rawFD >= 0)
      _ = unsafe FlushConsoleInputBuffer(conin)

      // The libuv-rule cases the pump was validated against on the VM:
      // UTF-16 unit passthrough, surrogate pairs recombined across records,
      // wRepeatCount expansion, VT runs (ENABLE_VIRTUAL_TERMINAL_INPUT
      // shape), the Alt+numpad key-up carrying a character, and plain
      // key-up filtering. Ctrl+C stays OFF this list: its in-band delivery
      // depends on the raw-mode console flags the session controller owns,
      // not on the pump alone.
      let cases: [InjectionCase] = [
        .init(name: "ascii", records: [Self.keyRecord(0x61)], expected: ["character(\"a\")"]),
        .init(
          name: "latin-e-acute", records: [Self.keyRecord(0x00E9)],
          expected: ["character(\"\u{E9}\")"]),
        .init(
          name: "cjk", records: [Self.keyRecord(0x4F60)],
          expected: ["character(\"\u{4F60}\")"]),
        .init(
          name: "emoji-surrogate-pair",
          records: [Self.keyRecord(0xD83D), Self.keyRecord(0xDE00)],
          expected: ["character(\"\u{1F600}\")"]),
        .init(
          name: "repeat-count", records: [Self.keyRecord(0x78, repeatCount: 3)],
          expected: ["character(\"x\")", "character(\"x\")", "character(\"x\")"]),
        .init(
          name: "vt-arrow-up-run",
          records: [Self.keyRecord(0x1B), Self.keyRecord(0x5B), Self.keyRecord(0x41)],
          expected: ["arrowUp"]),
        .init(
          name: "alt-numpad-composition",
          records: [Self.keyRecord(0x00F1, down: false, vk: UInt16(VK_MENU))],
          expected: ["character(\"\u{F1}\")"]),
        .init(
          name: "plain-keyup-dropped",
          records: [Self.keyRecord(0x7A, down: false), Self.keyRecord(0x62)],
          expected: ["character(\"b\")"]),
      ]

      // ONE reader for every case: a second reader on the console handle
      // races the first for records (risk-register rule).
      let box = EventBox()
      let reader = InputReader(fileDescriptor: rawFD)
      let consumer = Task.detached {
        for await press in reader.events() {
          box.events.withLock { $0.append(String(describing: press.key)) }
        }
      }
      defer { consumer.cancel() }

      var consumed = 0
      for injectionCase in cases {
        var written: DWORD = 0
        _ = unsafe injectionCase.records.withUnsafeBufferPointer { buffer in
          unsafe WriteConsoleInputW(conin, buffer.baseAddress, DWORD(buffer.count), &written)
        }

        // Bounded wait for the expected count, then a short settle so any
        // stray event attributes to the case that produced it.
        let deadline = ContinuousClock.now + .seconds(5)
        while box.events.withLock({ $0.count }) - consumed < injectionCase.expected.count,
          ContinuousClock.now < deadline
        {
          try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 150_000_000)

        let all = box.events.withLock { $0 }
        let received = Array(all[consumed...])
        consumed = all.count
        #expect(
          received == injectionCase.expected,
          "case \(injectionCase.name): expected \(injectionCase.expected), got \(received)"
        )
      }
    }
  }

#endif
