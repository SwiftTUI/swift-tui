import Synchronization
import Testing

@testable import SwiftTUIRuntime

@Suite("set F signal completion reentry")
struct AdversarialSetFSignalCompletionTests {
  @Test(arguments: Array(61...70))
  func completionBoundary(id: Int) {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    defer { reader.finish() }
    switch id {
    case 61, 62:
      let values = id == 61 ? ["A", "B"] : ["A", "B", "C"]
      for value in values { reader.send(value) }
      let stop = id == 61 ? "A" : "B"
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append(value) }
        if value == stop { reader?.finish() }
      } onFinish: {
        trace.withLock { $0.append("end") }
      }
      let allowed =
        id == 61
        ? [["A", "end"], ["A", "B", "end"]]
        : [["A", "B", "end"], ["A", "B", "C", "end"]]
      let observed = trace.withLock { $0 }
      print("F4_PROBE setF0\(id) \(observed)")
      withKnownIssue(
        "setF0\(id): a buffered signal is delivered after the end notification (observed \(observed)); InProcessSignalReader.installDirectHandler flushes a local copy of the pending signals outside the lock and never re-checks isFinished between deliveries, so a handler that calls finish() still receives the remaining buffered signals; contract: RunLoopSessionTypes.swift:148-190 — the direct end notification occurs once and no value callback may follow it; STUI-1192; adjacent STUI-1030 (same trace fixed in InjectedTerminalInputReader)"
      ) {
        #expect(allowed.contains(observed))
      }
    case 63:
      reader.send("A")
      reader.send("B")
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append(value) }
        if value == "A" { reader?.send("N") }
        if value == "N" { reader?.finish() }
      } onFinish: {
        trace.withLock { $0.append("end") }
      }
      let observed = trace.withLock { $0 }
      print("F4_PROBE setF063 \(observed)")
      withKnownIssue(
        "setF063: a buffered signal is delivered after the end notification a reentrant send triggered (observed \(observed)); InProcessSignalReader.installDirectHandler flushes a local copy of the pending signals outside the lock and never re-checks isFinished between deliveries, so a reentrant finish() during the flush still leaves the remaining buffered signal delivered; contract: RunLoopSessionTypes.swift:148-190 — the direct end notification occurs once and no value callback may follow it; STUI-1192; adjacent STUI-1030 (same trace fixed in InjectedTerminalInputReader)"
      ) {
        #expect([["A", "N", "end"], ["A", "N", "B", "end"]].contains(observed))
      }
    case 64:
      reader.send("A")
      reader.send("B")
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append(value) }
        if value == "A" { reader?.clearDirectHandler() }
      } onFinish: {
        trace.withLock { $0.append("end") }
      }
      reader.send("C")
      reader.finish()
      let observed = trace.withLock { $0 }
      print("F4_PROBE setF064 \(observed)")
      // The pending-array ownership is a probe; clear must detach end delivery.
      #expect(!observed.contains("end"))
    case 65:
      reader.send("A")
      reader.send("B")
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append("old:\(value)") }
        if value == "A" {
          reader?.installDirectHandler { name in
            trace.withLock { $0.append("new:\(name)") }
          } onFinish: {
            trace.withLock { $0.append("new:end") }
          }
        }
      } onFinish: {
        trace.withLock { $0.append("old:end") }
      }
      reader.send("C")
      reader.finish()
      let observed = trace.withLock { $0 }
      print("F4_PROBE setF065 \(observed)")
      #expect(Array(observed.suffix(2)) == ["new:C", "new:end"])
      #expect(!observed.contains("old:end"))
    case 66, 67:
      reader.installDirectHandler { value in
        trace.withLock { $0.append(value) }
      } onFinish: { [weak reader] in
        trace.withLock { $0.append("end") }
        if id == 66 { reader?.finish() } else { reader?.send("N") }
      }
      reader.finish()
      #expect(trace.withLock { $0 } == ["end"])
    case 68:
      reader.installDirectHandler { value in
        trace.withLock { $0.append("old:\(value)") }
      } onFinish: { [weak reader] in
        trace.withLock { $0.append("old:end") }
        reader?.installDirectHandler { value in
          trace.withLock { $0.append("new:\(value)") }
        } onFinish: {
          trace.withLock { $0.append("new:end") }
        }
      }
      reader.finish()
      reader.send("N")
      reader.finish()
      #expect(trace.withLock { $0 } == ["old:end", "new:end"])
    case 69:
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append(value) }
        reader?.finish()
      } onFinish: {
        trace.withLock { $0.append("end") }
      }
      reader.send("A")
      reader.send("B")
      #expect(trace.withLock { $0 } == ["A", "end"])
    default:
      reader.installDirectHandler { [weak reader] value in
        trace.withLock { $0.append("old:\(value)") }
        reader?.installDirectHandler { name in
          trace.withLock { $0.append("new:\(name)") }
        } onFinish: {
          trace.withLock { $0.append("new:end") }
        }
      } onFinish: {
        trace.withLock { $0.append("old:end") }
      }
      reader.send("A")
      reader.send("B")
      reader.finish()
      #expect(trace.withLock { $0 } == ["old:A", "new:B", "new:end"])
    }
  }
}
