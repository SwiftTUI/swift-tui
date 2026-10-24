import Synchronization
import Testing

@testable import SwiftTUIRuntime

/// In-process signal-reader delivery across raw-mode/transition windows and
/// render-suspension phase accounting (campaign two F4, setF086–setF100).
///
/// `RenderSuspensionDiagnostics` counts input queued only while a suspension
/// bracket is open and floors an unbalanced end at zero
/// (`Sources/SwiftTUIRuntime/RunLoop/RunLoopSessionTypes.swift:200-241`).
/// `InProcessSignalReader` buffers signals while no consumer is attached,
/// replays them to the next stream or direct handler, finishes exactly once,
/// and drops sends after finish
/// (`Sources/SwiftTUIRuntime/RunLoop/RunLoopSessionTypes.swift:77-198`;
/// contract counterpart to the stream finish, brief 02).
@Suite("set F signal and suspension phases", .serialized)
struct AdversarialSetFSignalPhaseTests {
  @Test("setF086 input outside a suspension bracket is not counted")
  func setF086InputOutsideSuspensionNotCounted() {
    let diagnostics = RenderSuspensionDiagnostics()
    #expect(!diagnostics.isSuspended)
    diagnostics.recordInputEventQueuedIfSuspended()
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 0)
  }

  @Test("setF087 a suspension bracket counts queued input and the drain resets it")
  func setF087SuspensionBracketCountsAndResets() {
    let diagnostics = RenderSuspensionDiagnostics()
    diagnostics.beginSuspension()
    #expect(diagnostics.isSuspended)
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.endSuspension()
    #expect(!diagnostics.isSuspended)
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 1)
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 0)
  }

  @Test("setF088 a nested suspension stays suspended until balanced and accumulates counts")
  func setF088NestedSuspensionAccumulates() {
    let diagnostics = RenderSuspensionDiagnostics()
    diagnostics.beginSuspension()
    diagnostics.beginSuspension()
    #expect(diagnostics.isSuspended)
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.endSuspension()
    #expect(diagnostics.isSuspended)
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.endSuspension()
    #expect(!diagnostics.isSuspended)
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 2)
  }

  @Test("setF089 an unbalanced end floors the depth at zero and a later begin still suspends")
  func setF089UnbalancedEndFloorsAtZero() {
    let diagnostics = RenderSuspensionDiagnostics()
    diagnostics.endSuspension()
    #expect(!diagnostics.isSuspended)
    diagnostics.beginSuspension()
    #expect(diagnostics.isSuspended)
  }

  @Test("setF090 the suspension-input drain resets the running count")
  func setF090DrainResetsCount() {
    let diagnostics = RenderSuspensionDiagnostics()
    diagnostics.beginSuspension()
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.recordInputEventQueuedIfSuspended()
    diagnostics.endSuspension()
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 3)
    #expect(diagnostics.drainInputEventsQueuedDuringSuspension() == 0)
  }

  @Test("setF091 signals buffered before a consumer replay in order to a later direct handler")
  func setF091BufferedSignalsReplayToDirectHandler() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.send("A")
    reader.send("B")
    reader.installDirectHandler { value in
      trace.withLock { $0.append(value) }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    #expect(trace.withLock { $0 } == ["A", "B"])
  }

  @Test("setF092 a direct handler installed before any signal receives live sends in order")
  func setF092DirectHandlerReceivesLiveSendsInOrder() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.installDirectHandler { value in
      trace.withLock { $0.append(value) }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    #expect(trace.withLock { $0 } == [])
    reader.send("A")
    reader.send("B")
    #expect(trace.withLock { $0 } == ["A", "B"])
  }

  @Test("setF093 a stream installed after buffering replays the buffer then finishes")
  func setF093StreamReplaysBufferThenFinishes() async {
    let reader = InProcessSignalReader()
    reader.send("A")
    reader.send("B")
    let stream = reader.events()
    reader.finish()
    var collected: [String] = []
    for await name in stream {
      collected.append(name)
    }
    #expect(collected == ["A", "B"])
  }

  @Test("setF094 a stream installed after finish is already finished")
  func setF094StreamAfterFinishIsEmpty() async {
    let reader = InProcessSignalReader()
    reader.finish()
    let stream = reader.events()
    var collected: [String] = []
    for await name in stream {
      collected.append(name)
    }
    #expect(collected.isEmpty)
  }

  @Test("setF095 a finished reader reports end on install and drops a later send")
  func setF095FinishedReaderReportsEndAndDropsSend() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.finish()
    reader.installDirectHandler { value in
      trace.withLock { $0.append(value) }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    reader.send("N")
    #expect(trace.withLock { $0 } == ["end"])
  }

  @Test("setF096 clearing a direct handler detaches end delivery from a later finish")
  func setF096ClearDetachesEndDelivery() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.installDirectHandler { value in
      trace.withLock { $0.append(value) }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    reader.clearDirectHandler()
    reader.finish()
    #expect(trace.withLock { $0 } == [])
  }

  @Test("setF097 a reentrant send during the pending flush interleaves ahead of the buffer (probe)")
  func setF097ReentrantSendDuringFlushInterleaves() throws {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.send("A")
    reader.send("B")
    reader.installDirectHandler { [weak reader] value in
      trace.withLock { $0.append(value) }
      if value == "A" { reader?.send("C") }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    let observed = trace.withLock { $0 }
    print("F4_PROBE setF097 \(observed)")
    // The live signal C, sent while the first buffered signal is being
    // delivered, reaches the handler before the remaining buffered B.
    let indexC = try #require(observed.firstIndex(of: "C"))
    let indexB = try #require(observed.firstIndex(of: "B"))
    #expect(indexC < indexB)
    #expect(observed == ["A", "C", "B"])
  }

  @Test("setF098 a live stream delivers sends in order then finishes")
  func setF098LiveStreamDeliversInOrder() async {
    let reader = InProcessSignalReader()
    let stream = reader.events()
    reader.send("A")
    reader.send("B")
    reader.finish()
    var collected: [String] = []
    for await name in stream {
      collected.append(name)
    }
    #expect(collected == ["A", "B"])
  }

  @Test("setF099 finish is idempotent and a post-finish stream is already finished")
  func setF099FinishIsIdempotent() async {
    let reader = InProcessSignalReader()
    let stream = reader.events()
    reader.finish()
    reader.finish()
    var collected: [String] = []
    for await name in stream {
      collected.append(name)
    }
    #expect(collected.isEmpty)
    var second: [String] = []
    for await name in reader.events() {
      second.append(name)
    }
    #expect(second.isEmpty)
  }

  @Test("setF100 finish discards signals buffered without a consumer")
  func setF100FinishDiscardsUnconsumedBuffer() {
    let reader = InProcessSignalReader()
    let trace = Mutex<[String]>([])
    reader.send("A")
    reader.finish()
    reader.installDirectHandler { value in
      trace.withLock { $0.append(value) }
    } onFinish: {
      trace.withLock { $0.append("end") }
    }
    #expect(trace.withLock { $0 } == ["end"])
  }
}
