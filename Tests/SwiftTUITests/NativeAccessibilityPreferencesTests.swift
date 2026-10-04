#if os(macOS) && canImport(AppKit)
  import AppKit
  import Testing
  @_spi(Testing) import SwiftTUITestSupport
  @testable import SwiftTUICore
  @testable import SwiftTUIRuntime

  @MainActor
  @Suite struct NativeAccessibilityPreferencesTests {
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
