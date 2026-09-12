import Testing

@testable import SwiftTUIRuntime

@Suite(.timeLimit(.minutes(1)))
struct TerminalInputPollGateTests {
  @Test("nested poll suspensions exclude reads until the final resume")
  func nestedSuspensions() {
    let gate = TerminalInputPollGate()
    #expect(gate.read { 1 } == 1)
    gate.suspend()
    gate.suspend()
    #expect(gate.read { 2 } == nil)
    gate.resume()
    #expect(gate.read { 3 } == nil)
    gate.resume()
    #expect(gate.read { 4 } == 4)
  }

}
