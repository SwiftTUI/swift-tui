import SwiftTUIRuntime
import Testing

struct WASITerminalHandoffTests {
  @Test("WASI polling input can acknowledge exclusive ownership across a throwing operation")
  func pollingOwnershipIsRestoredAfterFailure() {
    let gate = TerminalInputPollGate()
    enum Failure: Error { case operation }
    func operation() throws {
      gate.suspend()
      defer { gate.resume() }
      #expect(gate.read { true } == nil)
      throw Failure.operation
    }
    #expect(throws: Failure.operation) { try operation() }
    #expect(gate.read { true } == true)
  }
}
