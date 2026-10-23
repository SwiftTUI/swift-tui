#if os(macOS) && canImport(AppKit)
  import AppKit
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUICore
  @testable import SwiftTUIRuntime
  @testable import SwiftTUIViews

  @MainActor
  @Suite struct NativeAccessibilityPreferencesTests {
    @Test func nativeNotificationWakesTheRuntimeScheduler() async throws {
      let scheduler = FrameScheduler()
      let root = testIdentity("NativePreferenceWake")
      let loop = SwiftTUIRuntime.RunLoop(
        rootIdentity: root, presentationSurface: host(),
        terminalInputReader: PreferenceEmptyInput(),
        scheduler: scheduler,
        stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
        focusTracker: FocusTracker(invalidationIdentities: [root]),
        viewBuilder: { _, _ in Text("Idle") })
      defer { loop.lifecycleCoordinator.shutdown() }
      let signal = MainActorConditionSignal()
      let wakes = LockedBox(0)
      scheduler.setWakeHandler {
        wakes.withLock { $0 += 1 }
        Task { @MainActor in signal.notify() }
      }
      NSWorkspace.shared.notificationCenter.post(
        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
      try await withStageBudget(
        "native preference wake", within: .init(stages: 1), on: ManualStageClock()
      ) {
        await signal.wait { wakes.value > 0 }
      }
      #expect(wakes.value > 0)
      withExtendedLifetime(loop) {}
    }

    private func host(environment: [String: String] = [:], tty: Bool = true) -> TerminalHost {
      TerminalHost(
        inputFileDescriptor: 0, outputFileDescriptor: 1,
        fallbackSize: .init(width: 80, height: 24),
        controller: PreferenceTestController(tty: tty), usesNativeAccessibilityPreferences: true,
        environment: environment)
    }

    @Test func remoteAndRedirectedSessionsDoNotInheritDesktopPreferences() {
      #expect(isLocalTerminalPreferenceSource(host()))
      for remote in ["SSH_CONNECTION", "SSH_CLIENT", "REMOTEHOST"] {
        let surface = host(environment: [remote: "remote"])
        #expect(!isLocalTerminalPreferenceSource(surface))
        #expect(nativeAccessibilityPreferences(for: surface) == .init())
        #expect(NativeAccessibilityPreferenceObserver(surface: surface, changed: {}) == nil)
      }
      #expect(!isLocalTerminalPreferenceSource(host(tty: false)))
    }

    @Test func localDisplayNotificationsWakeTheSession() async throws {
      let center = NotificationCenter()
      let signal = MainActorConditionSignal()
      var updates = 0
      let observer = try #require(
        NativeAccessibilityPreferenceObserver(
          surface: host(), notificationCenter: center
        ) {
          updates += 1
          signal.notify()
        })
      center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
      await signal.wait { updates == 1 }
      withExtendedLifetime(observer) { #expect(updates == 1) }
    }
  }

  private final class PreferenceEmptyInput: TerminalInputReading {
    func inputEvents() -> AsyncStream<InputEvent> { AsyncStream { $0.finish() } }
  }

  private final class PreferenceTestController: TerminalControlling {
    let tty: Bool
    init(tty: Bool) { self.tty = tty }
    func isATTY(_: Int32) -> Bool { tty }
    func enterRawMode(input: Int32, output: Int32) throws -> TerminalModeSnapshot { .init() }
    func restore(_: TerminalModeSnapshot, input: Int32, output: Int32) throws {}
    func windowSize(of: Int32) throws -> CellSize { .init(width: 80, height: 24) }
    func cellPixelSize(of: Int32) throws -> PixelSize? { nil }
    func write(_: String, to: Int32) throws {}
    func read(from: Int32, maxBytes: Int, timeoutMilliseconds: Int) throws -> [UInt8] { [] }
  }
#endif
