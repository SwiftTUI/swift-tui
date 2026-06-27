import SwiftTUICore
import SwiftTUIRuntime
import Testing

// The public error types across the framework share a four-conformance baseline
// (Error + Equatable + Sendable + CustomStringConvertible). The public-API
// inventory baseline tracks the `description` members but not the synthesized
// Equatable/Sendable conformances, so these tests pin the behaviour the
// inventory cannot — Equatable equality/inequality and a non-empty description —
// on the types brought up to the baseline in supplemental item #27.
@Suite("Public error-type conformance baseline")
struct PublicErrorConformanceTests {
  @Test("TerminalHostError is Equatable and self-describing")
  func terminalHostErrorConformances() {
    #expect(
      TerminalHostError.failedToWrite(errno: 9) == TerminalHostError.failedToWrite(errno: 9)
    )
    #expect(
      TerminalHostError.failedToWrite(errno: 9) != TerminalHostError.failedToWrite(errno: 5)
    )
    #expect(TerminalHostError.notATTY(fileDescriptor: 1).description.contains("TTY"))
    #expect(!TerminalHostError.failedToReadWindowSize(errno: 1).description.isEmpty)
  }

  @Test("ColorError and ColorResolutionError are Equatable and self-describing")
  func colorErrorConformances() {
    #expect(ColorError.invalidHexString("#zzz") == ColorError.invalidHexString("#zzz"))
    #expect(ColorError.invalidHexString("#zzz") != ColorError.invalidProfile("#zzz"))
    #expect(!ColorError.conversionFailure("x").description.isEmpty)
    #expect(ColorResolutionError.emptyGradient == ColorResolutionError.emptyGradient)
    #expect(!ColorResolutionError.emptyGradient.description.isEmpty)
  }
}
