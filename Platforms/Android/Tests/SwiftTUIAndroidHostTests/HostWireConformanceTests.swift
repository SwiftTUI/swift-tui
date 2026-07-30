import Foundation
import Testing

@Suite
struct HostWireConformanceTests {
  @Test("portable test-only SHA-256 matches the FIPS known vector")
  func portableSHA256MatchesKnownVector() {
    #expect(
      HostWireConformanceSHA256.hexDigest(Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  @Test("strict JSON rejects nonintegral and host-Int-overflowing numbers")
  func strictJSONRejectsInvalidIntegers() {
    for source in [
      #"{"value":1.5}"#,
      #"{"value":999999999999999999999999999999999999}"#,
    ] {
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceJSON.parse(Data(source.utf8), context: "integer-meta")
      }
    }
  }

  @Test("manifest census is exact and every host adapter owns its stage")
  func manifestCensusIsExactAndEveryHostAdapterOwnsItsStage() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    #expect(corpus.manifest.formatVersion == 1)
    #expect(corpus.manifest.fixtures.count == 10)
    #expect(corpus.fixtures.count == corpus.manifest.fixtures.count)
    // S3d recorded its fixture from the real changed encoder, so `s3d` is now
    // part of the census rather than forbidden from it.
    #expect(
      corpus.manifest.fixtures.filter { $0.requiresStage == .s3d }.map(\.scenario)
        == ["style-append-splices-onto-the-retained-table"])

