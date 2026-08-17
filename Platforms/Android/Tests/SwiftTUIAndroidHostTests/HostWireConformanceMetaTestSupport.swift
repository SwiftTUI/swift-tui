// Excluded from Windows builds (Windows plan, Stage 6 item 3): the cross-host
// wire-conformance suite drives the Android and WebHost adapters, whose
// modules build empty on Windows (whole-file-guarded).
#if !os(Windows)

  import Foundation

  extension HostWireConformanceTests {
    enum ManifestMutation: CaseIterable, CustomStringConvertible {
      case unknownField
      case unknownStage
      case runnerOrder

      var description: String {
        switch self {
        case .unknownField: "unknown-field"
        case .unknownStage: "unknown-stage"
        case .runnerOrder: "runner-order"
        }
      }

      func apply(
        to manifest: inout [String: Any]
      ) {
        switch self {
        case .unknownField:
          manifest["future"] = true
        case .unknownStage:
          var fixtures = manifest["fixtures"] as! [[String: Any]]
          fixtures[0]["requiresStage"] = "s99"
          manifest["fixtures"] = fixtures
        case .runnerOrder:
          var fixtures = manifest["fixtures"] as! [[String: Any]]
          var runners = fixtures[1]["runners"] as! [String]
          runners.swapAt(0, 1)
          fixtures[1]["runners"] = runners
          manifest["fixtures"] = fixtures
        }
      }
    }

    enum ReferenceCorruption: CaseIterable {
      case rowCount
      case cellCount
      case row
      case column
      case text
      case nonpositiveSpan
      case gapWidth
      case imageID
      case imageCount
      case requestScope
      case requestIDs
      case requestOrder
      case requestCount
      case stylePosition
      case styleSpan
      case styleText
      case styleGapBoundary
      case resolvedStyle

      func apply(
        to observation: HostWireConformanceReferenceObservation
      ) -> HostWireConformanceReferenceObservation {
        var result = observation
        switch self {
        case .rowCount:
          result.rows.removeLast()
        case .cellCount:
          result.rows[0].cells.removeLast()
        case .row:
          result.rows[0].row += 1
        case .column:
          result.rows[0].cells[0].column += 1
        case .text:
          result.rows[0].cells[0].text = "B"
        case .nonpositiveSpan:
          result.rows[0].cells[0].span = 0
        case .gapWidth:
          result.rows[0].cells[1].column += 1
        case .imageID:
          result.imagesVisible[0] = "image-z"
        case .imageCount:
          result.imagesVisible.removeLast()
        case .requestScope:
          result.resyncRequests[0] = .object(["scope": .string("keyframe")])
        case .requestIDs:
          result.resyncRequests[0] = .object([
            "scope": .string("images"),
            "ids": .array([.string("image-b")]),
          ])
        case .requestOrder:
          result.resyncRequests.swapAt(0, 1)
        case .requestCount:
          result.resyncRequests.removeLast()
        case .stylePosition:
          result.styleRuns?[0].row += 1
        case .styleSpan:
          result.styleRuns?[0].span += 1
        case .styleText:
          result.styleRuns?[0].text = "B"
        case .styleGapBoundary:
          result.styleRuns?[1].startColumn -= 1
        case .resolvedStyle:
          result.styleRuns?[0].resolvedStyle = .object([
            "fg": .string("#61C67BFF")
          ])
        }
        return result
      }
    }

    enum JSONPathPart {
      case key(String)
      case index(Int)
    }

    /// The fixture's first expectation, plus the step index it occupies. Meta
    /// tests corrupt *that* interval, so they need the index to splice a
    /// corrupted expectation back into the step list at the right place —
    /// a multi-interval fixture is no longer "the last step".
    static func firstExpectation(
      in fixture: HostWireConformanceFixture
    ) throws -> (stepIndex: Int, expectation: HostWireConformanceJSON) {
      for (index, step) in fixture.steps.enumerated() {
        if case .expect(let expectation) = step {
          return (index, expectation)
        }
      }
      throw HostWireConformanceError.invalid("\(fixture.entry.file): expectation missing")
    }

    static func expectation(
      in fixture: HostWireConformanceFixture
    ) throws -> HostWireConformanceJSON {
      try firstExpectation(in: fixture).expectation
    }

    /// Every expectation interval, in fixture order.
    static func expectations(
      in fixture: HostWireConformanceFixture
    ) -> [HostWireConformanceJSON] {
      fixture.steps.compactMap { step in
        guard case .expect(let expectation) = step else { return nil }
        return expectation
      }
    }

    static func replacingJSONValue(
      at path: [JSONPathPart],
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard let head = path.first else {
        switch value {
        case .string(let string):
          return .string(string + "-corrupt")
        case .integer(let integer):
          return .integer(integer + 1)
        case .number(let double):
          return .number(double + 1)
        case .bool(let bool):
          return .bool(!bool)
        case .null:
          return .integer(0)
        case .array(let array):
          return .array(array + [.null])
        case .object(let object):
          return .object(object.merging(["corrupt": .bool(true)]) { current, _ in current })
        }
      }
      let tail = Array(path.dropFirst())
      switch (head, value) {
      case (.key(let key), .object(var object)):
        guard let child = object[key] else {
          throw HostWireConformanceError.invalid("meta path missing key \(key)")
        }
        object[key] = try replacingJSONValue(at: tail, in: child)
        return .object(object)
      case (.index(let index), .array(var array)):
        guard array.indices.contains(index) else {
          throw HostWireConformanceError.invalid("meta path missing index \(index)")
        }
        array[index] = try replacingJSONValue(at: tail, in: array[index])
        return .array(array)
      default:
        throw HostWireConformanceError.invalid("meta path shape mismatch")
      }
    }

    static func settingJSONValue(
      at path: [JSONPathPart],
      to replacement: HostWireConformanceJSON,
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard let head = path.first else {
        return replacement
      }
      let tail = Array(path.dropFirst())
      switch (head, value) {
      case (.key(let key), .object(var object)):
        guard let child = object[key] else {
          throw HostWireConformanceError.invalid("meta path missing key \(key)")
        }
        object[key] = try settingJSONValue(at: tail, to: replacement, in: child)
        return .object(object)
      case (.index(let index), .array(var array)):
        guard array.indices.contains(index) else {
          throw HostWireConformanceError.invalid("meta path missing index \(index)")
        }
        array[index] = try settingJSONValue(at: tail, to: replacement, in: array[index])
        return .array(array)
      default:
        throw HostWireConformanceError.invalid("meta path shape mismatch")
      }
    }

    static func replacingArrayCensus(
      _ key: String,
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard case .object(var object) = value, case .array(var array) = object[key] else {
        throw HostWireConformanceError.invalid("meta array key \(key) missing")
      }
      if array.isEmpty {
        array.append(.string("corrupt"))
      } else {
        array.removeLast()
      }
      object[key] = .array(array)
      return .object(object)
    }

    static func replacingArrayCensus(
      at path: [JSONPathPart],
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard let head = path.first else {
        guard case .array(var array) = value else {
          throw HostWireConformanceError.invalid("meta path does not end at an array")
        }
        if array.isEmpty {
          array.append(.null)
        } else {
          array.removeLast()
        }
        return .array(array)
      }
      let tail = Array(path.dropFirst())
      switch (head, value) {
      case (.key(let key), .object(var object)):
        guard let child = object[key] else {
          throw HostWireConformanceError.invalid("meta path missing key \(key)")
        }
        object[key] = try replacingArrayCensus(at: tail, in: child)
        return .object(object)
      case (.index(let index), .array(var array)):
        guard array.indices.contains(index) else {
          throw HostWireConformanceError.invalid("meta path missing index \(index)")
        }
        array[index] = try replacingArrayCensus(at: tail, in: array[index])
        return .array(array)
      default:
        throw HostWireConformanceError.invalid("meta path shape mismatch")
      }
    }

    static func appendingAndroidGridCell(
      to value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard case .object(var root) = value,
        case .array(var deliveries) = root["androidDeliveries"],
        case .object(var delivery) = deliveries[0],
        case .object(var record) = delivery["record"],
        case .array(var rows) = record["rows"],
        case .object(var row) = rows[0],
        case .array(var cells) = row["cells"]
      else {
        throw HostWireConformanceError.invalid("Android grid meta shape changed")
      }
      cells.append(
        .object([
          "column": .integer(3),
          "text": .string("Z"),
          "span": .integer(1),
        ]))
      row["cells"] = .array(cells)
      rows[0] = .object(row)
      record["rows"] = .array(rows)
      delivery["record"] = .object(record)
      deliveries[0] = .object(delivery)
      root["androidDeliveries"] = .array(deliveries)
      return .object(root)
    }

    static func swappingDeliveredAndSuppressedMembership(
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard case .object(var object) = value,
        case .array(var delivered) = object["deliveredRecords"],
        case .array(var suppressed) = object["suppressedSurfaceRecords"],
        !delivered.isEmpty,
        !suppressed.isEmpty
      else {
        throw HostWireConformanceError.invalid("channel membership meta shape changed")
      }
      let deliveredRecord = delivered[0]
      delivered[0] = suppressed[0]
      suppressed[0] = deliveredRecord
      object["deliveredRecords"] = .array(delivered)
      object["suppressedSurfaceRecords"] = .array(suppressed)
      return .object(object)
    }

    static func reversingArrayOrder(
      _ key: String,
      in value: HostWireConformanceJSON
    ) throws -> HostWireConformanceJSON {
      guard case .object(var object) = value, case .array(let array) = object[key],
        array.count > 1
      else {
        throw HostWireConformanceError.invalid("meta ordered array key \(key) is not populated")
      }
      object[key] = .array(Array(array.reversed()))
      return .object(object)
    }

    static func flippedHash(
      _ hash: String
    ) -> String {
      (hash.first == "0" ? "1" : "0") + hash.dropFirst()
    }

    static func replacingFirst(
      _ needle: String,
      with replacement: String,
      in data: Data
    ) throws -> Data {
      let text = String(decoding: data, as: UTF8.self)
      guard let range = text.range(of: needle) else {
        throw HostWireConformanceError.invalid("meta replacement needle missing")
      }
      return Data(text.replacingCharacters(in: range, with: replacement).utf8)
    }
  }

#endif
