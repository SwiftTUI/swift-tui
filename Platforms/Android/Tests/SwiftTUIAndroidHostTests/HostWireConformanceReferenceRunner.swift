import Foundation

struct HostWireConformanceReferenceObservation: Equatable {
  var rows: [HostWireConformanceGridRow]
  var imagesVisible: [String]
  var resyncRequests: [HostWireConformanceJSON]
  var styleRuns: [HostWireConformanceStyleRun]?
}

enum HostWireConformanceExactComparator {
  static func requireEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    context: String
  ) throws {
    guard actual == expected else {
      throw HostWireConformanceError.invalid(
        "\(context): exact observation mismatch\(detail(actual, expected))")
    }
  }

  /// The first differing JSON path, when both sides are conformance JSON.
  /// A bare "mismatch" makes every oracle failure a bisecting exercise; the
  /// path plus both values is what the message is for.
  private static func detail<T>(
    _ actual: T,
    _ expected: T
  ) -> String {
    guard let actual = actual as? HostWireConformanceJSON,
      let expected = expected as? HostWireConformanceJSON,
      let difference = firstDifference(actual, expected, path: "")
    else {
      return ""
    }
    return
      "\n  at \(difference.path.isEmpty ? "<root>" : difference.path)"
      + "\n  actual:   \(difference.actual)"
      + "\n  expected: \(difference.expected)"
  }

  private static func firstDifference(
    _ actual: HostWireConformanceJSON,
    _ expected: HostWireConformanceJSON,
    path: String
  ) -> (path: String, actual: String, expected: String)? {
    guard actual != expected else { return nil }
    switch (actual, expected) {
    case (.object(let actualObject), .object(let expectedObject)):
      for key in Set(actualObject.keys).union(expectedObject.keys).sorted() {
        guard let actualValue = actualObject[key], let expectedValue = expectedObject[key]
        else {
          return (
            "\(path).\(key)", describe(actualObject[key]), describe(expectedObject[key])
          )
        }
        if let difference = firstDifference(
          actualValue, expectedValue, path: "\(path).\(key)")
        {
          return difference
        }
      }
    case (.array(let actualArray), .array(let expectedArray)):
      for index in 0..<max(actualArray.count, expectedArray.count) {
        guard index < actualArray.count, index < expectedArray.count else {
          return (
            "\(path)[\(index)]",
            describe(actualArray.indices.contains(index) ? actualArray[index] : nil),
            describe(expectedArray.indices.contains(index) ? expectedArray[index] : nil)
          )
        }
        if let difference = firstDifference(
          actualArray[index], expectedArray[index], path: "\(path)[\(index)]")
        {
          return difference
        }
      }
    default:
      break
    }
    return (path, describe(actual), describe(expected))
  }

  private static func describe(
    _ value: HostWireConformanceJSON?
  ) -> String {
    guard let value else { return "<absent>" }
    switch value {
    case .object(let object):
      return "{\(object.keys.sorted().joined(separator: ","))}"
    case .array(let array):
      return "[\(array.count) elements]"
    case .string(let string):
      return "\"\(string)\""
    case .integer(let integer):
      return "\(integer)"
    case .bool(let bool):
      return "\(bool)"
    case .null:
      return "null"
    }
  }
}

struct HostWireConformanceReferenceRunner {
  private var applier = HostWireConformanceReferenceApplier()
  private var requestLog: [HostWireConformanceJSON] = []

  static func runActiveFixtures(
    _ corpus: HostWireConformanceCorpus
  ) throws -> [String] {
    var executed: [String] = []
    for entry in HostWireConformanceRunnerDeclaration.swiftReference.requiredEntries(
      in: corpus.manifest
    ) {
      guard let fixture = corpus.fixtures[entry.file] else {
        throw HostWireConformanceError.invalid("\(entry.file): missing parsed fixture")
      }
      var runner = Self()
      try runner.run(fixture)
      executed.append(entry.scenario)
    }
    return executed
  }

