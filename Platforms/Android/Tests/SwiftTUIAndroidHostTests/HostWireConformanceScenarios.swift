import Foundation
@_spi(Runners) import SwiftTUIRuntime

extension HostWireConformanceStreamRecorder {
  static func recordedScenarios() throws -> [Scenario] {
    var scenarios: [Scenario] = []
    scenarios.append(try controlScenario())
    scenarios.append(try baselineLossScenario())
    scenarios.append(try epochReanchorScenario())
    let image = try imageRecords()
    scenarios.append(try imageForgetRecordScenario(image))
    scenarios.append(try imageForgetWebPainterScenario(image))
    scenarios.append(try imageDecodeFailureScenario(image))
    scenarios.append(try unknownTokenScenario())
    scenarios.append(try androidDeliveryCommitScenario())
    scenarios.append(try websocketDetachedBacklogScenario())
    return scenarios
  }

  private static func controlScenario() throws -> Scenario {
    var state = HostWireEncodingState(deltaEnabled: true, epochID: 101)
    let initial = encode(
      surface: sparseWideSurface(leading: "A", wide: "界"),
      sequence: 1,
      damage: nil,
      state: &state
    )
    let changed = encode(
      surface: sparseWideSurface(leading: "B", wide: "宽"),
      sequence: 2,
      damage: fullRowDamage(width: 4),
      state: &state
    )
    let resized = encode(
      surface: RasterSurface(size: .init(width: 2, height: 1), lines: ["RZ"]),
      sequence: 3,
      damage: fullRowDamage(width: 2),
      state: &state
    )
    return Scenario(
      file: "conformance-control.jsonl",
      scenario: "control-steady-delta",
      kind: .record,
      mutationClass: .control,
      requiresStage: .s1,
      runners: [.swiftReference, .webCanvas, .webDOM, .android],
      steps: [
        ["emit": initial],
        ["emit": changed],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: changed,
              context: "control changed"
            ))
        ],
        ["emit": resized],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: resized,
              context: "control resized"
            ))
        ],
      ]
    )
  }

  private static func baselineLossScenario() throws -> Scenario {
    var state = HostWireEncodingState(deltaEnabled: true, epochID: 102)
    let initial = encode(
      surface: singleCellSurface("A"),
      sequence: 1,
      damage: nil,
      state: &state
    )
    let dropped = encode(
      surface: singleCellSurface("B"),
      sequence: 2,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    let stale = encode(
      surface: singleCellSurface("C"),
      sequence: 3,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    state.requestResync(.init(scope: .keyframe))
    let repaired = encode(
      surface: singleCellSurface("D"),
      sequence: 4,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    return Scenario(
      file: "conformance-baseline-loss.jsonl",
      scenario: "baseline-loss-refuses-stale-delta",
      kind: .record,
      mutationClass: .baselineLoss,
      requiresStage: .s1,
      runners: [.swiftReference, .webCanvas, .webDOM, .android],
      steps: [
        ["emit": initial],
        ["emit": dropped],
        ["drop": 1],
        ["emit": stale],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: initial,
              context: "baseline initial"
            ),
            resyncRequests: [["scope": "keyframe"]]
          )
        ],
        ["emit": repaired],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: repaired,
              context: "baseline repaired"
            ))
        ],
      ]
    )
  }

  private static func epochReanchorScenario() throws -> Scenario {
    var firstState = HostWireEncodingState(deltaEnabled: true, epochID: 103)
    let first = encode(
      surface: styledSingleCellSurface("A", color: .red),
      sequence: 1,
      damage: nil,
      state: &firstState
    )
    var colorSeed: UInt32 = 0
    while firstState.persistentStyles.count < 1_024 {
      let count = firstState.persistentStyles.count
      _ = firstState.persistentStyles.index(
        for: ResolvedTextStyle(foregroundColor: Color(hexRGB: colorSeed))
      )
      colorSeed += 1
      precondition(
        firstState.persistentStyles.count >= count,
        "style-budget setup must be monotonic"
      )
    }
    let styleBudgetFull = encode(
      surface: styledSingleCellSurface("C", color: .blue),
      sequence: 2,
      damage: fullRowDamage(width: 1),
      state: &firstState
    )
    precondition(
      !styleBudgetFull.contains(#""encoding":"delta""#)
        && styleBudgetFull.contains(#""epoch":103,"gen":2"#),
      "style-budget exhaustion must fall back to a full frame in the same epoch"
    )
    var reanchoredState = HostWireEncodingState(deltaEnabled: true, epochID: 104)
    let reanchored = encode(
      surface: singleCellSurface("R"),
      sequence: 3,
      damage: nil,
      state: &reanchoredState
    )
    return Scenario(
      file: "conformance-epoch-reanchor.jsonl",
      scenario: "epoch-reanchor-and-style-budget-full",
      kind: .record,
      mutationClass: .epochReanchor,
      requiresStage: .s1,
      runners: [.swiftReference, .webCanvas, .webDOM, .android],
      steps: [
        ["emit": first],
        ["emit": styleBudgetFull],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: styleBudgetFull,
              context: "style budget full"
            ),
            styleRuns: [
              styleRun(
                row: 0,
                startColumn: 0,
                text: "C",
                span: 1,
                resolvedStyle: ["fg": "#5BA3FFFF"]
              )
            ]
          )
        ],
        ["reconnect": [:]],
        ["emit": reanchored],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: reanchored,
              context: "epoch reanchored"
            ),
            styleRuns: []
          )
        ],
      ]
    )
  }

  private struct ImageRecords {
    var id: String
    var initial: String
    var payloadLessOne: String
    var payloadLessTwo: String
    var repaired: String
  }

  private static func imageRecords() throws -> ImageRecords {
    var state = HostWireEncodingState(deltaEnabled: true, epochID: 105)
    let initial = encode(
      surface: imageSurface(),
      sequence: 1,
      damage: nil,
      state: &state
    )
    let id = try imageID(in: initial)
    let payloadLessOne = encode(
      surface: imageSurface(),
      sequence: 2,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    let payloadLessTwo = encode(
      surface: imageSurface(),
      sequence: 3,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    state.requestResync(.init(scope: .images([id])))
    let repaired = encode(
      surface: imageSurface(),
      sequence: 4,
      damage: fullRowDamage(width: 1),
      state: &state
    )
    return .init(
      id: id,
      initial: initial,
      payloadLessOne: payloadLessOne,
      payloadLessTwo: payloadLessTwo,
      repaired: repaired
    )
  }

  private static func imageForgetRecordScenario(
    _ records: ImageRecords
  ) throws -> Scenario {
    try Scenario(
      file: "conformance-image-forget-record.jsonl",
      scenario: "image-forget-requests-and-reapplies",
      kind: .record,
      mutationClass: .imageForget,
      requiresStage: .s2,
      runners: [.swiftReference, .android],
      steps: [
        ["emit": records.initial],
        [
          "expect": expectation(
            rows: HostWireConformanceRecordDecoding.structuredRows(
              in: records.initial,
              context: "image initial"
            ),
            imagesVisible: [records.id]
          )
        ],
        ["evictImages": [records.id]],
        ["emit": records.payloadLessOne],
        [
          "expect": expectation(
            rows: HostWireConformanceRecordDecoding.structuredRows(
              in: records.payloadLessOne,
              context: "image payload-less"
            ),
            resyncRequests: [["scope": "images", "ids": [records.id]]]
          )
        ],
        ["emit": records.payloadLessTwo],
        ["emit": records.repaired],
        [
          "expect": expectation(
            rows: HostWireConformanceRecordDecoding.structuredRows(
              in: records.repaired,
              context: "image repaired"
            ),
            imagesVisible: [records.id]
          )
        ],
      ]
    )
  }

  private static func imageForgetWebPainterScenario(
    _ records: ImageRecords
  ) throws -> Scenario {
    try Scenario(
      file: "conformance-image-forget-web-painter.jsonl",
      scenario: "web-painter-image-forget-requests-and-reapplies",
      kind: .webPainter,
      mutationClass: .imageForget,
      requiresStage: .s2,
      runners: [.webCanvas, .webDOM],
      steps: imageForgetRecordScenario(records).steps
    )
  }

  private static func imageDecodeFailureScenario(
    _ records: ImageRecords
  ) throws -> Scenario {
    try Scenario(
      file: "conformance-image-decode-failure.jsonl",
      scenario: "canvas-decode-failure-retries-deterministically",
      kind: .webPainter,
      mutationClass: .imageDecodeFailure,
      requiresStage: .s2,
      runners: [.webCanvas],
      steps: [
        ["decodeFailure": ["id": records.id, "outcomes": ["failure", "failure", "success"]]],
        ["emit": records.initial],
        ["emit": records.payloadLessOne],
        ["emit": records.payloadLessTwo],
        [
          "expect": expectation(
            rows: HostWireConformanceRecordDecoding.structuredRows(
              in: records.payloadLessTwo,
              context: "image decode retry"
            ),
            imagesVisible: [records.id]
          )
        ],
      ]
    )
  }

  private static func unknownTokenScenario() throws -> Scenario {
    var state = HostWireEncodingState(deltaEnabled: false, epochID: 106)
    let production = WebSurfaceFrameEncoder.encode(
      HostWireFrameModel(
        surface: singleCellSurface("U"),
        sequence: 1,
        semanticSnapshot: SemanticSnapshot(
          accessibilityAnnouncements: [
            AccessibilityAnnouncement(message: "future token", politeness: .polite)
          ]
        ),
        focusedIdentity: nil,
        damage: nil,
        preferredLayoutSize: nil
      ),
      fallbackBackground: TerminalAppearance.fallback.backgroundColor,
      state: &state
    )
    let known = #""politeness":"polite""#
    let occurrences = production.components(separatedBy: known).count - 1
    precondition(occurrences == 1, "unknown-token fixture must mutate one encoder token")
    let mutated = production.replacingOccurrences(
      of: known,
      with: #""politeness":"future-priority""#
    )
    return Scenario(
      file: "conformance-unknown-token.jsonl",
      scenario: "unknown-token-degrades-per-record",
      kind: .record,
      mutationClass: .unknownToken,
      requiresStage: .s1,
      runners: [.webCanvas, .webDOM, .android],
      steps: [
        ["emit": mutated],
        [
          "expect": expectation(
            rows: try HostWireConformanceRecordDecoding.structuredRows(
              in: production,
              context: "unknown token production source"
            ))
        ],
      ]
    )
  }

  private static func androidDeliveryCommitScenario() throws -> Scenario {
    var state = HostWireEncodingState(
      deltaEnabled: true,
      epochID: HostWireConformanceCorpus.androidABIRunnerEpochID
    )
    // This scenario's bytes must be the bytes the *Android host seam* emits,
    // not the bytes a bare encoder call emits: the host always encodes with
    // its render style (`AndroidHostStyle.default.renderStyle`), so the record
    // carries a `terminalStyle` object. Recording without it produced a
    // fixture no real ABI delivery could ever satisfy.
    let hostStyle = TerminalRenderStyle(appearance: .fallback)
    // Two independently damageable columns with a gap between them: that is
    // what makes the accumulated-damage half of the candidate rule observable
    // in the delivered rows rather than only in the byte count.
    let first = encode(
      surface: gappedSurface("A", "Z"),
      sequence: 1,
      damage: nil,
      state: &state,
      terminalStyle: hostStyle
    )
    let second = encode(
      surface: gappedSurface("B", "Z"),
      sequence: 2,
      damage: columnDamage([0..<1]),
      state: &state,
      terminalStyle: hostStyle
    )
    // The abandoned-handshake discriminator. Sequence 3 changes the trailing
    // column and is size-queried but never copied, so nothing of it ever
    // reaches the wire: its generation must not be consumed and its damage
    // must not be lost. The recorder therefore does *not* encode it — the next
    // delivered record is sequence 4's delta, still generation 3 against
    // baseline generation 2, and it must carry *both* changed columns.
    //
    // An encoder that ratchets at encode time instead hands the consumer
    // generation 4 over a baseline generation 3 it never received; one that
    // drops the abandoned candidate's damage silently strands the trailing
    // column at its stale glyph forever.
    let third = encode(
      surface: gappedSurface("C", "Y"),
      sequence: 4,
      damage: columnDamage([0..<1, 2..<3]),
      state: &state,
      terminalStyle: hostStyle
    )
    let fourth = encode(
      surface: gappedSurface("C", "X"),
      sequence: 5,
      damage: columnDamage([2..<3]),
      state: &state,
      terminalStyle: hostStyle
    )
    return Scenario(
      file: "conformance-android-delivery-commit.jsonl",
      scenario: "android-delivery-commits-copied-candidate",
      kind: .androidABI,
      mutationClass: .androidDeliveryCommit,
      requiresStage: .s3a,
      runners: [.swiftAndroidABI],
      steps: [
        [
          "androidABI": [
            "action": "publish", "sequence": 1, "width": 3, "height": 1,
            "rows": [gridRow(0, [(0, "A", 1), (2, "Z", 1)])], "damage": NSNull(),
          ]
        ],
        ["androidABI": ["action": "sizeQuery", "label": "q1"]],
        [
          "androidABI": [
            "action": "publish", "sequence": 2, "width": 3, "height": 1,
            "rows": [gridRow(0, [(0, "B", 1), (2, "Z", 1)])],
            "damage": ["rows": [["row": 0, "ranges": [[0, 1]]]]],
          ]
        ],
        // The straddle: sequence 2 committed between q1's size query and its
        // copy. The copy must still deliver the bytes q1 measured.
        ["androidABI": ["action": "copy", "label": "q1", "capacity": 4096]],
        ["androidABI": ["action": "sizeQuery", "label": "q2"]],
        ["androidABI": ["action": "copy", "label": "q2", "capacity": 4096]],
        [
          "expect": [
            "androidDeliveries": [
              try HostWireConformanceRecordDecoding.androidDelivery(
                label: "q1",
                reported: first.utf8.count,
                capacity: 4096,
                returned: first.utf8.count,
                raw: first
              ),
              try HostWireConformanceRecordDecoding.androidDelivery(
                label: "q2",
                reported: second.utf8.count,
                capacity: 4096,
                returned: second.utf8.count,
                raw: second
              ),
            ]
          ]
        ],
        [
          "androidABI": [
            "action": "publish", "sequence": 3, "width": 3, "height": 1,
            "rows": [gridRow(0, [(0, "B", 1), (2, "Y", 1)])],
            "damage": ["rows": [["row": 0, "ranges": [[2, 3]]]]],
          ]
        ],
        // Size-queried, never copied: the abandoned handshake.
        ["androidABI": ["action": "sizeQuery", "label": "q3"]],
        [
          "androidABI": [
            "action": "publish", "sequence": 4, "width": 3, "height": 1,
            "rows": [gridRow(0, [(0, "C", 1), (2, "Y", 1)])],
            "damage": ["rows": [["row": 0, "ranges": [[0, 1]]]]],
          ]
        ],
        ["androidABI": ["action": "sizeQuery", "label": "q4"]],
        // Undersized copy: the reported size comes back, no bytes go out.
        ["androidABI": ["action": "copy", "label": "q4", "capacity": 4]],
        ["androidABI": ["action": "copy", "label": "q4", "capacity": 4096]],
        [
          "expect": [
            "androidDeliveries": [
              try HostWireConformanceRecordDecoding.androidDelivery(
                label: "q4",
                reported: third.utf8.count,
                capacity: 4,
                returned: third.utf8.count,
                raw: nil
              ),
              try HostWireConformanceRecordDecoding.androidDelivery(
                label: "q4",
                reported: third.utf8.count,
                capacity: 4096,
                returned: third.utf8.count,
                raw: third
              ),
            ]
          ]
        ],
        [
          "androidABI": [
            "action": "publish", "sequence": 5, "width": 3, "height": 1,
            "rows": [gridRow(0, [(0, "C", 1), (2, "X", 1)])],
            "damage": ["rows": [["row": 0, "ranges": [[2, 3]]]]],
          ]
        ],
        ["androidABI": ["action": "sizeQuery", "label": "q5"]],
        ["androidABI": ["action": "copy", "label": "q5", "capacity": 4096]],
        [
          "expect": [
            "androidDeliveries": [
              try HostWireConformanceRecordDecoding.androidDelivery(
                label: "q5",
                reported: fourth.utf8.count,
                capacity: 4096,
                returned: fourth.utf8.count,
                raw: fourth
              )
            ]
          ]
        ],
      ]
    )
  }

  private static func websocketDetachedBacklogScenario() throws -> Scenario {
    var detachedState = HostWireEncodingState(deltaEnabled: true, epochID: 201)
    let suppressedFull = encode(
      surface: singleCellSurface("S"),
      sequence: 1,
      damage: nil,
      state: &detachedState
    )
    let suppressedDelta = encode(
      surface: singleCellSurface("T"),
      sequence: 2,
      damage: fullRowDamage(width: 1),
      state: &detachedState
    )
    var activeState = HostWireEncodingState(deltaEnabled: true, epochID: 202)
    let deliveredKeyframe = encode(
      surface: singleCellSurface("K"),
      sequence: 3,
      damage: nil,
      state: &activeState
    )
    let issue = WebSurfaceFrameEncoder.encodeRuntimeIssue(
      RuntimeIssue(
        severity: .warning,
        code: "conformance.detached",
        message: "buffered while detached"
      )
    )
    let partialOldCaps = Array("\u{001E}caps:{\"acceptsDelta".utf8)
    let remainingOldCaps = Array("Frames\":true}\n".utf8)
    let staleFullCaps = Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)
    let staleKey = Array("\u{001E}key:character:X:0\n".utf8)
    let currentKeyN = "\u{001E}key:character:N:0\n"
    let currentKeyM = "\u{001E}key:character:M:0\n"
    return Scenario(
      file: "conformance-websocket-detached-backlog.jsonl",
      scenario: "websocket-detached-backlog-reconnects-by-token",
      kind: .websocketChannel,
      mutationClass: .websocketDetachedBacklog,
      requiresStage: .s3b,
      runners: [.swiftWebSocketChannel],
      steps: [
        [
          "channel": [
            "action": "clientChunk", "token": 1,
            "bytesBase64": Data(partialOldCaps).base64EncodedString(),
          ]
        ],
        ["channel": ["action": "closeClient", "token": 1]],
        ["emit": issue],
        ["reconnect": ["capsAfter": 2]],
        [
          "channel": [
            "action": "clientChunk", "token": 1,
            "bytesBase64": Data(remainingOldCaps).base64EncodedString(),
          ]
        ],
        [
          "channel": [
            "action": "clientChunk", "token": 1,
            "bytesBase64": Data(staleFullCaps).base64EncodedString(),
          ]
        ],
        [
          "channel": [
            "action": "clientChunk", "token": 1,
            "bytesBase64": Data(staleKey).base64EncodedString(),
          ]
        ],
        ["channel": ["action": "closeClient", "token": 1]],
        ["emit": suppressedFull],
        ["emit": suppressedDelta],
        [
          "channel": [
            "action": "clientChunk", "token": 2,
            "bytesBase64": Data(currentKeyN.utf8).base64EncodedString(),
          ]
        ],
        [
          "channel": [
            "action": "clientChunk", "token": 2,
            "bytesBase64": Data(currentKeyM.utf8).base64EncodedString(),
          ]
        ],
        ["channel": ["action": "drainInput"]],
        ["emit": deliveredKeyframe],
        [
          "expect": [
            "deliveredRecords": [
              try HostWireConformanceRecordDecoding.channelRecord(raw: issue),
              try HostWireConformanceRecordDecoding.channelRecord(raw: deliveredKeyframe),
            ],
            "suppressedSurfaceRecords": [
              try HostWireConformanceRecordDecoding.channelRecord(raw: suppressedFull),
              try HostWireConformanceRecordDecoding.channelRecord(raw: suppressedDelta),
            ],
            "detachedNonSurfaceBacklog": ["count": 0, "bytes": 0],
            "refreshRequestCount": 1,
            "capsProcessedCount": 1,
            "ignoredStaleCallbackCount": 1,
            "acceptedClientInputs": [currentKeyN, currentKeyM],
            "discardedInboundChunks": [
              [
                "token": 1,
                "bytesBase64": Data(partialOldCaps).base64EncodedString(),
                "reason": "stale-at-consumption",
              ],
              [
                "token": 1,
                "bytesBase64": Data(remainingOldCaps).base64EncodedString(),
                "reason": "stale-at-ingress",
              ],
              [
                "token": 1,
                "bytesBase64": Data(staleFullCaps).base64EncodedString(),
                "reason": "stale-at-ingress",
              ],
              [
                "token": 1,
                "bytesBase64": Data(staleKey).base64EncodedString(),
                "reason": "stale-at-ingress",
              ],
            ],
            "parser": ["token": 2, "bufferedBytes": 0],
            "connection": [
              "currentToken": 2,
              "lastIssuedToken": 2,
              "phase": "active",
              "sceneInputFinished": false,
            ],
          ]
        ],
      ]
    )
  }

  private static func encode(
    surface: RasterSurface,
    sequence: UInt64,
    damage: PresentationDamage?,
    state: inout HostWireEncodingState,
    terminalStyle: TerminalRenderStyle? = nil
  ) -> String {
    WebSurfaceFrameEncoder.encode(
      HostWireFrameModel(
        surface: surface,
        sequence: sequence,
        semanticSnapshot: nil,
        focusedIdentity: nil,
        damage: damage,
        preferredLayoutSize: nil,
        terminalStyle: terminalStyle
      ),
      fallbackBackground: TerminalAppearance.fallback.backgroundColor,
      state: &state
    )
  }

  private static func singleCellSurface(
    _ character: Character
  ) -> RasterSurface {
    RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [[RasterCell(character: character)]]
    )
  }

  private static func styledSingleCellSurface(
    _ character: Character,
    color: Color
  ) -> RasterSurface {
    RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [
        [
          RasterCell(
            character: character,
            style: ResolvedTextStyle(foregroundColor: color)
          )
        ]
      ]
    )
  }

  private static func sparseWideSurface(
    leading: Character,
    wide: Character
  ) -> RasterSurface {
    RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [
        [
          .init(character: leading),
          .init(character: " ", spanWidth: 0, continuationLeadX: 0),
          .init(character: wide, spanWidth: 2),
          .init(character: " ", spanWidth: 0, continuationLeadX: 2),
        ]
      ]
    )
  }

  private static func imageSurface() -> RasterSurface {
    let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01]
    return RasterSurface(
      size: .init(width: 1, height: 1),
      cells: [[.empty]],
      imageAttachments: [
        RasterImageAttachment(
          identity: Identity(components: ["conformance", "image"]),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
          source: .data(bytes),
          resolvedReference: .embeddedImage(bytes),
          pixelSize: .init(width: 1, height: 1)
        )
      ]
    )
  }

  private static func fullRowDamage(
    width: Int
  ) -> PresentationDamage {
    PresentationDamage(
      textRows: [.init(row: 0, columnRanges: [0..<width])]
    )
  }

  private static func columnDamage(
    _ columnRanges: [Range<Int>]
  ) -> PresentationDamage {
    PresentationDamage(textRows: [.init(row: 0, columnRanges: columnRanges)])
  }

  /// Two single-cell glyphs with an untouched column between them, so damage
  /// over one column is observably distinct from damage over the other.
  private static func gappedSurface(
    _ leading: Character,
    _ trailing: Character
  ) -> RasterSurface {
    RasterSurface(
      size: .init(width: 3, height: 1),
      cells: [
        [
          .init(character: leading),
          .empty,
          .init(character: trailing),
        ]
      ]
    )
  }

  private static func imageID(
    in record: String
  ) throws -> String {
    let prefix = "\u{001E}surface:"
    let bytes = Array(record.utf8)
    let payload = Data(bytes[prefix.utf8.count..<(bytes.count - 1)])
    let json = try JSONSerialization.jsonObject(with: payload)
    guard let object = json as? [String: Any],
      let images = object["images"] as? [[String: Any]],
      let id = images.first?["id"] as? String
    else {
      throw HostWireConformanceError.invalid("recorder: production image ID was not emitted")
    }
    return id
  }

  private static func expectation(
    rows: [[String: Any]],
    imagesVisible: [String] = [],
    resyncRequests: [[String: Any]] = [],
    styleRuns: [[String: Any]]? = nil
  ) -> [String: Any] {
    var expectation: [String: Any] = [
      "rows": rows,
      "imagesVisible": imagesVisible.sorted(),
      "resyncRequests": resyncRequests,
    ]
    if let styleRuns {
      expectation["styleRuns"] = styleRuns
    }
    return expectation
  }

  private static func styleRun(
    row: Int,
    startColumn: Int,
    text: String,
    span: Int,
    resolvedStyle: [String: Any]
  ) -> [String: Any] {
    [
      "row": row,
      "startColumn": startColumn,
      "text": text,
      "span": span,
      "resolvedStyle": resolvedStyle,
    ]
  }

  private static func gridRow(
    _ row: Int,
    _ cells: [(Int, String, Int)]
  ) -> [String: Any] {
    [
      "row": row,
      "cells": cells.map {
        ["column": $0.0, "text": $0.1, "span": $0.2]
      },
    ]
  }

}
