import SwiftTUIRuntime
import Testing

struct WASITerminalHandoffTests {
  @Test("WASI handoffs fail closed until stdin polling supports pause-and-ack")
  func platformAvailabilityMatchesExclusiveInputOwnership() {
    #if canImport(WASILibc)
      #expect(!terminalHandoffPlatformSupportsExclusiveInputOwnership)
    #else
      #expect(terminalHandoffPlatformSupportsExclusiveInputOwnership)
    #endif
  }
}
