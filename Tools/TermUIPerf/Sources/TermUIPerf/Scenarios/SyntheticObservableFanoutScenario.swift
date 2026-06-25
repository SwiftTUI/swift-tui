import Observation
@_spi(Runners) import SwiftTUI

/// Measures observable dependency fan-out over a large body.
///
/// SwiftTUI currently records observable graph dependencies by object token.
/// Swift's Observation bridge first narrows a mutation to the body identities
/// that actually read the changed key path, but the graph then expands that
/// dirty set to every live reader of the same object token. This scenario makes
/// that expansion visible by mutating `hot` while many sibling readers observe
/// `cold` or `rare` on the same model.
///
/// The default `fanout` shape reads each property as a **plain `body` read**
/// (`model.hot`). Plain reads record no object token, so they already fire
/// key-path precisely through Swift's Observation bridge and bypass SwiftTUI's
/// object-token co-reader union entirely — this shape's recompute is therefore
/// dominated by *structural* re-resolution of sibling cells, not observable
/// fan-out. The `bindable-fanout` shape reads each property through a
/// `@Bindable` projection (`$model.hot.wrappedValue`); the `@Bindable` subscript
/// is one of the only two seams that record an object token, so these readers DO
/// enter the co-reader union and a `hot` mutation expands to every `@Bindable`
/// peer on the same model. That is the workload the object-token union narrowing
/// (`SWIFTTUI_PRECISE_OBSERVATION_FIRING`) actually moves. The optional
/// `large-body` shape is the sub-body memo workload: one view body reads the hot
/// value and builds a large cold payload, so key-path fan-out alone cannot avoid
/// the large body cost.
///
/// Knobs:
///   - `TERMUI_PERF_OBSERVABLE_ROWS` (default: 12)
///   - `TERMUI_PERF_OBSERVABLE_COLUMNS` (default: 4)
///   - `TERMUI_PERF_OBSERVABLE_SHAPE=fanout|bindable-fanout|large-body`
///     (default: fanout)
public struct SyntheticObservableFanoutScenario: PerfScenario {
  public let name: PerfScenarioName = .syntheticObservableFanout
  public let defaultTerminalSize = PerfTerminalSize(columns: 100, rows: 44)
  public let scriptedEvents = [
    "mutate one @Observable key path while many same-object peers read other key paths"
  ]
  public let visualMarkers = ["hot 0"]
  public let settlingDescription = "first frame that shows hot 0"

  private static let defaultRowCount = 12
  private static let defaultColumnCount = 4
  private static let clickCount = 6

  public init() {}

  @MainActor
  public func run(options: PerfScenarioRunOptions) async throws -> PerfScenarioRunResult {
    let model = PerfObservableFanoutModel()
    let rowCount = Self.resolvedRowCount()
    let columnCount = Self.resolvedColumnCount()
    let shape = Self.resolvedShape()

    return try await PerfScenarioRunner.runWindow(
      scenario: self,
      options: options
    ) {
      PerfObservableFanoutProbeView(
        model: model,
        rowCount: rowCount,
        columnCount: columnCount,
        shape: shape
      )
    } drive: { driver in
      _ = try await driver.waitForFrame(containing: "hot 0")
      let dispatchTime = monotonicSeconds()
      var lastFrame = driver.terminalHost.presentedFrames.last?.frameNumber ?? 0

      for click in 1...Self.clickCount {
        let cell = try driver.cell(containing: "mutate hot")
        driver.sendClick(at: cell)
        let matching = try await driver.waitForFrame(
          containing: "hot \(click)",
          afterFrame: lastFrame
        )
        lastFrame = matching.frameNumber
      }

      let settled = driver.terminalHost.presentedFrames.last
      return [
        PerfEventRecord(
          eventID: "synthetic-observable-fanout-\(shape.rawValue)",
          eventType: "mouse_click",
          dispatchTimeSeconds: dispatchTime,
          expectedVisualMarker: "hot \(Self.clickCount)",
          firstMatchingFrame: lastFrame,
          firstMatchingTimeSeconds: settled?.timestampSeconds ?? dispatchTime,
          finalSettledFrame: settled?.frameNumber ?? lastFrame,
          finalSettledTimeSeconds: settled?.timestampSeconds ?? dispatchTime
        )
      ]
    }
  }

  private static func resolvedRowCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_OBSERVABLE_ROWS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultRowCount
    }
    return parsed
  }

  private static func resolvedColumnCount() -> Int {
    guard let raw = environmentValue("TERMUI_PERF_OBSERVABLE_COLUMNS"),
      let parsed = Int(raw),
      parsed > 0
    else {
      return defaultColumnCount
    }
    return parsed
  }

  private static func resolvedShape() -> PerfObservableFanoutShape {
    PerfObservableFanoutShape(rawValue: environmentValue("TERMUI_PERF_OBSERVABLE_SHAPE") ?? "")
      ?? .fanout
  }
}

