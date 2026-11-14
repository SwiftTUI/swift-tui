#if !os(Windows)
  import Foundation
  import SwiftTUIAndroidHost
  @_spi(Testing) import SwiftTUICore
  @_spi(Runners) import SwiftTUIRuntime
  import Testing

  /// The `swift_tui_android_text_input` ingress end to end: C ABI, record
  /// parsing, the run loop's action route, the controls' editing state, and
  /// the frame fields the Kotlin host mirrors (`value`, `textSelection`,
  /// `accessibilityActionResponse`).
  @MainActor
  @Suite(.timeLimit(.minutes(2)))
  struct AndroidTextInputTests {
    @Test
    func android_text_input_abi_carries_composition_selection_and_commit() async throws {
      let fixture = try await TextInputFixture()
      defer { swift_tui_android_destroy(fixture.handle) }

      // Pre-edit text in the middle of existing text.
      try #require(fixture.textInput(1, "前ni后", anchor: 3, head: 3, composition: (1, 3)) == 1)
      var frame = await fixture.frame(acknowledging: 1)
      #expect(frame.semantics.accessibilityActionResponse?.result == .accepted)
      #expect(frame.raster.lines.joined().contains("Echo 前ni后"))
      #expect(fixture.markedText(in: frame) == "ni")
      var record = try fixture.copyRecord()
      var node = try fixture.editorNode(in: record)
      #expect((node["value"] as? [String: Any])?["value"] as? String == "前ni后")
      #expect(node["textSelection"] as? [Int] == [3, 3])
      #expect(
        (record["accessibilityActionResponse"] as? [String: Any])?["requestID"] as? String == "1")

      // The candidate replaces the marked range; the suffix and caret hold.
      try #require(fixture.textInput(2, "前你好后", anchor: 3, head: 3, composition: nil) == 1)
      frame = await fixture.frame(acknowledging: 2)
      #expect(frame.raster.lines.joined().contains("Echo 前你好后"))
      #expect(fixture.markedText(in: frame) == "")
      record = try fixture.copyRecord()
      node = try fixture.editorNode(in: record)
      #expect(node["textSelection"] as? [Int] == [3, 3])

      // Existing byte input still edits at the caret the host placed.
      Array("!".utf8).withUnsafeBufferPointer {
        unsafe swift_tui_android_send_input(fixture.handle, $0.baseAddress, Int32($0.count))
      }
      frame = await fixture.host.surface.waitForFrame {
        $0.raster.lines.joined().contains("Echo 前你好!后")
      }
      #expect(fixture.markedText(in: frame) == "")

      // A supplementary-plane emoji: UTF-16 offsets, one Character.
      try #require(
        fixture.textInput(3, "前你好!😀后", anchor: 6, head: 6, composition: (4, 6)) == 1)
      frame = await fixture.frame(acknowledging: 3)
      #expect(fixture.markedText(in: frame) == "😀")
      node = try fixture.editorNode(in: try fixture.copyRecord())
      #expect(node["textSelection"] as? [Int] == [6, 6])

      // Cancellation: the input method removes its pre-edit text.
      try #require(fixture.textInput(4, "前你好!后", anchor: 4, head: 4, composition: nil) == 1)
      frame = await fixture.frame(acknowledging: 4)
      #expect(frame.raster.lines.joined().contains("Echo 前你好!后"))
      #expect(fixture.markedText(in: frame) == "")

      // A stale target is refused by the runtime and acknowledged as such.
      try #require(
        fixture.textInput(5, "x", anchor: 1, head: 1, composition: nil, target: "removed") == 1)
      frame = await fixture.frame(acknowledging: 5)
      #expect(frame.semantics.accessibilityActionResponse?.result == .staleTarget)
      #expect(frame.raster.lines.joined().contains("Echo 前你好!后"))
    }

    @Test
    func android_text_input_abi_rejects_malformed_ingress() async throws {
      let fixture = try await TextInputFixture()
      defer { swift_tui_android_destroy(fixture.handle) }
      let target = fixture.encodedTarget
      for invalid in [
        "textInput:1:\(target):a:1:1:-1:-1\n",  // no RS introducer
        "\u{1E}textInput:1:\(target):a:1:1:-1:-1",  // no terminator
        "\u{1E}textInput:1:\(target):a:1:1\n",  // no composition fields
        "\u{1E}textInput:1:\(target):a:1:1:1:0\n",  // reversed composition
        "\u{1E}textInput:1:\(target):%FF:1:1:-1:-1\n",  // not UTF-8
        "\u{1E}textInput:1:\(target):a:1:1:-1:-1\nextra\n",
        "\u{1E}accessibility:1:\(target):activate\n",  // another ingress's record
      ] {
        #expect(fixture.send(invalid) == 0, "\(invalid.debugDescription)")
      }
      #expect(swift_tui_android_text_input(fixture.handle, nil, 1) == 0)
      #expect(swift_tui_android_text_input(-1, nil, 0) == 0)
      let one: [UInt8] = [0]
      one.withUnsafeBufferPointer {
        #expect(unsafe swift_tui_android_text_input(fixture.handle, $0.baseAddress, .max) == 0)
      }
      // Nothing malformed reached the editor.
      let frame = await fixture.host.surface.waitForFrame { _ in true }
      #expect(!frame.raster.lines.joined().contains("Echo a"))

      // A stopped run refuses edits, like every other input.
      swift_tui_android_stop(fixture.handle)
      #expect(fixture.send("\u{1E}textInput:9:\(target):a:1:1:-1:-1\n") == 0)
    }

    @Test
    func android_abi_advertises_the_text_input_operation() {
      var bytes = [UInt8](repeating: 0, count: 32)
      let size = bytes.withUnsafeMutableBufferPointer {
        unsafe swift_tui_android_get_abi_info($0.baseAddress, 32)
      }
      #expect(size == 32)
      let operations = bytes[24..<28].enumerated().reduce(UInt32(0)) {
        $0 | UInt32($1.element) << (8 * UInt32($1.offset))
      }
      // Bit 7: SWIFT_TUI_ANDROID_OP_TEXT_INPUT. Earlier bits are unchanged.
      #expect(operations & (1 << 7) != 0)
      #expect(operations & 0b11111 == 0b11111)
    }
  }

  @MainActor
  private struct TextInputFixture {
    let host: AndroidHostSceneHost
    let handle: Int64
    let encodedTarget: String

    init() async throws {
      host = try AndroidHostSceneHost(app: AndroidTextInputApp())
      handle = AndroidHostHandleRegistry.register(host)
      host.start()
      let initial = await host.surface.waitForFrame {
        $0.semantics.accessibilityNodes.contains { $0.label == "Name" && $0.actionTarget != nil }
      }
      let target = try #require(
        initial.semantics.accessibilityNodes.first { $0.label == "Name" }?.actionTarget)
      encodedTarget = try #require(
        target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
      // Keyboard focus, as a tap on the field gives it on the device.
      let focus = Array("\u{1E}accessibility:\(encodedTarget):focus\n".utf8)
      let admitted = focus.withUnsafeBufferPointer {
        unsafe swift_tui_android_accessibility_action(handle, $0.baseAddress, Int32($0.count))
      }
      try #require(admitted == 1)
      _ = await host.surface.waitForFrame { [host] _ in host.focusPresentation.prefersTextInput }
    }

    func send(_ record: String) -> Int32 {
      Array(record.utf8).withUnsafeBufferPointer {
        unsafe swift_tui_android_text_input(handle, $0.baseAddress, Int32($0.count))
      }
    }

    func textInput(
      _ id: UInt64, _ text: String, anchor: Int, head: Int, composition: (Int, Int)?,
      target: String? = nil
    ) throws -> Int32 {
      let encodedText = try #require(
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
      let range = composition.map { "\($0.0):\($0.1)" } ?? "-1:-1"
      return send(
        "\u{1E}textInput:\(id):\(target ?? encodedTarget):\(encodedText):\(anchor):\(head):\(range)\n"
      )
    }

    func frame(acknowledging id: UInt64) async -> SemanticHostFrame {
      await host.surface.waitForFrame {
        $0.semantics.accessibilityActionResponse?.requestID == id
      }
    }

    /// The underlined characters of a frame, in reading order.
    func markedText(in frame: SemanticHostFrame) -> String {
      var marked = ""
      for row in frame.raster.cells {
        for cell in row where cell.continuationLeadX == nil {
          if cell.style?.underlineStyle != nil { marked.append(cell.character) }
        }
      }
      return marked
    }

    /// The latest frame as the Kotlin host receives it across the copy ABI.
    func copyRecord() throws -> [String: Any] {
      let needed = swift_tui_android_copy_latest_frame(handle, nil, 0)
      var bytes = [UInt8](repeating: 0, count: Int(needed))
      let copied = bytes.withUnsafeMutableBufferPointer {
        unsafe swift_tui_android_copy_latest_frame(handle, $0.baseAddress, Int32($0.count))
      }
      try #require(copied == needed && needed > 0)
      let record = String(decoding: bytes, as: UTF8.self)
      try #require(record.hasPrefix("\u{1E}surface:"))
      return try #require(
        try JSONSerialization.jsonObject(
          with: Data(record.dropFirst("\u{1E}surface:".count).utf8)) as? [String: Any])
    }

    func editorNode(in record: [String: Any]) throws -> [String: Any] {
      let tree = try #require(record["accessibilityTree"] as? [[String: Any]])
      return try #require(tree.first { $0["label"] as? String == "Name" })
    }
  }

  @MainActor
  private struct AndroidTextInputApp: App {
    var body: some Scene { WindowGroup { AndroidTextInputControls() } }
  }

  @MainActor
  private struct AndroidTextInputControls: View {
    @State private var name = "前后"
    var body: some View {
      VStack(alignment: .leading) {
        TextField("Name", text: $name)
        Text("Echo \(name)")
      }
    }
  }
#endif