  mutating func run(
    _ fixture: HostWireConformanceFixture
  ) throws {
    guard fixture.entry.runners.contains(.swiftReference),
      fixture.entry.kind == .record,
      HostWireConformanceRunnerDeclaration.swiftReference.implementedStages.contains(
        fixture.entry.requiresStage)
    else {
      throw HostWireConformanceError.invalid(
        "\(fixture.entry.file): fixture is not active for swift-reference")
    }
    var expectationCount = 0
    for (index, step) in fixture.steps.enumerated() {
      let context = "\(fixture.entry.file):step \(index + 1)"
      switch step {
      case .emit(let raw):
        guard !fixture.droppedEmitIndexes.contains(index) else {
          continue
        }
        try applier.apply(raw, requestLog: &requestLog)
      case .drop:
        continue
      case .evictImages(let ids):
        applier.evictImages(ids)
      case .reconnect(let capsAfter):
        guard capsAfter == nil else {
          throw HostWireConformanceError.invalid(
            "\(context): capsAfter is invalid for swift-reference")
        }
        applier = HostWireConformanceReferenceApplier()
      case .expect(let expected):
        expectationCount += 1
        let parsedExpected = try Self.parseExpectedObservation(expected, context: context)
        let observation = applier.observation(
          requests: requestLog,
          includesStyleRuns: parsedExpected.styleRuns != nil
        )
        try HostWireConformanceExactComparator.requireEqual(
          observation,
          parsedExpected,
          context: context
        )
        requestLog.removeAll(keepingCapacity: true)
      case .decodeFailure, .androidABI, .channel:
        throw HostWireConformanceError.invalid(
          "\(context): inapplicable step reached swift-reference")
      }
    }
    guard expectationCount > 0 else {
      throw HostWireConformanceError.invalid(
        "\(fixture.entry.file): executable fixture has no expectation")
    }
  }

  static func parseExpectedObservation(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws -> HostWireConformanceReferenceObservation {
    guard case .object(let object) = value else {
      throw HostWireConformanceError.invalid("\(context): expected observation object")
    }
    var expectedKeys: Set<String> = ["rows", "imagesVisible", "resyncRequests"]
    if object["styleRuns"] != nil {
      expectedKeys.insert("styleRuns")
    }
    guard Set(object.keys) == expectedKeys else {
      throw HostWireConformanceError.invalid(
        "\(context): unexpected observation fields \(Set(object.keys).subtracting(expectedKeys).sorted())"
      )
    }
    guard let rowsValue = object["rows"], let imagesValue = object["imagesVisible"],
      let requestsValue = object["resyncRequests"]
    else {
      throw HostWireConformanceError.invalid("\(context): incomplete observation")
    }
    let rows = try HostWireConformanceCorpus.parseGridRows(
      rowsValue,
      context: "\(context).rows"
    )
    let images = try imagesValue.array(context: "\(context).imagesVisible").enumerated().map {
      try $0.element.string(context: "\(context).imagesVisible[\($0.offset)]")
    }
    let requests = try requestsValue.array(context: "\(context).resyncRequests")
    let styleRuns = try object["styleRuns"].map {
      try HostWireConformanceCorpus.parseStyleRuns(
        $0,
        rows: rows,
        context: "\(context).styleRuns"
      )
    }
    return .init(
      rows: rows,
      imagesVisible: images,
      resyncRequests: requests,
      styleRuns: styleRuns
    )
  }
}

private struct HostWireConformanceReferenceApplier {
  private struct AppliedCell {
    var grid: HostWireConformanceGridCell
    var resolvedStyle: HostWireConformanceJSON
  }

  private var rowsByIndex: [Int: [AppliedCell]] = [:]
  private var hasBaseline = false
  private var gridHeight = 0
  private var gridWidth = 0
  private var lastEpoch: Int?
  private var lastGeneration: Int?
  private var styleTable: [HostWireConformanceJSON] = []
  private var imagePayloads: Set<String> = []
  private var presentedImageIDs: Set<String> = []
  private var outstandingImageIDs: Set<String> = []
  private var keyframeRequestOutstanding = false

