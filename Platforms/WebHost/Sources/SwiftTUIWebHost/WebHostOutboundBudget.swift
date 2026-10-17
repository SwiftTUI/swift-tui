import SwiftTUIRuntime

/// Each outbound boundary admits at most 32 records and one maximum encoded
/// wire record (4 MiB plus its terminating LF), including
/// records being written. Overflow ends the connection; encoded deltas and
/// reliable controls are never evicted to make room for newer records.
package struct WebHostOutboundBudget: Sendable {
  package static let recordLimit = 32
  package static let byteLimit = HostWireBudget.recordBytes + 1

  package private(set) var records = 0
  package private(set) var bytes = 0

  package mutating func admit(_ byteCount: Int) -> Bool {
    guard byteCount >= 0, records < Self.recordLimit, byteCount <= Self.byteLimit - bytes else {
      return false
    }
    records += 1
    bytes += byteCount
    return true
  }

  package mutating func release(_ byteCount: Int) {
    records -= 1
    bytes -= byteCount
  }
}
