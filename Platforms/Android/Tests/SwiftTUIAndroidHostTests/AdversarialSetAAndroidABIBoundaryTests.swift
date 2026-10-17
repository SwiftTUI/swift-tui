#if !os(Windows)
  import Foundation
  @_spi(Runners) import SwiftTUIRuntime
  @_spi(Testing) import SwiftTUITestSupport
  import Testing

  @testable import SwiftTUIAndroidHost

  @MainActor
  @Suite(.serialized, .timeLimit(.minutes(1)))
  struct AdversarialSetAAndroidABIBoundaryTests {
    @Test func setA963DestroyingOneABIHandleCannotRetireAnotherHost() throws {
      // Hypothesis: removing a handle reuses or clears a neighboring host's registry entry and pending delivery.
      let first = try makeHost()
      let second = try makeHost()
      let firstHandle = AndroidHostHandleRegistry.register(first)
      let secondHandle = AndroidHostHandleRegistry.register(second)
      defer {
        swift_tui_android_destroy(firstHandle)
        swift_tui_android_destroy(secondHandle)
      }
      try second.surface.writeClipboard("survivor")
      #expect(firstHandle != secondHandle)
      swift_tui_android_destroy(firstHandle)
      #expect(AndroidHostHandleRegistry.host(for: firstHandle) == nil)
      #expect(AndroidHostHandleRegistry.host(for: secondHandle) === second)
      swift_tui_android_resize(firstHandle, 1, 1, 2, 2)
      #expect(second.surfaceSize == .init(width: 80, height: 24))
      #expect(swift_tui_android_copy_clipboard_text(secondHandle, nil, 0) == 8)
      #expect(swift_tui_android_copy_clipboard_text(firstHandle, nil, 0) == 0)
    }

    @Test func setA964InvalidInitialSurfaceSizeFallsBackBeforeHostAllocation() throws {
      // Hypothesis: Android's style initializer bypasses the host-wire grid budget before creating its presentation surface.
      let invalid = try makeHost(style: .init(initialSurfaceSize: .init(width: Int.max, height: 2)))
      #expect(invalid.surfaceSize == .init(width: 80, height: 24))
      #expect(invalid.surface.surfaceSize == invalid.surfaceSize)
      let admitted = try makeHost(style: .init(initialSurfaceSize: .init(width: 256, height: 256)))
      #expect(admitted.surfaceSize == .init(width: 256, height: 256))
      #expect(admitted.surface.surfaceSize == admitted.surfaceSize)
    }

    @Test func setA965RejectedResizeCannotPartiallyApplyItsGridOrMetrics() throws {
      // Hypothesis: grid publication happens before metric validation and leaves the host and pointer capabilities inconsistent.
      let host = try makeHost()
      host.resize(columns: 23, rows: 11, cellPixelWidth: 9, cellPixelHeight: 18)
      let originalPointers = host.surface.pointerInputCapabilities
      host.resize(columns: 45, rows: 19, cellPixelWidth: .infinity, cellPixelHeight: 20)
      #expect(host.surfaceSize == .init(width: 23, height: 11))
      #expect(host.surface.surfaceSize == host.surfaceSize)
      #expect(host.cellPixelSize == .init(width: 9, height: 18))
      #expect(host.surface.graphicsCapabilities.cellPixelSize == host.cellPixelSize)
      #expect(host.surface.pointerInputCapabilities == originalPointers)
    }

    @Test func setA966ClipboardABICopiesUTF8BytesIncludingEmbeddedNUL() throws {
      // Hypothesis: the native boundary reports Character count or copies a C-string prefix instead of the complete UTF-8 payload.
      let host = try makeHost()
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      let text = "漢\0👩‍💻é"
      try host.surface.writeClipboard(text)
      let required = swift_tui_android_copy_clipboard_text(handle, nil, 0)
      #expect(required == Int32(text.utf8.count))
      var bytes = [UInt8](repeating: 0xA5, count: Int(required) + 2)
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_clipboard_text(handle, buffer.baseAddress, required)
      }
      #expect(copied == required)
      #expect(Array(bytes.prefix(Int(required))) == Array(text.utf8))
      #expect(Array(bytes.suffix(2)) == [0xA5, 0xA5])
      #expect(swift_tui_android_copy_clipboard_text(handle, nil, 0) == 0)
    }

    @Test func setA967UndersizedClipboardDeliveryNeitherWritesNorConsumes() throws {
      // Hypothesis: a failed copy partially writes caller memory or drains the pending clipboard despite insufficient capacity.
      let host = try makeHost()
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      try host.surface.writeClipboard("payload")
      var bytes = [UInt8](repeating: 0xA5, count: 7)
      let needed = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_clipboard_text(handle, buffer.baseAddress, 6)
      }
      #expect(needed == 7)
      #expect(bytes == [UInt8](repeating: 0xA5, count: 7))
      #expect(swift_tui_android_copy_clipboard_text(handle, nil, 0) == 7)
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe swift_tui_android_copy_clipboard_text(handle, buffer.baseAddress, 7)
      }
      #expect(copied == 7)
      #expect(bytes == Array("payload".utf8))
      #expect(swift_tui_android_copy_clipboard_text(handle, nil, 0) == 0)
    }

    @Test func setA968ClipboardKeepsTheLatestNonemptyWriteAcrossAQuery() throws {
      // Hypothesis: a size query pins stale clipboard content or an empty write erases a deliverable later update.
      let host = try makeHost()
      try host.surface.writeClipboard("old")
      #expect(unsafe host.copyPendingClipboardText(to: nil, capacity: 0) == 3)
      try host.surface.writeClipboard("newer payload")
      try host.surface.writeClipboard("")
      var oldCapacity = [UInt8](repeating: 0xA5, count: 3)
      let needed = oldCapacity.withUnsafeMutableBufferPointer { buffer in
        unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: buffer.count)
      }
      #expect(needed == 13)
      #expect(oldCapacity == [0xA5, 0xA5, 0xA5])
      var bytes = [UInt8](repeating: 0, count: needed)
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe host.copyPendingClipboardText(to: buffer.baseAddress, capacity: buffer.count)
      }
      #expect(copied == 13)
      #expect(String(decoding: bytes, as: UTF8.self) == "newer payload")
    }

    @Test func setA969FrameCopyDeliversTheFrameWhoseSizeWasQueried() throws {
      // Hypothesis: a newer committed frame replaces scratch between the ABI's size and copy legs, straddling two records.
      let host = try makeHost()
      try present(host, sequence: 1, lines: ["aaaa", "bbbb"])
      let required = unsafe host.copyLatestFrameBytes(to: nil, capacity: 0)
      try #require(required > 0)
      try present(host, sequence: 2, lines: ["cccc", "dddd"])
      let first = try record(copy(host, capacity: required))
      #expect(first["sequence"] as? Int == 1)
      let next = try record(queriedCopy(host))
      #expect(next["sequence"] as? Int == 2)
    }

    @Test func setA970AbandonedSizeQueryCannotAdvanceTheDeliveredDeltaBaseline() throws {
      // Hypothesis: encoding a never-copied candidate ratchets the baseline, so the first delivered frame depends on missing bytes.
      let host = try makeHost()
      let declared = host.declareCapabilities(json: #"{"acceptsDeltaFrames":true}"#)
      #expect(declared)
      try present(host, sequence: 1, lines: ["aaaa", "bbbb"])
      let abandonedSize = unsafe host.copyLatestFrameBytes(to: nil, capacity: 0)
      #expect(abandonedSize > 0)
      try present(host, sequence: 2, lines: ["cccc", "dddd"])
      let delivered = try record(queriedCopy(host))
      #expect(delivered["sequence"] as? Int == 2)
      #expect(delivered["gen"] as? Int == 1)
      #expect(delivered["encoding"] == nil)
      #expect(host.consumedFrameEncodeCount == 2)
    }

    @Test func setA971RepeatedDeliveryDoesNotPromoteTheSameCandidateTwice() throws {
      // Hypothesis: replaying cached bytes advances wire generation again even though no new frame was encoded.
      let host = try makeHost()
      let declared = host.declareCapabilities(json: #"{"acceptsDeltaFrames":true}"#)
      #expect(declared)
      try present(host, sequence: 1, lines: ["aaaa", "bbbb"])
      let first = try queriedCopy(host)
      let copiedAgain = try copy(host, capacity: first.count)
      #expect(copiedAgain == first)
      let queriedAgain = try queriedCopy(host)
      #expect(queriedAgain == first)
      #expect(host.consumedFrameEncodeCount == 1)
      try present(host, sequence: 2, lines: ["aaax", "bbbb"], damageRow: 0)
      let next = try record(queriedCopy(host))
      #expect(next["gen"] as? Int == 2)
      #expect(next["encoding"] as? String == "delta")
    }

    @Test func setA972AbandonedCandidateDamageRejoinsLaterUnconsumedDamage() throws {
      // Hypothesis: replacing an unconsumed scratch discards the damage it had removed from the pending accumulator.
      let host = try makeHost()
      let declared = host.declareCapabilities(json: #"{"acceptsDeltaFrames":true}"#)
      #expect(declared)
      try present(host, sequence: 1, lines: ["aaaa", "bbbb"])
      _ = try queriedCopy(host)
      try present(host, sequence: 2, lines: ["xaaX", "bbbb"], damageRow: 0)
      let abandonedSize = unsafe host.copyLatestFrameBytes(to: nil, capacity: 0)
      #expect(abandonedSize > 0)
      try present(host, sequence: 3, lines: ["xaaX", "ybbY"], damageRow: 1)
      let delivered = try record(queriedCopy(host))
      #expect(delivered["sequence"] as? Int == 3)
      #expect(delivered["gen"] as? Int == 2)
      #expect(delivered["encoding"] as? String == "delta")
      let rows = try #require(delivered["deltaRows"] as? [[Any]])
      #expect(rows.compactMap { $0.first as? Int }.sorted() == [0, 1])
    }

    @Test func setA973StoppingAStartedHostDoesNotReopenCapabilityNegotiation() async throws {
      // Hypothesis: stopping clears the capability lock along with the run task and permits a mid-lifetime record-shape change.
      let probe = AndroidABIBoundaryProbe()
      let host = try AndroidHostSceneHost(app: AndroidABIBoundaryApp(probe: probe))
      let declared = host.declareCapabilities(json: #"{"acceptsDeltaFrames":true}"#)
      #expect(declared)
      host.start()
      do {
        await probe.appeared.wait()
        try Task.checkCancellation()
        try #require(host.latestFrame != nil)
        _ = try await host.session.stopAndWait()
      } catch {
        _ = try? await host.session.stopAndWait()
        throw error
      }
      let redeclared = host.declareCapabilities(json: #"{"acceptsDeltaFrames":false}"#)
      #expect(!redeclared)
      #expect(host.wireCapabilities.acceptsDeltaFrames)
    }

    @Test func setA974BorrowedInputBytesDoNotOutliveTheABICall() async throws {
      // Hypothesis: deferred input delivery retains the caller's borrowed buffer instead of owning the bytes before the ABI returns.
      let probe = AndroidABIBoundaryProbe()
      let host = try AndroidHostSceneHost(app: AndroidABIBoundaryInputApp(probe: probe))
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      host.start()
      do {
        await probe.appeared.wait()
        try Task.checkCancellation()
        try #require(host.focusPresentation.semantics == .activate)
        let target = try #require(
          host.latestFrame?.semantics.accessibilityNodes.first { $0.role == .textField }?
            .actionTarget)
        host.session.send(.accessibility(.init(target: target, action: .focus, requestID: 974)))
        // The focused field's lifecycle task starts after its frame commits,
        // so its signal also witnesses the semantic focus acknowledgement.
        await probe.focusCommitted.wait()
        try Task.checkCancellation()
        #expect(host.latestFrame?.semantics.accessibilityActionResponse?.requestID == 974)
        #expect(host.latestFrame?.semantics.accessibilityActionResponse?.result == .accepted)
        #expect(host.focusPresentation.semantics == .edit)
        var borrowed = Array("abc".utf8)
        borrowed.withUnsafeBufferPointer { buffer in
          unsafe swift_tui_android_send_input(handle, buffer.baseAddress, Int32(buffer.count))
        }
        // Reuse the caller's storage before yielding to the run loop's input consumer.
        for index in borrowed.indices { borrowed[index] = 0x78 }
        #expect(borrowed == Array("xxx".utf8))
        await probe.inputChanged.wait(until: { probe.inputWrites >= 3 })
        try Task.checkCancellation()
        _ = try await host.session.stopAndWait()
      } catch {
        _ = try? await host.session.stopAndWait()
        throw error
      }
      #expect(probe.text == "abc")
      #expect(probe.inputWrites == 3)
    }

    @Test func setA975SemanticActionABIRejectsPartialOrConcatenatedRecords() throws {
      // Hypothesis: a complete-record ABI accepts only the first command of a concatenated buffer or treats a partial frame as complete.
      let host = try makeHost()
      let handle = AndroidHostHandleRegistry.register(host)
      defer { swift_tui_android_destroy(handle) }
      func submit(_ text: String) -> Int32 {
        Array(text.utf8).withUnsafeBufferPointer { buffer in
          unsafe swift_tui_android_accessibility_action(
            handle, buffer.baseAddress, Int32(buffer.count))
        }
      }
      let complete = "\u{1E}accessibility:975:future-target:activate\n"
      let withoutTerminator = submit(String(complete.dropLast()))
      #expect(withoutTerminator == 0)
      let withoutIntroducer = submit(String(complete.dropFirst()))
      #expect(withoutIntroducer == 0)
      let concatenated = submit(complete + complete)
      #expect(concatenated == 0)
      let accepted = submit(complete)
      #expect(accepted == 1)
    }

    private func makeHost(style: AndroidHostStyle = .default) throws -> AndroidHostSceneHost {
      try AndroidHostSceneHost(
        app: AndroidABIBoundaryApp(probe: AndroidABIBoundaryProbe()), style: style)
    }

    private func present(
      _ host: AndroidHostSceneHost, sequence: UInt64, lines: [String], damageRow: Int? = nil
    ) throws {
      _ = try host.surface.present(
        SemanticHostFrame(
          sequence: sequence, raster: RasterSurface(size: .init(width: 4, height: 2), lines: lines),
          semantics: .init(), focusedIdentity: nil,
          rasterDamage: damageRow.map {
            PresentationDamage(textRows: [.init(row: $0, columnRanges: [0..<4])])
          }))
      #expect(host.latestFrame?.sequence == sequence)
    }

    private func copy(_ host: AndroidHostSceneHost, capacity: Int) throws -> [UInt8] {
      try #require(capacity > 0)
      var bytes = [UInt8](repeating: 0xA5, count: capacity)
      let copied = bytes.withUnsafeMutableBufferPointer { buffer in
        unsafe host.copyLatestFrameBytes(to: buffer.baseAddress, capacity: buffer.count)
      }
      try #require(copied == capacity)
      return bytes
    }

    private func queriedCopy(_ host: AndroidHostSceneHost) throws -> [UInt8] {
      let required = unsafe host.copyLatestFrameBytes(to: nil, capacity: 0)
      return try copy(host, capacity: required)
    }

    private func record(_ bytes: [UInt8]) throws -> [String: Any] {
      let string = String(decoding: bytes, as: UTF8.self)
      try #require(string.hasPrefix("\u{1E}surface:") && string.hasSuffix("\n"))
      return try #require(
        JSONSerialization.jsonObject(with: Data(string.dropFirst("\u{1E}surface:".count).utf8))
          as? [String: Any])
    }
  }

  @MainActor
  private final class AndroidABIBoundaryProbe {
    var appearances = 0
    var calls = 0
    var text = ""
    var inputWrites = 0
    let appeared = AsyncEvent()
    let focusCommitted = AsyncEvent()
    let inputChanged = MainActorConditionSignal()
  }

  @MainActor
  private struct AndroidABIBoundaryApp: App {
    let probe: AndroidABIBoundaryProbe?
    nonisolated init() { probe = nil }
    init(probe: AndroidABIBoundaryProbe) { self.probe = probe }
    var body: some Scene {
      WindowGroup("ABI boundary") {
        Button("Activate") { probe?.calls += 1 }.onAppear {
          probe?.appearances += 1
          probe?.appeared.fire()
        }
      }
    }
  }

  @MainActor
  private struct AndroidABIBoundaryInputApp: App {
    let probe: AndroidABIBoundaryProbe?
    nonisolated init() { probe = nil }
    init(probe: AndroidABIBoundaryProbe) { self.probe = probe }
    var body: some Scene {
      WindowGroup("Borrowed input") {
        AndroidABIBoundaryInputField(probe: probe)
      }
    }
  }

  private struct AndroidABIBoundaryInputField: View {
    let probe: AndroidABIBoundaryProbe?
    @FocusState private var isFocused: Bool
    var body: some View {
      VStack {
        Button("Initial focus") {}
        TextField(
          "ABI input",
          text: Binding(
            get: { probe?.text ?? "" },
            set: {
              probe?.text = $0
              probe?.inputWrites += 1
              probe?.inputChanged.notify()
            })
        )
        .focused($isFocused)
        .task(id: isFocused) {
          if isFocused { probe?.focusCommitted.fire() }
        }
      }
      .onAppear { probe?.appeared.fire() }
    }
  }
#endif