  mutating func apply(
    _ record: String,
    requestLog: inout [HostWireConformanceJSON]
  ) throws {
    let prefix = "\u{001E}surface:"
    guard record.hasPrefix(prefix), record.hasSuffix("\n") else {
      throw HostWireConformanceError.invalid("swift-reference: expected surface record")
    }
    let bytes = Array(record.utf8)
    let payload = Data(bytes[prefix.utf8.count..<(bytes.count - 1)])
    let json = try HostWireConformanceJSON.parse(payload, context: "swift-reference.surface")
    guard case .object(let object) = json else {
      throw HostWireConformanceError.invalid("swift-reference: surface payload is not an object")
    }
    let encoding = try object["encoding"]?.string(context: "surface.encoding")
    if encoding == "delta" {
      try applyDelta(object, requestLog: &requestLog)
    } else if encoding == nil {
      try applyFull(object, requestLog: &requestLog)
    } else {
      throw HostWireConformanceError.invalid(
        "surface.encoding: unknown value \(encoding!)")
    }
  }

  mutating func evictImages(
    _ ids: [String]
  ) {
    imagePayloads.subtract(ids)
  }

  func observation(
    requests: [HostWireConformanceJSON],
    includesStyleRuns: Bool
  ) -> HostWireConformanceReferenceObservation {
    let rows = rowsByIndex.keys.sorted().map {
      HostWireConformanceGridRow(row: $0, cells: rowsByIndex[$0]!.map(\.grid))
    }
    let visible = presentedImageIDs.intersection(imagePayloads).sorted()
    return .init(
      rows: rows,
      imagesVisible: visible,
      resyncRequests: requests,
      styleRuns: includesStyleRuns ? resolvedStyleRuns() : nil
    )
  }

  private mutating func applyFull(
    _ object: [String: HostWireConformanceJSON],
    requestLog: inout [HostWireConformanceJSON]
  ) throws {
    let stamps = try fullStamps(object)
    let width = try nonnegativeInteger(object, key: "width")
    let height = try nonnegativeInteger(object, key: "height")
    try updateStyleTable(object)
    guard let rowsValue = object["rows"] else {
      throw HostWireConformanceError.invalid("surface.rows: missing")
    }
    let rows = try decodeFullRows(rowsValue)
    guard rows.count == height else {
      throw HostWireConformanceError.invalid(
        "surface.rows: full record row count does not equal height")
    }
    try validateRowsInGrid(rows, width: width, height: height)
    rowsByIndex = Dictionary(uniqueKeysWithValues: rows.map { ($0.row, $0.cells) })
    hasBaseline = true
    gridWidth = width
    gridHeight = height
    lastEpoch = stamps?.epoch
    lastGeneration = stamps?.generation
    keyframeRequestOutstanding = false
    try applyImages(object["images"], requestLog: &requestLog)
  }

  private mutating func applyDelta(
    _ object: [String: HostWireConformanceJSON],
    requestLog: inout [HostWireConformanceJSON]
  ) throws {
    let stamps = try deltaStamps(object)
    let width = try nonnegativeInteger(object, key: "width")
    let height = try nonnegativeInteger(object, key: "height")
    guard hasBaseline, width == gridWidth, height == gridHeight else {
      requestKeyframe(requestLog: &requestLog)
      return
    }
    if let stamps,
      stamps.epoch != lastEpoch || stamps.baselineGeneration != lastGeneration
    {
      requestKeyframe(requestLog: &requestLog)
      return
    }
    try updateStyleTable(object)
    guard let deltaRowsValue = object["deltaRows"] else {
      throw HostWireConformanceError.invalid("surface.deltaRows: missing")
    }
    let deltaRows = try decodeDeltaRows(deltaRowsValue)
    try validateRowsInGrid(deltaRows, width: width, height: height)
    for row in deltaRows {
      rowsByIndex[row.row] = row.cells
    }
    if let stamps {
      lastEpoch = stamps.epoch
      lastGeneration = stamps.generation
    }
    try applyImages(object["images"], requestLog: &requestLog)
  }

