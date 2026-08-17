// Excluded from Windows builds (Windows plan, Stage 6 item 3): the cross-host
// wire-conformance suite drives the Android and WebHost adapters, whose
// modules build empty on Windows (whole-file-guarded).
#if !os(Windows)

  import Foundation

  enum HostWireConformanceRecordDecoding {
    static func surfaceObject(
      in raw: String,
      context: String
    ) throws -> [String: Any] {
      let prefix = "\u{001E}surface:"
      guard raw.hasPrefix(prefix), raw.hasSuffix("\n") else {
        throw HostWireConformanceError.invalid("\(context): expected one surface record")
      }
      let bytes = Array(raw.utf8)
      let payload = Data(bytes[prefix.utf8.count..<(bytes.count - 1)])
      guard
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
      else {
        throw HostWireConformanceError.invalid("\(context): surface payload is not an object")
      }
      return object
    }

    static func structuredRows(
      in raw: String,
      context: String
    ) throws -> [[String: Any]] {
      let object = try surfaceObject(in: raw, context: context)
      if object["encoding"] as? String == "delta" {
        guard let rows = object["deltaRows"] as? [[Any]] else {
          throw HostWireConformanceError.invalid("\(context): deltaRows missing")
        }
        return try rows.enumerated().map { index, pair in
          guard pair.count == 2, let row = pair[0] as? Int, let cells = pair[1] as? [[Any]]
          else {
            throw HostWireConformanceError.invalid(
              "\(context): malformed deltaRows[\(index)]")
          }
          return [
            "row": row,
            "cells": try structuredCells(cells, context: "\(context).deltaRows[\(index)]"),
          ]
        }
      }

      guard let rows = object["rows"] as? [[[Any]]] else {
        throw HostWireConformanceError.invalid("\(context): rows missing")
      }
      return try rows.enumerated().map { row, cells in
        [
          "row": row,
          "cells": try structuredCells(cells, context: "\(context).rows[\(row)]"),
        ]
      }
    }

    static func androidDelivery(
      label: String,
      reported: Int,
      capacity: Int,
      returned: Int,
      raw: String?
    ) throws -> [String: Any] {
      guard let raw, returned > 0, capacity >= returned else {
        return [
          "label": label,
          "reported": reported,
          "capacity": capacity,
          "returned": returned,
          "copied": false,
          "record": NSNull(),
        ]
      }
      let object = try surfaceObject(in: raw, context: "android delivery \(label)")
      let kind = object["encoding"] as? String == "delta" ? "delta" : "full"
      return [
        "label": label,
        "reported": reported,
        "capacity": capacity,
        "returned": returned,
        "copied": true,
        "record": [
          "kind": kind,
          "epoch": object["epoch"] ?? NSNull(),
          "gen": object["gen"] ?? NSNull(),
          "baselineGen": object["baselineGen"] ?? NSNull(),
          "rows": try structuredRows(in: raw, context: "android delivery \(label)"),
        ],
      ]
    }

    static func channelRecord(
      raw: String
    ) throws -> [String: Any] {
      guard raw.hasPrefix("\u{001E}surface:") else {
        return [
          "raw": raw,
          "kind": "non-surface",
          "epoch": NSNull(),
          "gen": NSNull(),
          "baselineGen": NSNull(),
        ]
      }
      let object = try surfaceObject(in: raw, context: "channel record")
      return [
        "raw": raw,
        "kind": object["encoding"] as? String == "delta" ? "delta" : "full",
        "epoch": object["epoch"] ?? NSNull(),
        "gen": object["gen"] ?? NSNull(),
        "baselineGen": object["baselineGen"] ?? NSNull(),
      ]
    }

    static func conformanceJSON(
      from object: Any,
      context: String
    ) throws -> HostWireConformanceJSON {
      let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
      return try HostWireConformanceJSON.parse(data, context: context)
    }

    private static func structuredCells(
      _ cells: [[Any]],
      context: String
    ) throws -> [[String: Any]] {
      try cells.enumerated().map { index, tuple in
        guard tuple.count == 4, let column = tuple[0] as? Int,
          let text = tuple[1] as? String, let span = tuple[2] as? Int
        else {
          throw HostWireConformanceError.invalid("\(context).cells[\(index)]: malformed tuple")
        }
        return [
          "column": column,
          "text": text,
          "span": span,
        ]
      }
    }
  }

#endif
