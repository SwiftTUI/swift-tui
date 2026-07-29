import Foundation

extension HostWireConformanceCorpus {
  static func validateChannelAction(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws {
    guard case .object(let object) = value else {
      throw HostWireConformanceError.invalid("\(context): expected object")
    }
    let action = try required(object, "action").string(context: "\(context).action")
    switch action {
    case "closeClient":
      guard Set(object.keys) == ["action", "token"],
        try required(object, "token").integer(context: "\(context).token") > 0
      else {
        throw HostWireConformanceError.invalid("\(context): invalid closeClient action")
      }
    case "clientChunk":
      guard Set(object.keys) == ["action", "token", "bytesBase64"],
        try required(object, "token").integer(context: "\(context).token") > 0
      else {
        throw HostWireConformanceError.invalid("\(context): invalid clientChunk action")
      }
      let encoded = try required(object, "bytesBase64").string(
        context: "\(context).bytesBase64")
      guard Data(base64Encoded: encoded) != nil else {
        throw HostWireConformanceError.invalid("\(context): bytesBase64 is malformed")
      }
    case "drainInput":
      guard Set(object.keys) == ["action"] else {
        throw HostWireConformanceError.invalid("\(context): drainInput takes no fields")
      }
    default:
      throw HostWireConformanceError.invalid(
        "\(context): unknown channel action \(action); detach/requestRefresh/shutdown are forbidden"
      )
    }
  }

  static func validateChannelExpectation(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws {
    let object = try value.object(
      keys: [
        "deliveredRecords", "suppressedSurfaceRecords", "detachedNonSurfaceBacklog",
        "refreshRequestCount", "capsProcessedCount", "ignoredStaleCallbackCount",
        "acceptedClientInputs", "discardedInboundChunks", "parser", "connection",
      ],
      context: context
    )
    for key in ["deliveredRecords", "suppressedSurfaceRecords"] {
      let records = try required(object, key).array(context: "\(context).\(key)")
      for (index, record) in records.enumerated() {
        let recordContext = "\(context).\(key)[\(index)]"
        let fields = try record.object(
          keys: ["raw", "kind", "epoch", "gen", "baselineGen"],
          context: recordContext
        )
        let raw = try required(fields, "raw").string(context: "\(recordContext).raw")
        try validateEmittedRecord(raw, allowsNonSurface: true, context: recordContext)
        let kind = try required(fields, "kind").string(context: "\(recordContext).kind")
        guard ["full", "delta", "non-surface"].contains(kind) else {
          throw HostWireConformanceError.invalid("\(recordContext): invalid record kind")
        }
        let isSurface = raw.hasPrefix("\u{001E}surface:")
        guard (kind == "non-surface") != isSurface else {
          throw HostWireConformanceError.invalid(
            "\(recordContext): record kind does not match its raw envelope")
        }
        if key == "suppressedSurfaceRecords", kind == "non-surface" {
          throw HostWireConformanceError.invalid(
            "\(recordContext): only full/delta surface records may be suppressed")
        }
        if isSurface {
          let prefixCount = "\u{001E}surface:".utf8.count
          let bytes = Array(raw.utf8)
          let payload = try HostWireConformanceJSON.parse(
            Data(bytes[prefixCount..<(bytes.count - 1)]),
            context: "\(recordContext).raw.surface"
          )
          guard case .object(let surface) = payload else {
            preconditionFailure("surface object was already validated")
          }
          let emittedKind =
            (try surface["encoding"]?.string(context: "\(recordContext).raw.encoding"))
              == "delta" ? "delta" : "full"
          guard kind == emittedKind else {
            throw HostWireConformanceError.invalid(
              "\(recordContext): kind disagrees with the emitted surface encoding")
          }
          for stamp in ["epoch", "gen", "baselineGen"] {
            guard required(fields, stamp) == (surface[stamp] ?? .null) else {
              throw HostWireConformanceError.invalid(
                "\(recordContext): \(stamp) disagrees with the emitted surface record")
            }
          }
        } else {
          guard ["epoch", "gen", "baselineGen"].allSatisfy({ required(fields, $0) == .null })
          else {
            throw HostWireConformanceError.invalid(
              "\(recordContext): non-surface records cannot carry surface stamps")
          }
        }
        for stamp in ["epoch", "gen", "baselineGen"] {
          let stampValue = required(fields, stamp)
          guard
            stampValue == .null
              || ((try? stampValue.integer(context: "\(recordContext).\(stamp)")) ?? -1) >= 0
          else {
            throw HostWireConformanceError.invalid("\(recordContext): invalid stamp")
          }
        }
      }
    }
    let delivered = try required(object, "deliveredRecords").array(
      context: "\(context).deliveredRecords")
    let suppressed = try required(object, "suppressedSurfaceRecords").array(
      context: "\(context).suppressedSurfaceRecords")
    guard !delivered.contains(where: suppressed.contains) else {
      throw HostWireConformanceError.invalid(
        "\(context): a channel record cannot be both delivered and suppressed")
    }
    let backlog = try required(object, "detachedNonSurfaceBacklog").object(
      keys: ["count", "bytes"],
      context: "\(context).detachedNonSurfaceBacklog")
    for key in ["count", "bytes"] {
      guard
        try required(backlog, key).integer(
          context: "\(context).detachedNonSurfaceBacklog.\(key)") >= 0
      else {
        throw HostWireConformanceError.invalid("\(context): invalid backlog gauge")
      }
    }
    for key in ["refreshRequestCount", "capsProcessedCount", "ignoredStaleCallbackCount"] {
      guard try required(object, key).integer(context: "\(context).\(key)") >= 0 else {
        throw HostWireConformanceError.invalid("\(context): invalid interval counter \(key)")
      }
    }
    let inputs = try required(object, "acceptedClientInputs").array(
      context: "\(context).acceptedClientInputs")
    for (index, input) in inputs.enumerated() {
      _ = try input.string(context: "\(context).acceptedClientInputs[\(index)]")
    }
    let discarded = try required(object, "discardedInboundChunks").array(
      context: "\(context).discardedInboundChunks")
    for (index, chunk) in discarded.enumerated() {
      let chunkContext = "\(context).discardedInboundChunks[\(index)]"
      let fields = try chunk.object(
        keys: ["token", "bytesBase64", "reason"],
        context: chunkContext
      )
      guard try required(fields, "token").integer(context: "\(chunkContext).token") > 0,
        Data(
          base64Encoded: try required(fields, "bytesBase64").string(
            context: "\(chunkContext).bytesBase64")) != nil
      else {
        throw HostWireConformanceError.invalid("\(chunkContext): invalid discarded chunk")
      }
      let reason = try required(fields, "reason").string(context: "\(chunkContext).reason")
      guard
        [
          "stale-at-ingress", "stale-at-consumption", "connection-boundary", "terminal",
        ].contains(reason)
      else {
        throw HostWireConformanceError.invalid("\(chunkContext): invalid discard reason")
      }
    }
    let parser = try required(object, "parser").object(
      keys: ["token", "bufferedBytes"],
      context: "\(context).parser")
    let parserTokenValue = required(parser, "token")
    let parserToken =
      parserTokenValue == .null
      ? nil : try parserTokenValue.integer(context: "\(context).parser.token")
    guard
      parserToken == nil || parserToken! > 0,
      try required(parser, "bufferedBytes").integer(
        context: "\(context).parser.bufferedBytes") >= 0
    else {
      throw HostWireConformanceError.invalid("\(context): invalid parser gauge")
    }
    let connection = try required(object, "connection").object(
      keys: ["currentToken", "lastIssuedToken", "phase", "sceneInputFinished"],
      context: "\(context).connection")
    let currentTokenValue = required(connection, "currentToken")
    let currentToken =
      currentTokenValue == .null
      ? nil : try currentTokenValue.integer(context: "\(context).connection.currentToken")
    let lastIssuedToken = try required(connection, "lastIssuedToken").integer(
      context: "\(context).connection.lastIssuedToken")
    guard
      currentToken == nil || currentToken! > 0,
      lastIssuedToken >= 1
    else {
      throw HostWireConformanceError.invalid("\(context): invalid connection token gauge")
    }
    let phase = try required(connection, "phase").string(context: "\(context).connection.phase")
    guard ["detached", "pre-capabilities", "active"].contains(phase) else {
      throw HostWireConformanceError.invalid("\(context): invalid connection phase")
    }
    guard
      (phase == "detached") == (currentToken == nil),
      currentToken == nil || currentToken == lastIssuedToken,
      parserToken == nil || parserToken == currentToken
    else {
      throw HostWireConformanceError.invalid(
        "\(context): parser/connection phase and tokens are inconsistent")
    }
    guard
      try required(connection, "sceneInputFinished").bool(
        context: "\(context).connection.sceneInputFinished") == false
    else {
      throw HostWireConformanceError.invalid(
        "\(context): S5 reconnect fixtures must keep scene input unfinished")
    }
    for (index, chunk) in discarded.enumerated() {
      guard case .object(let fields) = chunk,
        try required(fields, "token").integer(
          context: "\(context).discardedInboundChunks[\(index)].token") <= lastIssuedToken
      else {
        throw HostWireConformanceError.invalid(
          "\(context): discarded chunk names an unissued connection token")
      }
    }
  }

  static func validateSequentialSemantics(
    _ steps: [HostWireConformanceStep],
    entry: HostWireConformanceManifestEntry
  ) throws {
    var labels: Set<String> = []
    var pendingAndroidCopies: [(label: String, capacity: Int)] = []
    var activeDecodePlans: Set<String> = []
    var lastIssuedToken = 1
    var currentToken: Int? = entry.kind == .websocketChannel ? 1 : nil
    var channelPhase = entry.kind == .websocketChannel ? "active" : ""
    var pendingCapsSends: Int?
    var capsAwaitingDrain = false
    var requiredSuppressedCount = 0
    var requiredCapsProcessedCount = 0
    var requiredRefreshRequestCount = 0
    var requiredIgnoredStaleCallbackCount = 0

    for (index, step) in steps.enumerated() {
      let context = "\(entry.file):step \(index + 1)"
      switch step {
      case .decodeFailure(let id, _):
        guard activeDecodePlans.insert(id).inserted else {
          throw HostWireConformanceError.invalid("\(context): duplicate active decode plan")
        }
      case .expect(let expectation):
        // Outcome consumption is an execution-time obligation because only
        // the named painter can know how many decode attempts an emit caused.
        activeDecodePlans.removeAll(keepingCapacity: true)
        if entry.kind == .websocketChannel {
          guard case .object(let object) = expectation else {
            preconditionFailure("channel expectation was already validated")
          }
          let suppressed = try required(object, "suppressedSurfaceRecords").array(
            context: "\(context).suppressedSurfaceRecords")
          guard suppressed.count == requiredSuppressedCount else {
            throw HostWireConformanceError.invalid(
              "\(context): expected \(requiredSuppressedCount) suppressed surface records, got \(suppressed.count)"
            )
          }
          let connection = try required(object, "connection").object(
            keys: ["currentToken", "lastIssuedToken", "phase", "sceneInputFinished"],
            context: "\(context).connection")
          let expectedCurrentValue = required(connection, "currentToken")
          let expectedCurrent =
            expectedCurrentValue == .null
            ? nil : try expectedCurrentValue.integer(context: "\(context).connection.currentToken")
          let expectedLast = try required(connection, "lastIssuedToken").integer(
            context: "\(context).connection.lastIssuedToken")
          let expectedPhase = try required(connection, "phase").string(
            context: "\(context).connection.phase")
          guard expectedCurrent == currentToken, expectedLast == lastIssuedToken,
            expectedPhase == channelPhase
          else {
            throw HostWireConformanceError.invalid(
              "\(context): connection gauge disagrees with preceding channel actions")
          }
          for (key, requiredCount) in [
            ("capsProcessedCount", requiredCapsProcessedCount),
            ("refreshRequestCount", requiredRefreshRequestCount),
            ("ignoredStaleCallbackCount", requiredIgnoredStaleCallbackCount),
          ] {
            guard
              try required(object, key).integer(context: "\(context).\(key)")
                == requiredCount
            else {
              throw HostWireConformanceError.invalid(
                "\(context): \(key) disagrees with preceding channel actions")
            }
          }
          requiredSuppressedCount = 0
          requiredCapsProcessedCount = 0
          requiredRefreshRequestCount = 0
          requiredIgnoredStaleCallbackCount = 0
        } else if entry.kind == .androidABI {
          guard case .object(let object) = expectation else {
            preconditionFailure("Android expectation was already validated")
          }
          let deliveries = try required(object, "androidDeliveries").array(
            context: "\(context).androidDeliveries")
          guard deliveries.count == pendingAndroidCopies.count else {
            throw HostWireConformanceError.invalid(
              "\(context): one Android delivery is required per preceding copy action")
          }
          for (deliveryIndex, pair) in zip(deliveries, pendingAndroidCopies).enumerated() {
            guard case .object(let delivery) = pair.0 else {
              preconditionFailure("Android delivery was already validated")
            }
            let label = try required(delivery, "label").string(
              context: "\(context).androidDeliveries[\(deliveryIndex)].label")
            let capacity = try required(delivery, "capacity").integer(
              context: "\(context).androidDeliveries[\(deliveryIndex)].capacity")
            guard label == pair.1.label, capacity == pair.1.capacity else {
              throw HostWireConformanceError.invalid(
                "\(context): Android delivery order/label/capacity disagrees with copy actions")
            }
          }
          pendingAndroidCopies.removeAll(keepingCapacity: true)
        }
      case .androidABI(let action):
        let object = try action.object(
          keys: Set(try actionObjectKeys(action, context: context)),
          context: context
        )
        let name = try required(object, "action").string(context: "\(context).action")
        if name == "sizeQuery" {
          let label = try required(object, "label").string(context: "\(context).label")
          guard labels.insert(label).inserted else {
            throw HostWireConformanceError.invalid("\(context): duplicate size label \(label)")
          }
        } else if name == "copy" {
          let label = try required(object, "label").string(context: "\(context).label")
          guard labels.contains(label) else {
            throw HostWireConformanceError.invalid(
              "\(context): copy references missing or forward label \(label)")
          }
          let capacity = try required(object, "capacity").integer(
            context: "\(context).capacity")
          pendingAndroidCopies.append((label: label, capacity: capacity))
        }
      case .channel(let action):
        guard case .object(let object) = action else {
          preconditionFailure("channel action was already validated")
        }
        let name = try required(object, "action").string(context: "\(context).action")
        if name == "closeClient" || name == "clientChunk" {
          let token = try required(object, "token").integer(context: "\(context).token")
          guard token <= lastIssuedToken else {
            throw HostWireConformanceError.invalid("\(context): unknown future token \(token)")
          }
          if name == "closeClient", token == currentToken {
            currentToken = nil
            channelPhase = "detached"
            pendingCapsSends = nil
            capsAwaitingDrain = false
          } else if name == "closeClient" {
            requiredIgnoredStaleCallbackCount += 1
          }
        } else if name == "drainInput", capsAwaitingDrain {
          capsAwaitingDrain = false
          channelPhase = "active"
          pendingCapsSends = nil
          requiredCapsProcessedCount += 1
          requiredRefreshRequestCount += 1
        }
      case .reconnect(let capsAfter):
        guard entry.kind == .websocketChannel else {
          continue
        }
        guard currentToken == nil, pendingCapsSends == nil, !capsAwaitingDrain,
          let capsAfter
        else {
          throw HostWireConformanceError.invalid(
            "\(context): reconnect while attached or caps are pending")
        }
        lastIssuedToken += 1
        currentToken = lastIssuedToken
        channelPhase = "pre-capabilities"
        pendingCapsSends = capsAfter == 0 ? nil : capsAfter
        capsAwaitingDrain = capsAfter == 0
      case .emit(let raw):
        if entry.kind == .websocketChannel, raw.hasPrefix("\u{001E}surface:"),
          channelPhase == "pre-capabilities"
        {
          let (suppressedCount, suppressedOverflow) =
            requiredSuppressedCount.addingReportingOverflow(1)
          guard !suppressedOverflow else {
            throw HostWireConformanceError.invalid(
              "\(context): suppressed surface count overflows host Int")
          }
          requiredSuppressedCount = suppressedCount
          if let remaining = pendingCapsSends {
            let next = remaining - 1
            pendingCapsSends = next == 0 ? nil : next
            capsAwaitingDrain = next == 0
          }
        }
      case .drop, .evictImages:
        break
      }
    }
    guard activeDecodePlans.isEmpty else {
      throw HostWireConformanceError.invalid(
        "\(entry.file): decode plan has no following expectation")
    }
    guard pendingCapsSends == nil else {
      throw HostWireConformanceError.invalid("\(entry.file): unresolved delayed caps at EOF")
    }
    guard !capsAwaitingDrain else {
      throw HostWireConformanceError.invalid("\(entry.file): queued caps were not drained at EOF")
    }
    guard pendingAndroidCopies.isEmpty else {
      throw HostWireConformanceError.invalid(
        "\(entry.file): Android copy observations were not consumed at EOF")
    }
  }

  private static func actionObjectKeys(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws -> [String] {
    guard case .object(let object) = value else {
      throw HostWireConformanceError.invalid("\(context): expected action object")
    }
    return Array(object.keys)
  }

  static func resolveDrops(
    _ steps: [HostWireConformanceStep],
    context: String
  ) throws -> Set<Int> {
    var claimed: Set<Int> = []
    for (dropIndex, step) in steps.enumerated() {
      guard case .drop(let count) = step else {
        continue
      }
      var remaining = count
      var scan = dropIndex
      while scan > 0, remaining > 0 {
        scan -= 1
        let candidate = steps[scan]
        if candidate.isDropBarrier {
          break
        }
        if case .emit = candidate, claimed.insert(scan).inserted {
          remaining -= 1
        }
      }
      guard remaining == 0 else {
        throw HostWireConformanceError.invalid(
          "\(context): drop at step \(dropIndex + 1) cannot bind \(count) unmatched emits")
      }
    }
    return claimed
  }
}
