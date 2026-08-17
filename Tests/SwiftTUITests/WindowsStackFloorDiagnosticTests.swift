import Testing

@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime

@MainActor
@Suite
struct WindowsStackFloorDiagnosticTests {
  @Test("full-engine stack floor matches the POSIX main-thread reserve")
  func fullEngineStackFloorMatchesPOSIXReserve() {
    // The ratified Stage 6 item-9 floor: POSIX main threads get 8 MiB and
    // the resolve descent is budgeted against it. Changing this constant
    // changes which Windows executables silently degrade — it must not
    // drift by accident.
    #expect(fullEngineStackReserveFloor == 8 << 20)
  }

  @Test("stack-floor diagnostic names the /STACK remedy")
  func stackFloorDiagnosticNamesRemedy() {
    let message = WindowsStackFloorDiagnostic.message(
      reserveBytes: 1 << 20,
      floorBytes: 8 << 20
    )

    #expect(message.contains("1 MiB"))
    #expect(message.contains("8 MiB"))
    #expect(message.contains("stack-lean"))
    #expect(message.contains("swift build -Xlinker /STACK:16777216"))
    #expect(message.contains(".when(platforms: [.windows])"))
  }

  @Test("stack-floor session issue is nil off Windows and in full-engine runs")
  func stackFloorSessionIssueIsNilOffWindows() {
    #if os(Windows)
      // A debug test runner linked with the default 1 MiB reserve arms the
      // floor check itself, so the issue tracks the arming flag exactly.
      #if DEBUG
        #expect(
          (WindowsStackFloorDiagnostic.sessionIssue() != nil)
            == stackLeanArmedByWindowsStackFloor
        )
      #else
        #expect(WindowsStackFloorDiagnostic.sessionIssue() == nil)
      #endif
    #else
      // On POSIX the floor check never arms.
      #expect(WindowsStackFloorDiagnostic.sessionIssue() == nil)
    #endif
  }
}