  private mutating func applyImages(
    _ value: HostWireConformanceJSON?,
    requestLog: inout [HostWireConformanceJSON]
  ) throws {
    guard let value else {
      presentedImageIDs = []
      return
    }
    let images = try value.array(context: "surface.images")
    var presented: Set<String> = []
    for (index, imageValue) in images.enumerated() {
      let context = "surface.images[\(index)]"
      guard case .object(let image) = imageValue else {
        throw HostWireConformanceError.invalid("\(context): expected object")
      }
      guard let idValue = image["id"] else {
        throw HostWireConformanceError.invalid("\(context).id: missing")
      }
      let id = try idValue.string(context: "\(context).id")
      presented.insert(id)
      if image["dataBase64"] != nil {
        imagePayloads.insert(id)
        outstandingImageIDs.remove(id)
      } else if !imagePayloads.contains(id), outstandingImageIDs.insert(id).inserted {
        let request: HostWireConformanceJSON = .object([
          "scope": .string("images"),
          "ids": .array([.string(id)]),
        ])
        requestLog.append(request)
      }
    }
    presentedImageIDs = presented
  }

  private mutating func requestKeyframe(
    requestLog: inout [HostWireConformanceJSON]
  ) {
    guard !keyframeRequestOutstanding else {
      return
    }
    keyframeRequestOutstanding = true
    requestLog.append(.object(["scope": .string("keyframe")]))
  }

  private func fullStamps(
    _ object: [String: HostWireConformanceJSON]
  ) throws -> (epoch: Int, generation: Int)? {
    let epoch = object["epoch"]
    let generation = object["gen"]
    guard (epoch == nil) == (generation == nil) else {
      throw HostWireConformanceError.invalid(
        "surface: full stamp tuple must contain both epoch and gen or neither")
    }
    guard let epoch, let generation else {
      return nil
    }
    return (
      try epoch.integer(context: "surface.epoch"),
      try generation.integer(context: "surface.gen")
    )
  }

  private func deltaStamps(
    _ object: [String: HostWireConformanceJSON]
  ) throws -> (epoch: Int, generation: Int, baselineGeneration: Int)? {
    let values = [object["epoch"], object["gen"], object["baselineGen"]]
    guard values.allSatisfy({ $0 == nil }) || values.allSatisfy({ $0 != nil }) else {
      throw HostWireConformanceError.invalid(
        "surface: delta stamp tuple must contain epoch, gen, and baselineGen or none")
    }
    guard let epoch = values[0], let generation = values[1], let baseline = values[2] else {
      return nil
    }
    return (
      try epoch.integer(context: "surface.epoch"),
      try generation.integer(context: "surface.gen"),
      try baseline.integer(context: "surface.baselineGen")
    )
  }

  private func nonnegativeInteger(
    _ object: [String: HostWireConformanceJSON],
    key: String
  ) throws -> Int {
    guard let value = object[key] else {
      throw HostWireConformanceError.invalid("surface.\(key): missing")
    }
    let integer = try value.integer(context: "surface.\(key)")
    guard integer >= 0 else {
      throw HostWireConformanceError.invalid("surface.\(key): must be nonnegative")
    }
    return integer
  }

  private func decodeFullRows(
    _ value: HostWireConformanceJSON
  ) throws -> [(row: Int, cells: [AppliedCell])] {
    let rows = try value.array(context: "surface.rows")
    return try rows.enumerated().map { rowIndex, rowValue in
      (
        row: rowIndex,
        cells: try decodeCells(rowValue, context: "surface.rows[\(rowIndex)]")
      )
    }
  }

  private func decodeDeltaRows(
    _ value: HostWireConformanceJSON
  ) throws -> [(row: Int, cells: [AppliedCell])] {
    let rows = try value.array(context: "surface.deltaRows")
    var result: [(row: Int, cells: [AppliedCell])] = []
    var priorRow = -1
    for (index, rowValue) in rows.enumerated() {
      let context = "surface.deltaRows[\(index)]"
      let pair = try rowValue.array(context: context)
      guard pair.count == 2 else {
        throw HostWireConformanceError.invalid("\(context): expected [row,cells]")
      }
      let row = try pair[0].integer(context: "\(context)[0]")
      guard row > priorRow else {
        throw HostWireConformanceError.invalid("\(context): rows must be strictly ascending")
      }
      priorRow = row
      result.append((row: row, cells: try decodeCells(pair[1], context: "\(context)[1]")))
    }
    return result
  }

