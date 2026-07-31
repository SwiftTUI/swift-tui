import Foundation
@_spi(Runners) import SwiftTUI
import Testing

@testable import TermUIPerf

/// Program Stage 0, WP-2: the scroll drive model and the five scenarios that
/// use it.
///
/// The scenarios themselves run at env-pinned smoke scale — these cases are
/// about *what the drive does*, not how fast it is.
struct ScrollDriveModelTests {
  // MARK: - T-10

  @Test("Open-loop drive emits every notch in order without awaiting a settle")
  @MainActor
  func openLoopDriveEmitsEveryNotchInOrder() async throws {
    let reader = PerfScriptedInputReader()
    let driver = PerfScenarioDriver(
      inputReader: reader,
      terminalHost: PerfTerminalHost(size: PerfTerminalSize(columns: 40, rows: 12))
    )

    // Open the stream first: `finish()` drops anything still staged, and the
    // point of this case is that the drive does not wait for a consumer.
    let stream = reader.inputEvents()
    await driver.driveScroll(
      cadence: .milliseconds(1),
      notches: 12,
      at: CellPoint(x: 4, y: 4),
      deltaY: 1
    )
    reader.finish()

    var received: [InputEvent] = []
    for await event in stream {
      received.append(event)
    }

    #expect(received.count == 12)
    for event in received {
      guard case .mouse(let mouseEvent) = event,
        case .scrolled(let deltaX, let deltaY) = mouseEvent.kind
      else {
        Issue.record("expected a scroll event, got \(event)")
        return
      }
      #expect(deltaX == 0)
      #expect(deltaY == 1)
      #expect(mouseEvent.location.cell == CellPoint(x: 4, y: 4))
    }
  }

  // MARK: - T-13 (drive shape)

  @Test("A fling is a press, monotonically travelling drags, and a release")
  @MainActor
  func flingSendsAPressDragsAndRelease() async throws {
    let reader = PerfScriptedInputReader()
    let driver = PerfScenarioDriver(
      inputReader: reader,
      terminalHost: PerfTerminalHost(size: PerfTerminalSize(columns: 40, rows: 24))
    )

    let stream = reader.inputEvents()
    await driver.sendFling(
      from: CellPoint(x: 5, y: 18),
      cells: 12,
      over: .milliseconds(24),
      samples: 6
    )
    reader.finish()

    var received: [MouseEvent] = []
    for await event in stream {
      if case .mouse(let mouseEvent) = event {
        received.append(mouseEvent)
      }
    }

    #expect(received.count == 8)  // down + 6 drags + up
    guard case .down(.primary) = received.first?.kind,
      case .up(.primary) = received.last?.kind
    else {
      Issue.record("a fling must open with a press and close with a release")
      return
    }

    // The drags walk upward without ever going back, and their timestamps
    // increase — that monotonic pair is what the velocity sampler reads.
    let drags = received.dropFirst().dropLast()
    var previousRow = received[0].location.cell.y
    var previousTimestamp = received[0].timestamp
    for drag in drags {
      #expect(drag.location.cell.y <= previousRow)
      #expect(drag.timestamp > previousTimestamp)
      previousRow = drag.location.cell.y
      previousTimestamp = drag.timestamp
    }
    #expect(received.last?.location.cell.y == 6)  // 18 - 12
    // Authored, not wall-clock: the release timestamp is exactly the fling
    // duration after the press, so the seeded velocity is run-independent.
    #expect(
      received[0].timestamp.duration(to: received[received.count - 1].timestamp)
        == .milliseconds(24))
  }

  // MARK: - Registration

  @Test("Every scroll scenario is registered and reachable by name")
  @MainActor
  func scrollScenariosAreRegistered() {
    let scrollNames: [PerfScenarioName] = [
      .scrollNotchLatency,
      .scrollCadence60Hz,
      .scrollFlingMomentum,
      .scrollJump,
      .scrollDocumentMixed,
    ]
    for name in scrollNames {
      #expect(
        PerfScenarioRegistry.scenario(named: name) != nil,
        "\(name.rawValue) is not in PerfScenarioRegistry.all"
      )
      #expect(PerfScenarioName(rawValue: name.rawValue) == name)
    }
  }
}
