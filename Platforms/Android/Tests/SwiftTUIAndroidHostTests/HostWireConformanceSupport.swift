// Excluded from Windows builds (Windows plan, Stage 6 item 3): the cross-host
// wire-conformance suite drives the Android and WebHost adapters, whose
// modules build empty on Windows (whole-file-guarded).
#if !os(Windows)

  import Foundation

  struct HostWireConformanceGridCell: Equatable {
    var column: Int
    var text: String
    var span: Int
  }

  struct HostWireConformanceGridRow: Equatable {
    var row: Int
    var cells: [HostWireConformanceGridCell]
  }

  struct HostWireConformanceStyleRun: Equatable {
    var row: Int
    var startColumn: Int
    var text: String
    var span: Int
    var resolvedStyle: HostWireConformanceJSON
  }

  enum HostWireConformanceStage: String, CaseIterable {
    case s1
    case s2
    case s3a
    case s3b
    case s3d
  }

  enum HostWireConformanceRunner: String, CaseIterable {
    case swiftReference = "swift-reference"
    case webCanvas = "web-canvas"
    case webDOM = "web-dom"
    case android
    case swiftAndroidABI = "swift-android-abi"
    case swiftWebSocketChannel = "swift-websocket-channel"
  }

  enum HostWireConformanceKind: String, CaseIterable {
    case record
    case webPainter = "web-painter"
    case androidABI = "android-abi"
    case websocketChannel = "websocket-channel"
  }

  enum HostWireConformanceMutationClass: String, CaseIterable {
    case control
    case baselineLoss = "baseline-loss"
    case imageForget = "image-forget"
    case imageDecodeFailure = "image-decode-failure"
    case unknownToken = "unknown-token"
    case epochReanchor = "epoch-reanchor"
    case androidDeliveryCommit = "android-delivery-commit"
    case websocketDetachedBacklog = "websocket-detached-backlog"
    case styleAppend = "style-append"
  }

  struct HostWireConformanceManifestEntry: Equatable {
    var file: String
    var scenario: String
    var kind: HostWireConformanceKind
    var mutationClass: HostWireConformanceMutationClass
    var bodySHA256: String
    var requiresStage: HostWireConformanceStage
    var runners: [HostWireConformanceRunner]
  }

  struct HostWireConformanceManifest: Equatable {
    var formatVersion: Int
    var fixtures: [HostWireConformanceManifestEntry]
  }

  enum HostWireConformanceStep: Equatable {
    case emit(String)
    case drop(Int)
    case evictImages([String])
    case reconnect(capsAfter: Int?)
    case decodeFailure(id: String, outcomes: [String])
    case androidABI(HostWireConformanceJSON)
    case channel(HostWireConformanceJSON)
    case expect(HostWireConformanceJSON)

    var isDropBarrier: Bool {
      switch self {
      case .emit, .drop:
        return false
      case .evictImages, .reconnect, .decodeFailure, .androidABI, .channel, .expect:
        return true
      }
    }
  }

  struct HostWireConformanceFixture: Equatable {
    var entry: HostWireConformanceManifestEntry
    var steps: [HostWireConformanceStep]
    var droppedEmitIndexes: Set<Int>
  }

  struct HostWireConformanceCorpus {
    static let manifestFilename = "conformance-manifest.json"
    static let formatVersion = 1
    static let activeSwiftReferenceStages: Set<HostWireConformanceStage> = [.s1, .s2, .s3d]
    /// The epoch both the `android-abi` recorder and the `swift-android-abi`
    /// runner pin the host's encoding state to, so the byte-frozen fixture can
    /// name an exact `epoch` the process-global counter could never reproduce.
    /// The assertion is real: the emitted record must carry *this* epoch, and
    /// candidate-commit must not re-anchor it mid-handshake.
    static let androidABIRunnerEpochID: UInt32 = 301

    var manifestData: Data
    var manifest: HostWireConformanceManifest
    var fixtures: [String: HostWireConformanceFixture]

    static func load(
      directory: URL
    ) throws -> Self {
      let manifestURL = directory.appendingPathComponent(manifestFilename)
      let manifestData = try Data(contentsOf: manifestURL)
      var fixtureData: [String: Data] = [:]
      for url in try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )
      where url.lastPathComponent.hasPrefix("conformance-")
        && url.pathExtension == "jsonl"
      {
        fixtureData[url.lastPathComponent] = try Data(contentsOf: url)
      }
      return try load(manifestData: manifestData, fixtureData: fixtureData)
    }

    static func load(
      manifestData: Data,
      fixtureData: [String: Data]
    ) throws -> Self {
      try validateTextBytes(manifestData, context: manifestFilename)
      let manifestJSON = try HostWireConformanceJSON.parse(
        manifestData,
        context: manifestFilename
      )
      let manifest = try parseManifest(manifestJSON)
      let expectedFiles = Set(manifest.fixtures.map(\.file))
      let actualFiles = Set(fixtureData.keys)
      guard actualFiles == expectedFiles else {
        throw HostWireConformanceError.invalid(
          "fixture census mismatch: expected \(expectedFiles.sorted()), got \(actualFiles.sorted())"
        )
      }

      let manifestHash = HostWireConformanceSHA256.hexDigest(manifestData)
      var fixtures: [String: HostWireConformanceFixture] = [:]
      for entry in manifest.fixtures {
        guard let data = fixtureData[entry.file] else {
          throw HostWireConformanceError.invalid("\(entry.file): missing fixture body")
        }
        fixtures[entry.file] = try parseFixture(
          entry: entry,
          data: data,
          manifestHash: manifestHash
        )
      }
      return Self(manifestData: manifestData, manifest: manifest, fixtures: fixtures)
    }

    private static func validateTextBytes(
      _ data: Data,
      context: String
    ) throws {
      let bytes = Array(data)
      guard !bytes.isEmpty else {
        throw HostWireConformanceError.invalid("\(context): file is empty")
      }
      guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else {
        throw HostWireConformanceError.invalid("\(context): UTF-8 BOM is forbidden")
      }
      guard !bytes.contains(0x0D) else {
        throw HostWireConformanceError.invalid("\(context): CR bytes are forbidden")
      }
      guard bytes.last == 0x0A, bytes.dropLast().last != 0x0A else {
        throw HostWireConformanceError.invalid(
          "\(context): file must contain exactly one terminal LF")
      }
      guard String(data: data, encoding: .utf8) != nil else {
        throw HostWireConformanceError.invalid("\(context): file is not UTF-8")
      }
      let lines = data.dropLast().split(separator: 0x0A, omittingEmptySubsequences: false)
      guard lines.allSatisfy({ !$0.isEmpty }) else {
        throw HostWireConformanceError.invalid("\(context): blank lines are forbidden")
      }
    }

    private static func parseManifest(
      _ json: HostWireConformanceJSON
    ) throws -> HostWireConformanceManifest {
      let object = try json.object(
        keys: ["formatVersion", "fixtures"],
        context: manifestFilename
      )
      let formatVersion = try required(object, "formatVersion").integer(
        context: "\(manifestFilename).formatVersion")
      guard formatVersion == Self.formatVersion else {
        throw HostWireConformanceError.invalid(
          "\(manifestFilename): unsupported formatVersion \(formatVersion)")
      }
      let fixtureValues = try required(object, "fixtures").array(
        context: "\(manifestFilename).fixtures")
      var entries: [HostWireConformanceManifestEntry] = []
      entries.reserveCapacity(fixtureValues.count)
      for (index, value) in fixtureValues.enumerated() {
        let context = "\(manifestFilename).fixtures[\(index)]"
        let entryObject = try value.object(
          keys: [
            "file", "scenario", "kind", "mutationClass", "bodySHA256", "requiresStage",
            "runners",
          ],
          context: context
        )
        let file = try required(entryObject, "file").string(context: "\(context).file")
        let scenario = try required(entryObject, "scenario").string(
          context: "\(context).scenario")
        let kind = try enumValue(
          HostWireConformanceKind.self,
          json: required(entryObject, "kind"),
          context: "\(context).kind"
        )
        let mutationClass = try enumValue(
          HostWireConformanceMutationClass.self,
          json: required(entryObject, "mutationClass"),
          context: "\(context).mutationClass"
        )
        let bodySHA256 = try required(entryObject, "bodySHA256").string(
          context: "\(context).bodySHA256")
        let requiresStage = try enumValue(
          HostWireConformanceStage.self,
          json: required(entryObject, "requiresStage"),
          context: "\(context).requiresStage"
        )
        let runnerValues = try required(entryObject, "runners").array(
          context: "\(context).runners")
        let runners = try runnerValues.enumerated().map { runnerIndex, runnerValue in
          try enumValue(
            HostWireConformanceRunner.self,
            json: runnerValue,
            context: "\(context).runners[\(runnerIndex)]"
          )
        }
        let entry = HostWireConformanceManifestEntry(
          file: file,
          scenario: scenario,
          kind: kind,
          mutationClass: mutationClass,
          bodySHA256: bodySHA256,
          requiresStage: requiresStage,
          runners: runners
        )
        try validateManifestEntry(entry, context: context)
        entries.append(entry)
      }

      guard entries.map(\.file) == entries.map(\.file).sorted() else {
        throw HostWireConformanceError.invalid(
          "\(manifestFilename): fixtures must be sorted by filename")
      }
      guard Set(entries.map(\.file)).count == entries.count else {
        throw HostWireConformanceError.invalid("\(manifestFilename): duplicate fixture filename")
      }
      guard Set(entries.map(\.scenario)).count == entries.count else {
        throw HostWireConformanceError.invalid("\(manifestFilename): duplicate scenario ID")
      }
      return HostWireConformanceManifest(formatVersion: formatVersion, fixtures: entries)
    }

    private static func validateManifestEntry(
      _ entry: HostWireConformanceManifestEntry,
      context: String
    ) throws {
      guard entry.file.hasPrefix("conformance-"), entry.file.hasSuffix(".jsonl") else {
        throw HostWireConformanceError.invalid(
          "\(context): file must match conformance-*.jsonl")
      }
      let scenarioPattern = try! NSRegularExpression(pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$")
      let scenarioRange = NSRange(entry.scenario.startIndex..., in: entry.scenario)
      guard scenarioPattern.firstMatch(in: entry.scenario, range: scenarioRange) != nil else {
        throw HostWireConformanceError.invalid("\(context): scenario must be kebab-case")
      }
      guard isLowercaseSHA256(entry.bodySHA256) else {
        throw HostWireConformanceError.invalid("\(context): bodySHA256 is not lowercase SHA-256")
      }
      let order = Dictionary(
        uniqueKeysWithValues: HostWireConformanceRunner.allCases.enumerated().map {
          ($0.element, $0.offset)
        })
      guard Set(entry.runners).count == entry.runners.count,
        entry.runners == entry.runners.sorted(by: { order[$0]! < order[$1]! })
      else {
        throw HostWireConformanceError.invalid(
          "\(context): runners must be a duplicate-free ordered subset")
      }

      let expected:
        (
          kind: HostWireConformanceKind,
          stage: HostWireConformanceStage,
          runners: [HostWireConformanceRunner]
        )
      switch entry.mutationClass {
      case .control:
        expected = (.record, .s1, [.swiftReference, .webCanvas, .webDOM, .android])
      case .baselineLoss:
        expected = (.record, .s1, [.swiftReference, .webCanvas, .webDOM, .android])
      case .imageForget:
        if entry.kind == .record {
          expected = (.record, .s2, [.swiftReference, .android])
        } else {
          expected = (.webPainter, .s2, [.webCanvas, .webDOM])
        }
      case .imageDecodeFailure:
        expected = (.webPainter, .s2, [.webCanvas])
      case .unknownToken:
        expected = (.record, .s1, [.webCanvas, .webDOM, .android])
      case .epochReanchor:
        expected = (.record, .s1, [.swiftReference, .webCanvas, .webDOM, .android])
      case .androidDeliveryCommit:
        expected = (.androidABI, .s3a, [.swiftAndroidABI])
      case .websocketDetachedBacklog:
        expected = (.websocketChannel, .s3b, [.swiftWebSocketChannel])
      case .styleAppend:
        expected = (.record, .s3d, [.swiftReference, .webCanvas, .webDOM, .android])
      }
      guard entry.kind == expected.kind, entry.requiresStage == expected.stage,
        entry.runners == expected.runners
      else {
        throw HostWireConformanceError.invalid(
          "\(context): mutationClass/kind/stage/runner applicability mismatch")
      }
    }

    private static func parseFixture(
      entry: HostWireConformanceManifestEntry,
      data: Data,
      manifestHash: String
    ) throws -> HostWireConformanceFixture {
      try validateTextBytes(data, context: entry.file)
      guard let headerLF = data.firstIndex(of: 0x0A) else {
        throw HostWireConformanceError.invalid("\(entry.file): missing header LF")
      }
      let headerData = data[..<headerLF]
      let bodyStart = data.index(after: headerLF)
      let bodyData = data[bodyStart...]
      let headerJSON = try HostWireConformanceJSON.parse(
        Data(headerData),
        context: "\(entry.file):header"
      )
      let header = try headerJSON.object(
        keys: ["formatVersion", "manifestSHA256", "bodySHA256"],
        context: "\(entry.file):header"
      )
      let formatVersion = try required(header, "formatVersion").integer(
        context: "\(entry.file):header.formatVersion")
      let recordedManifestHash = try required(header, "manifestSHA256").string(
        context: "\(entry.file):header.manifestSHA256")
      let recordedBodyHash = try required(header, "bodySHA256").string(
        context: "\(entry.file):header.bodySHA256")
      guard formatVersion == Self.formatVersion else {
        throw HostWireConformanceError.invalid("\(entry.file): unsupported header formatVersion")
      }
      guard recordedManifestHash == manifestHash else {
        throw HostWireConformanceError.invalid("\(entry.file): manifestSHA256 mismatch")
      }
      guard recordedBodyHash == entry.bodySHA256 else {
        throw HostWireConformanceError.invalid("\(entry.file): manifest/header body hash mismatch")
      }
      let actualBodyHash = HostWireConformanceSHA256.hexDigest(Data(bodyData))
      guard actualBodyHash == recordedBodyHash else {
        throw HostWireConformanceError.invalid("\(entry.file): bodySHA256 mismatch")
      }

      let bodyWithoutLF = bodyData.dropLast()
      let lineData = bodyWithoutLF.split(separator: 0x0A, omittingEmptySubsequences: false)
      var steps: [HostWireConformanceStep] = []
      steps.reserveCapacity(lineData.count)
      for (index, line) in lineData.enumerated() {
        let context = "\(entry.file):line \(index + 2)"
        let json = try HostWireConformanceJSON.parse(Data(line), context: context)
        steps.append(try parseStep(json, entry: entry, context: context))
      }
      try validateSequentialSemantics(steps, entry: entry)
      let dropped = try resolveDrops(steps, context: entry.file)
      return HostWireConformanceFixture(
        entry: entry,
        steps: steps,
        droppedEmitIndexes: dropped
      )
    }

    static func parseStep(
      _ json: HostWireConformanceJSON,
      entry: HostWireConformanceManifestEntry,
      context: String
    ) throws -> HostWireConformanceStep {
      guard case .object(let object) = json, object.count == 1, let key = object.keys.first,
        let value = object[key]
      else {
        throw HostWireConformanceError.invalid(
          "\(context): step must be an object with exactly one action")
      }
      switch key {
      case "emit":
        guard
          entry.kind == .record || entry.kind == .webPainter
            || entry.kind == .websocketChannel
        else {
          throw HostWireConformanceError.invalid(
            "\(context): emit is inapplicable to \(entry.kind)")
        }
        let record = try value.string(context: "\(context).emit")
        try validateEmittedRecord(
          record, allowsNonSurface: entry.kind == .websocketChannel, context: context)
        return .emit(record)
      case "drop":
        guard entry.kind == .record || entry.kind == .webPainter else {
          throw HostWireConformanceError.invalid(
            "\(context): drop is inapplicable to \(entry.kind)")
        }
        let count = try value.integer(context: "\(context).drop")
        guard count > 0 else {
          throw HostWireConformanceError.invalid("\(context): drop must be positive")
        }
        return .drop(count)
      case "evictImages":
        guard entry.kind == .record || entry.kind == .webPainter else {
          throw HostWireConformanceError.invalid(
            "\(context): evictImages is inapplicable to \(entry.kind)")
        }
        let values = try value.array(context: "\(context).evictImages")
        let ids = try values.enumerated().map {
          try $0.element.string(context: "\(context).evictImages[\($0.offset)]")
        }
        guard !ids.isEmpty, Set(ids).count == ids.count else {
          throw HostWireConformanceError.invalid(
            "\(context): evictImages must contain unique IDs")
        }
        return .evictImages(ids)
      case "reconnect":
        if entry.kind == .record || entry.kind == .webPainter {
          _ = try value.object(keys: [], context: "\(context).reconnect")
          return .reconnect(capsAfter: nil)
        }
        guard entry.kind == .websocketChannel,
          entry.mutationClass == .websocketDetachedBacklog
        else {
          throw HostWireConformanceError.invalid(
            "\(context): reconnect is inapplicable to \(entry.kind)")
        }
        let reconnect = try value.object(keys: ["capsAfter"], context: "\(context).reconnect")
        let count = try required(reconnect, "capsAfter").integer(
          context: "\(context).reconnect.capsAfter")
        guard count >= 0 else {
          throw HostWireConformanceError.invalid("\(context): capsAfter must be nonnegative")
        }
        return .reconnect(capsAfter: count)
      case "decodeFailure":
        guard entry.kind == .webPainter, entry.mutationClass == .imageDecodeFailure,
          entry.runners == [.webCanvas]
        else {
          throw HostWireConformanceError.invalid(
            "\(context): decodeFailure is canvas image-decode-failure-only")
        }
        let plan = try value.object(
          keys: ["id", "outcomes"],
          context: "\(context).decodeFailure"
        )
        let id = try required(plan, "id").string(context: "\(context).decodeFailure.id")
        let outcomeValues = try required(plan, "outcomes").array(
          context: "\(context).decodeFailure.outcomes")
        let outcomes = try outcomeValues.enumerated().map {
          try $0.element.string(context: "\(context).decodeFailure.outcomes[\($0.offset)]")
        }
        guard !id.isEmpty, !outcomes.isEmpty,
          outcomes.allSatisfy({ $0 == "failure" || $0 == "success" })
        else {
          throw HostWireConformanceError.invalid(
            "\(context): decode plan must have an ID and failure/success outcomes")
        }
        return .decodeFailure(id: id, outcomes: outcomes)
      case "androidABI":
        guard entry.kind == .androidABI else {
          throw HostWireConformanceError.invalid(
            "\(context): androidABI is inapplicable to \(entry.kind)")
        }
        try validateAndroidABIAction(value, context: "\(context).androidABI")
        return .androidABI(value)
      case "channel":
        guard entry.kind == .websocketChannel else {
          throw HostWireConformanceError.invalid(
            "\(context): channel is inapplicable to \(entry.kind)")
        }
        try validateChannelAction(value, context: "\(context).channel")
        return .channel(value)
      case "expect":
        try validateExpectation(value, entry: entry, context: "\(context).expect")
        return .expect(value)
      default:
        throw HostWireConformanceError.invalid("\(context): unknown action \(key)")
      }
    }

    static func required(
      _ object: [String: HostWireConformanceJSON],
      _ key: String
    ) -> HostWireConformanceJSON {
      guard let value = object[key] else {
        preconditionFailure("strict object validation omitted required key \(key)")
      }
      return value
    }

    private static func enumValue<T>(
      _ type: T.Type,
      json: HostWireConformanceJSON,
      context: String
    ) throws -> T where T: RawRepresentable, T.RawValue == String {
      let rawValue = try json.string(context: context)
      guard let value = T(rawValue: rawValue) else {
        throw HostWireConformanceError.invalid("\(context): unknown value \(rawValue)")
      }
      return value
    }

    private static func isLowercaseSHA256(
      _ value: String
    ) -> Bool {
      value.count == 64
        && value.utf8.allSatisfy {
          (48...57).contains($0) || (97...102).contains($0)
        }
    }
  }

  struct HostWireConformanceRunnerDeclaration: Equatable {
    var id: HostWireConformanceRunner
    var implementedStages: Set<HostWireConformanceStage>

    static let swiftReference = Self(
      id: .swiftReference,
      implementedStages: HostWireConformanceCorpus.activeSwiftReferenceStages
    )
    static let swiftAndroidABI = Self(id: .swiftAndroidABI, implementedStages: [.s3a])
    static let swiftWebSocketChannel = Self(
      id: .swiftWebSocketChannel,
      implementedStages: [.s3b]
    )

    func requiredEntries(
      in manifest: HostWireConformanceManifest
    ) -> [HostWireConformanceManifestEntry] {
      manifest.fixtures.filter {
        $0.runners.contains(id) && implementedStages.contains($0.requiresStage)
      }
    }

    func inactiveEntries(
      in manifest: HostWireConformanceManifest
    ) -> [HostWireConformanceManifestEntry] {
      manifest.fixtures.filter {
        $0.runners.contains(id) && !implementedStages.contains($0.requiresStage)
      }
    }
  }

#endif
