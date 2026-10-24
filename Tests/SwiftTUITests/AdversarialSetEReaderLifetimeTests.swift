import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite("Campaign F3 direct reader callback lifetimes", .serialized)
struct AdversarialSetEReaderLifetimeTests {
  @Test(arguments: Array(71...80))
  func readerLifetime(id: Int) {
    let reader = SetEDirectReader(signals: id >= 76)
    defer { reader.finish() }
    let log = SetEReaderLog()
    let mode = (id - 71) % 5
    if mode < 3 {
      var capture: SetEReaderCapture? = .init(log: log)
      weak let weakCapture = capture
      if let capture { reader.install({ capture.record($0) }, finish: { capture.record("EOF") }) }
      capture = nil
      #expect(weakCapture != nil)
      reader.send(["A"])
      switch mode {
      case 0:
        reader.clear()
        #expect(weakCapture == nil)
        reader.send(["B"])
        #expect(log.values == ["A"])
        reader.install({ value in log.append("new-\(value)") }, finish: {})
        #expect(log.values == ["A", "new-B"])
      case 1:
        reader.finish()
        #expect(weakCapture == nil)
        reader.finish()
        reader.send(["B"])
        #expect(log.values == ["A", "EOF"])
      default:
        reader.install(
          { value in log.append("new-\(value)") },
          finish: {
            log.append("new-EOF")
          })
        #expect(weakCapture == nil)
        reader.send(["B"])
        reader.finish()
        #expect(log.values == ["A", "new-B", "new-EOF"])
      }
    } else if mode == 3 {
      reader.install(
        { [weak reader] value in
          log.append("old-\(value)")
          reader?.clear()
        }, finish: { log.append("old-EOF") })
      reader.send(["A"])
      reader.send(["B"])
      #expect(log.values == ["old-A"])
      reader.install(
        { value in log.append("new-\(value)") },
        finish: {
          log.append("new-EOF")
        })
      reader.finish()
      #expect(log.values == ["old-A", "new-B", "new-EOF"])
    } else {
      reader.install(
        { [weak reader] value in
          log.append(value)
          if value == "A" { reader?.finish() }
        }, finish: { log.append("EOF") })
      reader.send(["A", "B"])
      reader.send(["C"])
      reader.finish()
      #expect(log.values == (id < 76 ? ["A", "B", "EOF"] : ["A", "EOF"]))
    }
  }
}

private final class SetEReaderLog: Sendable {
  private let state = Mutex<[String]>([])
  var values: [String] { state.withLock { $0 } }
  func append(_ value: String) { state.withLock { $0.append(value) } }
}

private final class SetEReaderCapture: Sendable {
  let log: SetEReaderLog
  init(log: SetEReaderLog) { self.log = log }
  func record(_ value: String) { log.append(value) }
}

private final class SetEDirectReader: Sendable {
  let input: InjectedTerminalInputReader?
  let signals: InProcessSignalReader?
  init(signals: Bool) {
    input = signals ? nil : InjectedTerminalInputReader(mouseFlushScheduling: .manual)
    self.signals = signals ? InProcessSignalReader() : nil
  }
  func install(
    _ handler: @escaping @Sendable (String) -> Void, finish: @escaping @Sendable () -> Void
  ) {
    input?.installDirectHandler(
      { event in
        if case .key(let press) = event, case .character(let character) = press.key {
          handler(String(character))
        }
      }, onFinish: finish)
    signals?.installDirectHandler(handler, onFinish: finish)
  }
  func send(_ values: [String]) {
    if let input {
      input.send(values.flatMap { $0.map { InputEvent.key(.character($0)) } })
    } else {
      for value in values { signals?.send(value) }
    }
  }
  func clear() {
    input?.clearDirectHandler()
    signals?.clearDirectHandler()
  }
  func finish() {
    input?.finish()
    signals?.finish()
  }
}