  private func decodeCells(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws -> [AppliedCell] {
    let cells = try value.array(context: context)
    var result: [AppliedCell] = []
    var previousEnd = 0
    for (index, cellValue) in cells.enumerated() {
      let cellContext = "\(context)[\(index)]"
      let tuple = try cellValue.array(context: cellContext)
      guard tuple.count == 4 else {
        throw HostWireConformanceError.invalid("\(cellContext): expected four-element cell tuple")
      }
      let column = try tuple[0].integer(context: "\(cellContext)[0]")
      let text = try tuple[1].string(context: "\(cellContext)[1]")
      let span = try tuple[2].integer(context: "\(cellContext)[2]")
      let styleIndex = try tuple[3].integer(context: "\(cellContext)[3]")
      guard column >= 0, span > 0, result.isEmpty || column >= previousEnd else {
        throw HostWireConformanceError.invalid("\(cellContext): invalid cell geometry")
      }
      guard styleTable.indices.contains(styleIndex) else {
        throw HostWireConformanceError.invalid(
          "\(cellContext): style index \(styleIndex) is outside the resolved table")
      }
      let (end, overflow) = column.addingReportingOverflow(span)
      guard !overflow else {
        throw HostWireConformanceError.invalid("\(cellContext): cell geometry overflow")
      }
      previousEnd = end
      result.append(
        .init(
          grid: .init(column: column, text: text, span: span),
          resolvedStyle: styleTable[styleIndex]
        ))
    }
    return result
  }

  private func validateRowsInGrid(
    _ rows: [(row: Int, cells: [AppliedCell])],
    width: Int,
    height: Int
  ) throws {
    guard
      rows.allSatisfy({
        $0.row >= 0 && $0.row < height
          && $0.cells.allSatisfy({
            $0.grid.column <= width && $0.grid.span <= width - $0.grid.column
          })
      })
    else {
      throw HostWireConformanceError.invalid("surface: row/cell outside declared grid")
    }
  }

  private mutating func updateStyleTable(
    _ object: [String: HostWireConformanceJSON]
  ) throws {
    guard let stylesValue = object["styles"] else {
      throw HostWireConformanceError.invalid("surface.styles: missing")
    }
    let styles = try stylesValue.array(context: "surface.styles")
    for (index, style) in styles.enumerated() {
      guard style == .null || isObject(style) else {
        throw HostWireConformanceError.invalid(
          "surface.styles[\(index)]: expected null or resolved-style object")
      }
    }
    if let baseValue = object["stylesBase"] {
      let base = try baseValue.integer(context: "surface.stylesBase")
      guard base == styleTable.count else {
        throw HostWireConformanceError.invalid(
          "surface.stylesBase: append prefix does not match the retained table")
      }
      styleTable += styles
    } else {
      styleTable = styles
    }
    guard !styleTable.isEmpty, styleTable[0] == .null else {
      throw HostWireConformanceError.invalid(
        "surface.styles: resolved table must retain null at index zero")
    }
  }

  private func isObject(_ value: HostWireConformanceJSON) -> Bool {
    if case .object = value {
      return true
    }
    return false
  }

  private func resolvedStyleRuns() -> [HostWireConformanceStyleRun] {
    var result: [HostWireConformanceStyleRun] = []
    for row in rowsByIndex.keys.sorted() {
      guard let cells = rowsByIndex[row] else {
        continue
      }
      for cell in cells where cell.resolvedStyle != .null {
        if let last = result.last,
          last.row == row,
          last.startColumn + last.span == cell.grid.column,
          last.resolvedStyle == cell.resolvedStyle
        {
          result[result.count - 1].text += cell.grid.text
          result[result.count - 1].span += cell.grid.span
        } else {
          result.append(
            .init(
              row: row,
              startColumn: cell.grid.column,
              text: cell.grid.text,
              span: cell.grid.span,
              resolvedStyle: cell.resolvedStyle
            ))
        }
      }
    }
    return result
  }
}