private enum PerfObservableFanoutShape: String, Sendable {
  case fanout
  case bindableFanout = "bindable-fanout"
  case largeBody = "large-body"
}

@Observable
private final class PerfObservableFanoutModel {
  var hot = 0
  var cold = 10_000
  var rare = 20_000
}

private struct PerfObservableFanoutProbeView: View {
  let model: PerfObservableFanoutModel
  let rowCount: Int
  let columnCount: Int
  let shape: PerfObservableFanoutShape

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("mutate hot") {
        model.hot += 1
      }
      switch shape {
      case .fanout:
        PerfObservableFanoutGrid(
          model: model,
          rowCount: rowCount,
          columnCount: columnCount
        )
      case .bindableFanout:
        PerfObservableBindableFanoutGrid(
          model: model,
          rowCount: rowCount,
          columnCount: columnCount
        )
      case .largeBody:
        PerfObservableLargeBodyPane(
          model: model,
          rowCount: rowCount,
          columnCount: columnCount
        )
      }
    }
    .padding(1)
  }
}

private struct PerfObservableFanoutGrid: View {
  let model: PerfObservableFanoutModel
  let rowCount: Int
  let columnCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(0..<rowCount), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<columnCount), id: \.self) { column in
            PerfObservableFanoutCell(
              model: model,
              row: row,
              column: column,
              property: PerfObservableFanoutProperty(
                rawValue: (row * columnCount + column) % PerfObservableFanoutProperty.count
              ) ?? .hot
            )
          }
        }
      }
    }
  }
}

/// `@Bindable` variant of ``PerfObservableFanoutGrid``. Cells read each property
/// through the `@Bindable` subscript (`$model.hot.wrappedValue`), which records
/// an object token via `recordObservableRead` and so enters SwiftTUI's
/// object-token co-reader union — the path the precise-firing narrowing targets.
private struct PerfObservableBindableFanoutGrid: View {
  let model: PerfObservableFanoutModel
  let rowCount: Int
  let columnCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(0..<rowCount), id: \.self) { row in
        HStack(spacing: 1) {
          ForEach(Array(0..<columnCount), id: \.self) { column in
            PerfObservableBindableFanoutCell(
              model: model,
              row: row,
              column: column,
              property: PerfObservableFanoutProperty(
                rawValue: (row * columnCount + column) % PerfObservableFanoutProperty.count
              ) ?? .hot
            )
          }
        }
      }
    }
  }
}

private struct PerfObservableBindableFanoutCell: View {
  @Bindable var model: PerfObservableFanoutModel
  let row: Int
  let column: Int
  let property: PerfObservableFanoutProperty

  init(
    model: PerfObservableFanoutModel,
    row: Int,
    column: Int,
    property: PerfObservableFanoutProperty
  ) {
    _model = Bindable(model)
    self.row = row
    self.column = column
    self.property = property
  }

  var body: some View {
    switch property {
    case .hot:
      Text("r\(row)c\(column) hot \($model.hot.wrappedValue)")
    case .cold:
      Text("r\(row)c\(column) cold \($model.cold.wrappedValue)")
    case .rare:
      Text("r\(row)c\(column) rare \($model.rare.wrappedValue)")
    }
  }
}

private enum PerfObservableFanoutProperty: Int, Sendable {
  case hot
  case cold
  case rare

  static let count = 3
}

private struct PerfObservableFanoutCell: View {
  let model: PerfObservableFanoutModel
  let row: Int
  let column: Int
  let property: PerfObservableFanoutProperty

  var body: some View {
    switch property {
    case .hot:
      Text("r\(row)c\(column) hot \(model.hot)")
    case .cold:
      Text("r\(row)c\(column) cold \(model.cold)")
    case .rare:
      Text("r\(row)c\(column) rare \(model.rare)")
    }
  }
}

private struct PerfObservableLargeBodyPane: View {
  let model: PerfObservableFanoutModel
  let rowCount: Int
  let columnCount: Int

  var body: some View {
    let hot = model.hot
    let coldPayload = Self.coldPayload(
      cold: model.cold,
      rowCount: rowCount,
      columnCount: columnCount
    )

    VStack(alignment: .leading, spacing: 0) {
      Text("large-body hot \(hot)")
      ForEach(coldPayload, id: \.id) { cell in
        Text(cell.text)
      }
    }
  }

  private static func coldPayload(
    cold: Int,
    rowCount: Int,
    columnCount: Int
  ) -> [PerfObservableLargeBodyCell] {
    var cells: [PerfObservableLargeBodyCell] = []
    cells.reserveCapacity(rowCount * columnCount)
    for row in 0..<rowCount {
      for column in 0..<columnCount {
        let id = row * columnCount + column
        cells.append(
          PerfObservableLargeBodyCell(
            id: id,
            text: "large r\(row)c\(column) cold \(cold)"
          ))
      }
    }
    return cells
  }
}

private struct PerfObservableLargeBodyCell: Sendable {
  var id: Int
  var text: String
}
