// Excluded from Windows builds (Windows plan, Stage 6 item 3): the cross-host
// wire-conformance suite drives the Android and WebHost adapters, whose
// modules build empty on Windows (whole-file-guarded).
#if !os(Windows)

  import Foundation

  extension HostWireConformanceCorpus {
    static func validateEmittedRecord(
      _ record: String,
      allowsNonSurface: Bool,
      context: String
    ) throws {
      guard record.first == "\u{001E}", record.last == "\n",
        record.dropLast().last != "\n", !record.contains("\r")
      else {
        throw HostWireConformanceError.invalid(
          "\(context): emit must contain one LF-terminated RS-framed record")
      }
      guard !record.dropLast().contains("\n") else {
        throw HostWireConformanceError.invalid("\(context): emit contains multiple records")
      }
      if !allowsNonSurface {
        guard record.hasPrefix("\u{001E}surface:") else {
          throw HostWireConformanceError.invalid("\(context): record emit must be surface:")
        }
      }
      if record.hasPrefix("\u{001E}surface:") {
        let prefixCount = "\u{001E}surface:".utf8.count
        let bytes = Array(record.utf8)
        let json = Data(bytes[prefixCount..<(bytes.count - 1)])
        let decoded = try HostWireConformanceJSON.parse(json, context: "\(context).emit.surface")
        guard case .object = decoded else {
          throw HostWireConformanceError.invalid("\(context): surface payload must be an object")
        }
      }
    }

    static func validateExpectation(
      _ value: HostWireConformanceJSON,
      entry: HostWireConformanceManifestEntry,
      context: String
    ) throws {
      switch entry.kind {
      case .record, .webPainter:
        guard case .object(let object) = value else {
          throw HostWireConformanceError.invalid("\(context): expected object")
        }
        var expectedKeys: Set<String> = ["rows", "imagesVisible", "resyncRequests"]
        if entry.kind == .record, object["styleRuns"] != nil {
          expectedKeys.insert("styleRuns")
        }
        guard Set(object.keys) == expectedKeys else {
          throw HostWireConformanceError.invalid(
            "\(context): invalid record expectation keys \(object.keys.sorted())")
        }
        let rows = try parseGridRows(required(object, "rows"), context: "\(context).rows")
        let imageValues = try required(object, "imagesVisible").array(
          context: "\(context).imagesVisible")
        let images = try imageValues.enumerated().map {
          try $0.element.string(context: "\(context).imagesVisible[\($0.offset)]")
        }
        guard images == images.sorted(), Set(images).count == images.count else {
          throw HostWireConformanceError.invalid(
            "\(context): imagesVisible must be a sorted set")
        }
        let requests = try required(object, "resyncRequests").array(
          context: "\(context).resyncRequests")
        for (index, request) in requests.enumerated() {
          try validateResyncRequest(request, context: "\(context).resyncRequests[\(index)]")
        }
        if let styleRuns = object["styleRuns"] {
          _ = try parseStyleRuns(
            styleRuns,
            rows: rows,
            context: "\(context).styleRuns"
          )
        }
      case .androidABI:
        let object = try value.object(keys: ["androidDeliveries"], context: context)
        let deliveries = try required(object, "androidDeliveries").array(
          context: "\(context).androidDeliveries")
        for (index, delivery) in deliveries.enumerated() {
          try validateAndroidDelivery(
            delivery,
            context: "\(context).androidDeliveries[\(index)]"
          )
        }
      case .websocketChannel:
        try validateChannelExpectation(value, context: context)
      }
    }

    static func parseGridRows(
      _ value: HostWireConformanceJSON,
      context: String
    ) throws -> [HostWireConformanceGridRow] {
      let rowValues = try value.array(context: context)
      var result: [HostWireConformanceGridRow] = []
      var priorRow = -1
      for (rowIndex, rowValue) in rowValues.enumerated() {
        let rowContext = "\(context)[\(rowIndex)]"
        let rowObject = try rowValue.object(keys: ["row", "cells"], context: rowContext)
        let row = try required(rowObject, "row").integer(context: "\(rowContext).row")
        guard row >= 0, row > priorRow else {
          throw HostWireConformanceError.invalid(
            "\(rowContext): rows must be nonnegative and strictly ascending")
        }
        priorRow = row
        let cellValues = try required(rowObject, "cells").array(context: "\(rowContext).cells")
        var cells: [HostWireConformanceGridCell] = []
        var previousEnd = 0
        for (cellIndex, cellValue) in cellValues.enumerated() {
          let cellContext = "\(rowContext).cells[\(cellIndex)]"
          let cellObject = try cellValue.object(
            keys: ["column", "text", "span"],
            context: cellContext
          )
          let column = try required(cellObject, "column").integer(
            context: "\(cellContext).column")
          let text = try required(cellObject, "text").string(context: "\(cellContext).text")
          let span = try required(cellObject, "span").integer(context: "\(cellContext).span")
          guard column >= 0, span > 0, cells.isEmpty || column >= previousEnd else {
            throw HostWireConformanceError.invalid(
              "\(cellContext): cells must be ascending, positive-span, and nonoverlapping")
          }
          let (end, overflow) = column.addingReportingOverflow(span)
          guard !overflow else {
            throw HostWireConformanceError.invalid("\(cellContext): cell geometry overflow")
          }
          previousEnd = end
          cells.append(.init(column: column, text: text, span: span))
        }
        result.append(.init(row: row, cells: cells))
      }
      return result
    }

    static func parseStyleRuns(
      _ value: HostWireConformanceJSON,
      rows: [HostWireConformanceGridRow],
      context: String
    ) throws -> [HostWireConformanceStyleRun] {
      let values = try value.array(context: context)
      let rowsByIndex = Dictionary(uniqueKeysWithValues: rows.map { ($0.row, $0.cells) })
      var result: [HostWireConformanceStyleRun] = []
      var priorRow = -1
      var priorEnd = -1
      var priorStyle: HostWireConformanceJSON?
      for (index, run) in values.enumerated() {
        let runContext = "\(context)[\(index)]"
        let object = try run.object(
          keys: ["row", "startColumn", "text", "span", "resolvedStyle"],
          context: runContext
        )
        let row = try required(object, "row").integer(context: "\(runContext).row")
        let startColumn = try required(object, "startColumn").integer(
          context: "\(runContext).startColumn")
        let text = try required(object, "text").string(context: "\(runContext).text")
        let span = try required(object, "span").integer(context: "\(runContext).span")
        let resolvedStyle = required(object, "resolvedStyle")
        guard row >= 0, startColumn >= 0, span > 0
        else {
          throw HostWireConformanceError.invalid("\(runContext): invalid style-run geometry")
        }
        guard case .object = resolvedStyle else {
          throw HostWireConformanceError.invalid("\(runContext): resolvedStyle must be an object")
        }
        guard row > priorRow || (row == priorRow && startColumn >= priorEnd) else {
          throw HostWireConformanceError.invalid(
            "\(runContext): style runs must be ordered and nonoverlapping")
        }
        if row == priorRow, startColumn == priorEnd, resolvedStyle == priorStyle {
          throw HostWireConformanceError.invalid(
            "\(runContext): adjacent equal-style cells must be coalesced")
        }
        guard let cells = rowsByIndex[row],
          let firstIndex = cells.firstIndex(where: { $0.column == startColumn })
        else {
          throw HostWireConformanceError.invalid(
            "\(runContext): style run does not start on an explicit grid cell")
        }
        var coveredText = ""
        var coveredSpan = 0
        var expectedColumn = startColumn
        var cellIndex = firstIndex
        while coveredSpan < span, cellIndex < cells.count {
          let cell = cells[cellIndex]
          guard cell.column == expectedColumn else {
            throw HostWireConformanceError.invalid(
              "\(runContext): style run crosses an intentional grid gap")
          }
          coveredText += cell.text
          let (nextSpan, spanOverflow) = coveredSpan.addingReportingOverflow(cell.span)
          let (nextColumn, columnOverflow) = expectedColumn.addingReportingOverflow(cell.span)
          guard !spanOverflow, !columnOverflow else {
            throw HostWireConformanceError.invalid(
              "\(runContext): style-run geometry overflow")
          }
          coveredSpan = nextSpan
          expectedColumn = nextColumn
          cellIndex += 1
        }
        guard coveredSpan == span, coveredText == text else {
          throw HostWireConformanceError.invalid(
            "\(runContext): style-run text/span does not exactly cover grid cells")
        }
        result.append(
          .init(
            row: row,
            startColumn: startColumn,
            text: text,
            span: span,
            resolvedStyle: resolvedStyle
          ))
        priorRow = row
        let (end, overflow) = startColumn.addingReportingOverflow(span)
        guard !overflow else {
          throw HostWireConformanceError.invalid("\(runContext): style-run geometry overflow")
        }
        priorEnd = end
        priorStyle = resolvedStyle
      }
      return result
    }

    private static func validateResyncRequest(
      _ value: HostWireConformanceJSON,
      context: String
    ) throws {
      guard case .object(let object) = value else {
        throw HostWireConformanceError.invalid("\(context): resync request must be an object")
      }
      let scope = try required(object, "scope").string(context: "\(context).scope")
      if scope == "keyframe" {
        guard Set(object.keys) == ["scope"] else {
          throw HostWireConformanceError.invalid("\(context): keyframe request has extra fields")
        }
        return
      }
      guard scope == "images", Set(object.keys).isSubset(of: ["scope", "ids"]) else {
        throw HostWireConformanceError.invalid("\(context): invalid resync scope or fields")
      }
      if let idsValue = object["ids"] {
        let ids = try idsValue.array(context: "\(context).ids")
        let strings = try ids.enumerated().map {
          try $0.element.string(context: "\(context).ids[\($0.offset)]")
        }
        guard strings == strings.sorted(), Set(strings).count == strings.count else {
          throw HostWireConformanceError.invalid("\(context): image IDs must be a sorted set")
        }
      }
    }

    static func validateAndroidABIAction(
      _ value: HostWireConformanceJSON,
      context: String
    ) throws {
      guard case .object(let object) = value else {
        throw HostWireConformanceError.invalid("\(context): expected object")
      }
      let action = try required(object, "action").string(context: "\(context).action")
      switch action {
      case "publish":
        guard
          Set(object.keys)
            == ["action", "sequence", "width", "height", "rows", "damage"]
        else {
          throw HostWireConformanceError.invalid("\(context): invalid publish fields")
        }
        let sequence = try required(object, "sequence").integer(
          context: "\(context).sequence")
        let width = try required(object, "width").integer(context: "\(context).width")
        let height = try required(object, "height").integer(context: "\(context).height")
        guard sequence >= 0, width >= 0, height >= 0 else {
          throw HostWireConformanceError.invalid("\(context): publish integers must be nonnegative")
        }
        let rows = try parseGridRows(required(object, "rows"), context: "\(context).rows")
        for row in rows {
          guard row.row < height,
            row.cells.allSatisfy({
              $0.column <= width && $0.span <= width - $0.column
            })
          else {
            throw HostWireConformanceError.invalid(
              "\(context): published grid cell is outside width/height")
          }
        }
        try validateDamage(
          required(object, "damage"), width: width, height: height, context: "\(context).damage")
      case "sizeQuery":
        guard Set(object.keys) == ["action", "label"] else {
          throw HostWireConformanceError.invalid("\(context): invalid sizeQuery fields")
        }
        guard !(try required(object, "label").string(context: "\(context).label")).isEmpty else {
          throw HostWireConformanceError.invalid("\(context): size label must be nonempty")
        }
      case "copy":
        guard Set(object.keys) == ["action", "label", "capacity"] else {
          throw HostWireConformanceError.invalid("\(context): invalid copy fields")
        }
        guard !(try required(object, "label").string(context: "\(context).label")).isEmpty,
          try required(object, "capacity").integer(context: "\(context).capacity") >= 0
        else {
          throw HostWireConformanceError.invalid("\(context): invalid copy label/capacity")
        }
      default:
        throw HostWireConformanceError.invalid("\(context): unknown Android ABI action \(action)")
      }
    }

    private static func validateDamage(
      _ value: HostWireConformanceJSON,
      width: Int,
      height: Int,
      context: String
    ) throws {
      if value == .null {
        return
      }
      let object = try value.object(keys: ["rows"], context: context)
      let rows = try required(object, "rows").array(context: "\(context).rows")
      var priorRow = -1
      for (index, rowValue) in rows.enumerated() {
        let rowContext = "\(context).rows[\(index)]"
        let rowObject = try rowValue.object(keys: ["row", "ranges"], context: rowContext)
        let row = try required(rowObject, "row").integer(context: "\(rowContext).row")
        guard row >= 0, row < height, row > priorRow else {
          throw HostWireConformanceError.invalid("\(rowContext): invalid damage row")
        }
        priorRow = row
        let ranges = try required(rowObject, "ranges").array(context: "\(rowContext).ranges")
        for (rangeIndex, rangeValue) in ranges.enumerated() {
          let rangeContext = "\(rowContext).ranges[\(rangeIndex)]"
          let pair = try rangeValue.array(context: rangeContext)
          guard pair.count == 2 else {
            throw HostWireConformanceError.invalid("\(rangeContext): expected [start,end]")
          }
          let start = try pair[0].integer(context: "\(rangeContext)[0]")
          let end = try pair[1].integer(context: "\(rangeContext)[1]")
          guard start >= 0, start < end, end <= width else {
            throw HostWireConformanceError.invalid(
              "\(rangeContext): damage range must be increasing and in-grid")
          }
        }
      }
    }

    private static func validateAndroidDelivery(
      _ value: HostWireConformanceJSON,
      context: String
    ) throws {
      let object = try value.object(
        keys: ["label", "reported", "capacity", "returned", "copied", "record"],
        context: context
      )
      guard !(try required(object, "label").string(context: "\(context).label")).isEmpty else {
        throw HostWireConformanceError.invalid("\(context): delivery label must be nonempty")
      }
      for key in ["reported", "capacity", "returned"] {
        guard try required(object, key).integer(context: "\(context).\(key)") >= 0 else {
          throw HostWireConformanceError.invalid("\(context): \(key) must be nonnegative")
        }
      }
      let copied = try required(object, "copied").bool(context: "\(context).copied")
      let record = required(object, "record")
      if !copied {
        guard record == .null else {
          throw HostWireConformanceError.invalid(
            "\(context): uncopied delivery record must be null")
        }
        return
      }
      let recordObject = try record.object(
        keys: ["kind", "epoch", "gen", "baselineGen", "rows"],
        context: "\(context).record"
      )
      let kind = try required(recordObject, "kind").string(context: "\(context).record.kind")
      guard kind == "full" || kind == "delta" else {
        throw HostWireConformanceError.invalid("\(context): invalid decoded record kind")
      }
      for key in ["epoch", "gen", "baselineGen"] {
        let stamp = required(recordObject, key)
        guard
          stamp == .null || ((try? stamp.integer(context: "\(context).record.\(key)")) ?? -1) >= 0
        else {
          throw HostWireConformanceError.invalid("\(context): invalid decoded record stamp")
        }
      }
      _ = try parseGridRows(required(recordObject, "rows"), context: "\(context).record.rows")
    }

  }

#endif