    let declarations: [HostWireConformanceRunnerDeclaration] = [
      .swiftAndroidABI, .swiftWebSocketChannel,
    ]
    // S3a and S3b have both landed, so no host fixture is inactive: an
    // unaccounted fixture is a failure, not a silent skip.
    #expect(declarations.map(\.implementedStages) == [[.s3a], [.s3b]])
    #expect(declarations.allSatisfy { $0.inactiveEntries(in: corpus.manifest).isEmpty })
    #expect(
      declarations.map { $0.requiredEntries(in: corpus.manifest).map(\.requiresStage) }
        == [[.s3a], [.s3b]])
  }

  @MainActor
  @Test("swift-android-abi executes the S3a delivery-commit scenario")
  func androidABIRunnerExecutesDeliveryCommitScenario() async throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let executed = try await HostWireConformanceAndroidABIRunner.runActiveFixtures(corpus)
    #expect(executed == ["android-delivery-commits-copied-candidate"])
    #expect(
      executed
        == HostWireConformanceRunnerDeclaration.swiftAndroidABI.requiredEntries(
          in: corpus.manifest
        ).map(\.scenario))
    #expect(
      HostWireConformanceRunnerDeclaration.swiftAndroidABI.inactiveEntries(
        in: corpus.manifest
      ).isEmpty)
  }

  @Test("swift-websocket-channel executes the S3b detached-backlog scenario")
  func webSocketChannelRunnerExecutesDetachedBacklogScenario() async throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let executed = try await HostWireConformanceWebSocketChannelRunner.runActiveFixtures(
      corpus)
    #expect(executed == ["websocket-detached-backlog-reconnects-by-token"])
    #expect(
      executed
        == HostWireConformanceRunnerDeclaration.swiftWebSocketChannel.requiredEntries(
          in: corpus.manifest
        ).map(\.scenario))
  }

  @Test("swift-reference executes every applicable record scenario")
  func swiftReferenceExecutesEveryApplicableRecordScenario() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let executed = try HostWireConformanceReferenceRunner.runActiveFixtures(corpus)
    let expected = HostWireConformanceRunnerDeclaration.swiftReference.requiredEntries(
      in: corpus.manifest
    ).map(\.scenario)
    #expect(executed == expected)
    #expect(
      executed == [
        "baseline-loss-refuses-stale-delta",
        "control-steady-delta",
        "epoch-reanchor-and-style-budget-full",
        "image-forget-requests-and-reapplies",
        "style-append-splices-onto-the-retained-table",
      ])
  }

  @Test("style-budget exhaustion records a same-epoch full frame")
  func styleBudgetExhaustionRecordsSameEpochFullFrame() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let fixture = try #require(
      corpus.fixtures["conformance-epoch-reanchor.jsonl"])
    let emitted = fixture.steps.compactMap { step -> String? in
      if case .emit(let record) = step {
        return record
      }
      return nil
    }
    #expect(emitted.count == 3)
    #expect(emitted[0].contains(#""epoch":103,"gen":1"#))
    #expect(emitted[1].contains(#""epoch":103,"gen":2"#))
    #expect(!emitted[1].contains(#""encoding":"delta""#))
    #expect(emitted[1].contains(##""styles":[null,{"fg":"#5BA3FFFF"}]"##))
    #expect(emitted[2].contains(#""epoch":104,"gen":1"#))
  }

  @Test("an explicit zero-sized full frame establishes a usable delta baseline")
  func zeroSizedFullFrameEstablishesBaseline() throws {
    let entry = HostWireConformanceManifestEntry(
      file: "conformance-zero-grid-meta.jsonl",
      scenario: "zero-grid-meta",
      kind: .record,
      mutationClass: .control,
      bodySHA256: String(repeating: "0", count: 64),
      requiresStage: .s1,
      runners: [.swiftReference]
    )
    let full =
      "\u{001E}surface:{\"version\":3,\"epoch\":9,\"gen\":1,\"sequence\":1,\"width\":0,\"height\":0,\"styles\":[null],\"rows\":[],\"images\":[]}\n"
    let delta =
      "\u{001E}surface:{\"version\":3,\"encoding\":\"delta\",\"epoch\":9,\"gen\":2,\"baselineGen\":1,\"sequence\":2,\"width\":0,\"height\":0,\"styles\":[null],\"deltaRows\":[],\"images\":[]}\n"
    let expected: HostWireConformanceJSON = .object([
      "rows": .array([]),
      "imagesVisible": .array([]),
      "resyncRequests": .array([]),
    ])
    var runner = HostWireConformanceReferenceRunner()
    try runner.run(
      HostWireConformanceFixture(
        entry: entry,
        steps: [.emit(full), .emit(delta), .expect(expected)],
        droppedEmitIndexes: []
      ))
  }

  @Test("two-pass drop resolution walks backward, passes drops, and stops at barriers")
  func twoPassDropResolutionIsDeterministic() throws {
    let emit = "\u{001E}surface:{\"version\":1}\n"
    let steps: [HostWireConformanceStep] = [
      .emit(emit),
      .emit(emit),
      .drop(1),
      .drop(1),
    ]
    #expect(try HostWireConformanceCorpus.resolveDrops(steps, context: "meta") == [0, 1])

    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.resolveDrops(
        [
          .emit(emit),
          .expect(.object([:])),
          .drop(1),
        ],
        context: "barrier"
      )
    }
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.resolveDrops(
        [.emit(emit), .drop(2)],
        context: "underflow"
      )
    }
  }

  @Test("structured grids preserve rows, intentional gaps, text, and spans")
  func structuredGridPreservesLosslessGeometry() throws {
    let value: HostWireConformanceJSON = .array([
      .object([
        "row": .integer(2),
        "cells": .array([
          .object([
            "column": .integer(1),
            "text": .string("A"),
            "span": .integer(1),
          ]),
          .object([
            "column": .integer(4),
            "text": .string("界"),
            "span": .integer(2),
          ]),
        ]),
      ])
    ])
    #expect(
      try HostWireConformanceCorpus.parseGridRows(value, context: "grid")
        == [
          .init(
            row: 2,
            cells: [
              .init(column: 1, text: "A", span: 1),
              .init(column: 4, text: "界", span: 2),
            ]
          )
        ])
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.parseGridRows(
        .array([
          .object([
            "row": .integer(0),
            "cells": .array([
              .object([
                "column": .integer(Int.max),
                "text": .string("X"),
                "span": .integer(1),
              ])
            ]),
          ])
        ]),
        context: "overflow-grid"
      )
    }
  }

  @Test("strict manifest rejects unknown fields, stages, and runner-order drift")
  func strictManifestRejectsSchemaDrift() throws {
    let generated = try HostWireConformanceStreamRecorder.record()
    let parsed = try #require(
      JSONSerialization.jsonObject(with: generated.manifestData) as? [String: Any])

    for mutation in ManifestMutation.allCases {
      var manifest = parsed
      mutation.apply(to: &manifest)
      var data = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
      data.append(0x0A)
      #expect(throws: HostWireConformanceError.self, "mutation: \(mutation)") {
        try HostWireConformanceCorpus.load(
          manifestData: data,
          fixtureData: generated.fixtureData
        )
      }
    }
  }

  @Test("raw corpus files reject BOM, CR, missing LF, and extra terminal LF")
  func rawCorpusFilesRejectByteNormalization() throws {
    let generated = try HostWireConformanceStreamRecorder.record()
    var mutations: [Data] = []
    mutations.append(Data(generated.manifestData.dropLast()))
    mutations.append(generated.manifestData + Data([0x0A]))
    mutations.append(Data([0xEF, 0xBB, 0xBF]) + generated.manifestData)
    var withCR = generated.manifestData
    withCR.insert(0x0D, at: withCR.index(before: withCR.endIndex))
    mutations.append(withCR)

    for mutation in mutations {
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceCorpus.load(
          manifestData: mutation,
          fixtureData: generated.fixtureData
        )
      }
    }
  }

  @Test("fixture grammar rejects unknown and forbidden host actions")
  func fixtureGrammarRejectsUnknownAndForbiddenHostActions() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let entry = try #require(
      corpus.manifest.fixtures.first { $0.requiresStage == .s3b })
    for action in ["shutdown", "detach", "requestRefresh", "future"] {
      let step: HostWireConformanceJSON = .object([
        "channel": .object(["action": .string(action)])
      ])
      #expect(throws: HostWireConformanceError.self, "action: \(action)") {
        try HostWireConformanceCorpus.parseStep(
          step,
          entry: entry,
          context: "forbidden-action"
        )
      }
    }
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.parseStep(
        .object(["future": .object([:])]),
        entry: entry,
        context: "unknown-step"
      )
    }
  }

  @Test("host fixture expectations are bound to their preceding action intervals")
  func hostFixtureExpectationsAreSequentiallyBound() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let android = try #require(
      corpus.fixtures["conformance-android-delivery-commit.jsonl"])
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.validateSequentialSemantics(
        Array(android.steps.dropLast()),
        entry: android.entry
      )
    }
    var reorderedAndroid = android.steps
    let (androidExpectationStep, androidExpectation) = try Self.firstExpectation(in: android)
    let reversedDeliveries = try Self.reversingArrayOrder(
      "androidDeliveries",
      in: androidExpectation
    )
    reorderedAndroid[androidExpectationStep] = .expect(reversedDeliveries)
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.validateSequentialSemantics(
        reorderedAndroid,
        entry: android.entry
      )
    }
    for (path, value) in [
      (
        [JSONPathPart.key("androidDeliveries"), .index(0), .key("label")],
        HostWireConformanceJSON.string("wrong-copy")
      ),
      (
        [JSONPathPart.key("androidDeliveries"), .index(0), .key("capacity")],
        HostWireConformanceJSON.integer(1)
      ),
    ] {
      let corruptedExpectation = try Self.settingJSONValue(
        at: path,
        to: value,
        in: androidExpectation
      )
      var corruptedAndroid = android.steps
      corruptedAndroid[androidExpectationStep] = .expect(corruptedExpectation)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceCorpus.validateSequentialSemantics(
          corruptedAndroid,
          entry: android.entry
        )
      }
    }

    let channel = try #require(
      corpus.fixtures["conformance-websocket-detached-backlog.jsonl"])
    let channelExpectation = try Self.expectation(in: channel)
    for path in [
      [JSONPathPart.key("connection"), .key("sceneInputFinished")],
      [JSONPathPart.key("connection"), .key("currentToken")],
      [JSONPathPart.key("parser"), .key("token")],
    ] {
      let corrupted = try Self.replacingJSONValue(at: path, in: channelExpectation)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceCorpus.validateExpectation(
          corrupted,
          entry: channel.entry,
          context: "channel-binding-meta"
        )
      }
    }
    let nonSurfaceSuppression = try Self.settingJSONValue(
      at: [.key("suppressedSurfaceRecords"), .index(0), .key("kind")],
      to: .string("non-surface"),
      in: channelExpectation
    )
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.validateExpectation(
        nonSurfaceSuppression,
        entry: channel.entry,
        context: "suppressed-surface-meta"
      )
    }
  }

  @Test("integrity rejects a changed manifest hash before execution")
  func integrityRejectsChangedManifestHash() throws {
    let generated = try HostWireConformanceStreamRecorder.record()
    let filename = "conformance-control.jsonl"
    var fixtures = generated.fixtureData
    let manifestHash = HostWireConformanceSHA256.hexDigest(generated.manifestData)
    fixtures[filename] = try Self.replacingFirst(
      manifestHash,
      with: Self.flippedHash(manifestHash),
      in: #require(fixtures[filename])
    )
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.load(
        manifestData: generated.manifestData,
        fixtureData: fixtures
      )
    }
  }

  @Test("integrity rejects a changed body hash before execution")
  func integrityRejectsChangedBodyHash() throws {
    let generated = try HostWireConformanceStreamRecorder.record()
    let filename = "conformance-control.jsonl"
    let corpus = try HostWireConformanceCorpus.load(
      manifestData: generated.manifestData,
      fixtureData: generated.fixtureData
    )
    let bodyHash = try #require(
      corpus.manifest.fixtures.first { $0.file == filename }?.bodySHA256)
    var fixtures = generated.fixtureData
    fixtures[filename] = try Self.replacingFirst(
      bodyHash,
      with: Self.flippedHash(bodyHash),
      in: #require(fixtures[filename])
    )
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.load(
        manifestData: generated.manifestData,
        fixtureData: fixtures
      )
    }
  }

  @Test("integrity rejects a changed hashed body byte before execution")
  func integrityRejectsChangedBodyByte() throws {
    let generated = try HostWireConformanceStreamRecorder.record()
    let filename = "conformance-control.jsonl"
    var fixtures = generated.fixtureData
    var bytes = Array(try #require(fixtures[filename]))
    let headerLF = try #require(bytes.firstIndex(of: 0x0A))
    bytes[headerLF + 1] = bytes[headerLF + 1] == 0x7B ? 0x5B : 0x7B
    fixtures[filename] = Data(bytes)
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceCorpus.load(
        manifestData: generated.manifestData,
        fixtureData: fixtures
      )
    }
  }

  @Test("reference observable-axis corruptions all fail exact comparison")
  func referenceObservableAxisMetaTestsHaveTeeth() {
    let actual = HostWireConformanceReferenceObservation(
      rows: [
        .init(
          row: 1,
          cells: [
            .init(column: 0, text: "A", span: 1),
            .init(column: 3, text: "界", span: 2),
          ]
        )
      ],
      imagesVisible: ["image-a", "image-b"],
      resyncRequests: [
        .object(["scope": .string("images"), "ids": .array([.string("image-a")])]),
        .object(["scope": .string("keyframe")]),
      ],
      styleRuns: [
        .init(
          row: 1,
          startColumn: 0,
          text: "A",
          span: 1,
          resolvedStyle: .object(["fg": .string("#E05757FF")])
        ),
        .init(
          row: 1,
          startColumn: 3,
          text: "界",
          span: 2,
          resolvedStyle: .object(["fg": .string("#E05757FF")])
        ),
      ]
    )
    for corruption in ReferenceCorruption.allCases {
      let expected = corruption.apply(to: actual)
      #expect(throws: HostWireConformanceError.self, "corruption: \(corruption)") {
        try HostWireConformanceExactComparator.requireEqual(
          actual,
          expected,
          context: "reference-meta"
        )
      }
    }
  }

  @Test("Android ABI expectation axes are exact")
  func androidABIExpectationMetaTestsHaveTeeth() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let fixture = try #require(corpus.fixtures["conformance-android-delivery-commit.jsonl"])
    let expected = try Self.expectation(in: fixture)
    // The undersized-copy interval carries the `copied:false` / `record:null`
    // axes the first interval cannot express; corrupting either must fail.
    let undersized = try Self.expectations(in: fixture)[1]
    for path in [
      [JSONPathPart.key("androidDeliveries"), .index(0), .key("copied")],
      [JSONPathPart.key("androidDeliveries"), .index(0), .key("record")],
    ] {
      let corrupted = try Self.replacingJSONValue(at: path, in: undersized)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          undersized,
          corrupted,
          context: "android-abi-undersized-meta"
        )
      }
    }
    let paths: [[JSONPathPart]] = [
      [.key("androidDeliveries"), .index(0), .key("reported")],
      [.key("androidDeliveries"), .index(0), .key("capacity")],
      [.key("androidDeliveries"), .index(0), .key("returned")],
      [.key("androidDeliveries"), .index(0), .key("copied")],
      [.key("androidDeliveries"), .index(0), .key("record"), .key("kind")],
      [.key("androidDeliveries"), .index(0), .key("record"), .key("epoch")],
      [.key("androidDeliveries"), .index(0), .key("record"), .key("gen")],
      [.key("androidDeliveries"), .index(1), .key("record"), .key("baselineGen")],
      [
        .key("androidDeliveries"), .index(0), .key("record"), .key("rows"), .index(0),
        .key("row"),
      ],
      [
        .key("androidDeliveries"), .index(0), .key("record"), .key("rows"), .index(0),
        .key("cells"), .index(0), .key("column"),
      ],
      [
        .key("androidDeliveries"), .index(0), .key("record"), .key("rows"), .index(0),
        .key("cells"), .index(0), .key("text"),
      ],
      [
        .key("androidDeliveries"), .index(0), .key("record"), .key("rows"), .index(0),
        .key("cells"), .index(0), .key("span"),
      ],
    ]
    for path in paths {
      let corrupted = try Self.replacingJSONValue(at: path, in: expected)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          expected,
          corrupted,
          context: "android-abi-meta"
        )
      }
    }
    for path in [
      [
        JSONPathPart.key("androidDeliveries"), .index(0), .key("record"), .key("rows"),
      ],
      [
        JSONPathPart.key("androidDeliveries"), .index(0), .key("record"), .key("rows"),
        .index(0), .key("cells"),
      ],
    ] {
      let corrupted = try Self.replacingArrayCensus(at: path, in: expected)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          expected,
          corrupted,
          context: "android-abi-grid-census-meta"
        )
      }
    }
    let gapBaseline = try Self.appendingAndroidGridCell(to: expected)
    let corruptedGap = try Self.replacingJSONValue(
      at: [
        .key("androidDeliveries"), .index(0), .key("record"), .key("rows"), .index(0),
        .key("cells"), .index(1), .key("column"),
      ],
      in: gapBaseline
    )
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceExactComparator.requireEqual(
        gapBaseline,
        corruptedGap,
        context: "android-abi-grid-gap-meta"
      )
    }
  }

  @Test("WebSocket channel expectation axes are exact")
  func webSocketChannelExpectationMetaTestsHaveTeeth() throws {
    let corpus = try HostWireConformanceCorpus.load(
      directory: HostWireConformanceStreamRecorder.fixtureDirectory)
    let expected = try Self.expectation(
      in: #require(corpus.fixtures["conformance-websocket-detached-backlog.jsonl"]))
    let paths: [[JSONPathPart]] = [
      [.key("deliveredRecords"), .index(0), .key("raw")],
      [.key("deliveredRecords"), .index(1), .key("kind")],
      [.key("deliveredRecords"), .index(1), .key("epoch")],
      [.key("deliveredRecords"), .index(1), .key("gen")],
      [.key("suppressedSurfaceRecords"), .index(1), .key("baselineGen")],
      [.key("detachedNonSurfaceBacklog"), .key("count")],
      [.key("detachedNonSurfaceBacklog"), .key("bytes")],
      [.key("refreshRequestCount")],
      [.key("capsProcessedCount")],
      [.key("ignoredStaleCallbackCount")],
      [.key("acceptedClientInputs"), .index(0)],
      [.key("discardedInboundChunks"), .index(0), .key("token")],
      [.key("discardedInboundChunks"), .index(0), .key("bytesBase64")],
      [.key("discardedInboundChunks"), .index(0), .key("reason")],
      [.key("parser"), .key("token")],
      [.key("parser"), .key("bufferedBytes")],
      [.key("connection"), .key("currentToken")],
      [.key("connection"), .key("lastIssuedToken")],
      [.key("connection"), .key("phase")],
      [.key("connection"), .key("sceneInputFinished")],
    ]
    for path in paths {
      let corrupted = try Self.replacingJSONValue(at: path, in: expected)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          expected,
          corrupted,
          context: "websocket-channel-meta"
        )
      }
    }
    let membershipCorruption = try Self.swappingDeliveredAndSuppressedMembership(in: expected)
    #expect(throws: HostWireConformanceError.self) {
      try HostWireConformanceExactComparator.requireEqual(
        expected,
        membershipCorruption,
        context: "websocket-channel-membership-meta"
      )
    }

    for arrayKey in [
      "deliveredRecords", "suppressedSurfaceRecords", "acceptedClientInputs",
      "discardedInboundChunks",
    ] {
      let corrupted = try Self.replacingArrayCensus(arrayKey, in: expected)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          expected,
          corrupted,
          context: "websocket-channel-census-meta"
        )
      }
    }
    for arrayKey in [
      "deliveredRecords", "suppressedSurfaceRecords", "acceptedClientInputs",
      "discardedInboundChunks",
    ] {
      let corrupted = try Self.reversingArrayOrder(arrayKey, in: expected)
      #expect(throws: HostWireConformanceError.self) {
        try HostWireConformanceExactComparator.requireEqual(
          expected,
          corrupted,
          context: "websocket-channel-order-meta"
        )
      }
    }
  }

}
