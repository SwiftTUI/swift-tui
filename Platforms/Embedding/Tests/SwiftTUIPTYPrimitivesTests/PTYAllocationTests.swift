#if canImport(Darwin)
  import Darwin
  @testable import SwiftTUIPTYPrimitives
  import Testing

  @Suite("PTY allocation resilience")
  struct PTYAllocationTests {
    @Test("transient ENXIO is retried before returning a usable pair")
    func transientFailure() throws {
      var attempts = 0
      var pauses: [UInt32] = []
      let handles = try allocatePTYWithRetry(pause: { pauses.append($0) }) {
        () throws(PTYError) -> PTYHandles in
        attempts += 1
        if attempts < 3 { throw .allocationFailed(errno: ENXIO) }
        return try openPTY()
      }
      defer {
        closeFD(handles.masterFD)
        closeFD(handles.slaveFD)
      }
      #expect(attempts == 3)
      #expect(pauses == [1_000, 2_000])
      #expect(isatty(handles.slaveFD) == 1)
    }

    @Test(
      "persistent ENXIO is bounded and resource failures are not retried",
      arguments: [ENXIO, EMFILE, ENFILE, EACCES])
    func permanentFailure(failure: Int32) {
      var attempts = 0
      var pauses: [UInt32] = []
      do {
        _ = try allocatePTYWithRetry(pause: { pauses.append($0) }) {
          () throws(PTYError) -> PTYHandles in
          attempts += 1
          throw .allocationFailed(errno: failure)
        }
        Issue.record("allocation unexpectedly succeeded")
      } catch {
        #expect(error == .allocationFailed(errno: failure))
      }
      #expect(attempts == (failure == ENXIO ? 4 : 1))
      #expect(pauses == (failure == ENXIO ? [1_000, 2_000, 4_000] : []))
    }
  }
#endif
