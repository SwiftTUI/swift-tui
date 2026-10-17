import Foundation
import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// Set A's second pass probes host boundary hypotheses adjacent to the wire
/// budget, captured-geometry, directed-edit, and accessibility transport fixes.
@Suite(.serialized)
struct AdversarialSetAWireTests {
  @Test("A151 escaped capability keys survive nested future metadata")
  func setA151EscapedCapabilityKeysSurviveNestedMetadata() throws {
    let declaration =
      #"{"future":{"rows":[null,{"text":"\uD83D\uDE80","n":-1.25e+4}]},"acceptsDelta\u0046rames":true,"styleAppend":true}"#
    let caps = try #require(HostWireCapabilities.fromDeclarationJSON(declaration))
    let state = caps.negotiatedEncodingState(epochID: 151)
    #expect(state.deltaEnabled)
    #expect(state.styleAppendEnabled)
    #expect(!state.sharedViewportEnabled)
  }

  @Test("A152 image recovery requests enforce the published 1024-ID budget")
  func setA152ImageRecoveryIDCountIsBounded() throws {
    // HOST-WIRE-CONTRACT.md applies the image-placement budget to recovery
    // IDs too. A small record can exceed that table limit without exceeding
    // the independent four-MiB byte limit.
    func request(count: Int) -> String {
      let ids = (0..<count).map { "\"image-\($0)\"" }.joined(separator: ",")
      return #"{"scope":"images","ids":[\#(ids)]}"#
    }
    let admitted = try #require(
      HostWireResyncRequest.fromRequestJSON(request(count: HostWireBudget.images)))
    if case .images(let ids) = admitted.scope {
      #expect(ids.count == HostWireBudget.images)
    } else {
      Issue.record("Image repair request changed scope")
    }
    let rejectsOversizedTable =
      HostWireResyncRequest.fromRequestJSON(request(count: HostWireBudget.images + 1)) == nil
    do {
      #expect(rejectsOversizedTable)
    }
  }

  @Test("A153 image recovery IDs enforce their UTF-8 byte budget")
  func setA153ImageRecoveryIDLengthUsesUTF8Bytes() throws {
    // Recovery IDs have the same 1,024-byte limit as image placement IDs.
    // These two 512-Character strings sit on opposite sides of that limit.
    let admittedID = String(repeating: "é", count: 512)
    let oversizedID = String(repeating: "é", count: 511) + "🚀"
    #expect(admittedID.utf8.count == 1024)
    #expect(oversizedID.count == admittedID.count)
    #expect(oversizedID.utf8.count == 1026)
    let admitted = try #require(
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","ids":["\#(admittedID)"]}"#))
    #expect(admitted.scope == .images([admittedID]))
    let rejectsOversizedID =
      HostWireResyncRequest.fromRequestJSON(#"{"scope":"images","ids":["\#(oversizedID)"]}"#)
      == nil
    do {
      #expect(rejectsOversizedID)
    }
  }

  @Test("A154 action framing preserves escaped separators and maximum correlation ID")
  func setA154ActionSeparatorsRemainInsideDecodedFields() throws {
    let request = try #require(
      AccessibilityActionWire.parseCommand(
        "accessibility:18446744073709551615:scene%3Acontrol%25:editText:text:a%3Ab%25%F0%9F%9A%80:6:0"
      ))
    #expect(request.requestID == UInt64.max)
    #expect(request.target == "scene:control%")
    #expect(request.action == .editText(.init(text: "a:b%🚀", anchor: 6, head: 0)))
    #expect(request.hostSession == nil)
  }

  @Test("A155 malformed percent-encoded UTF-8 cannot become a partial assistive action")
  func setA155MalformedActionUTF8IsRejectedWhole() {
    for invalid in ["%C0%AF", "%ED%A0%80", "%F4%90%80%80", "%E2%82", "%FF", "%0G"] {
      #expect(
        AccessibilityActionWire.parseCommand("accessibility:target:setValue:text:\(invalid)")
          == nil)
      #expect(AccessibilityActionWire.parseCommand("accessibility:\(invalid):activate") == nil)
    }
    #expect(AccessibilityActionWire.parseCommand("accessibility:target:activate:extra") == nil)
  }

  @Test("A156 a fresh capability declaration cannot inherit the old delta baseline")
  func setA156RenegotiationStartsWithAKeyframe() throws {
    let caps = HostWireCapabilities(acceptsDeltaFrames: true, styleAppend: true)
    var state = caps.negotiatedEncodingState(epochID: 156)
    _ = try record(surface(), state: &state)
    let delta = try record(surface("b"), state: &state)
    #expect(delta["encoding"] as? String == "delta")
    state = caps.negotiatedEncodingState(epochID: 157)
    let restarted = try record(surface("c"), state: &state)
    #expect(restarted["rows"] != nil)
    #expect(restarted["deltaRows"] == nil)
    #expect(restarted["stylesBase"] == nil)
    #expect(restarted["epoch"] as? Int == 157)
    #expect(restarted["gen"] as? Int == 1)
  }

  @Test("A157 style append alone never negotiates delta record shapes")
  func setA157StyleAppendAloneKeepsFullRecords() throws {
    var state = HostWireCapabilities(styleAppend: true).negotiatedEncodingState(epochID: 157)
    for text in ["a", "b", "a"] {
      let object = try record(surface(text), state: &state)
      #expect(object["rows"] != nil)
      #expect(object["deltaRows"] == nil)
      #expect(object["stylesBase"] == nil)
      #expect(!(try #require(object["styles"] as? [Any])).isEmpty)
    }
  }

  @Test("A158 keyframe resync keeps the epoch and reanchors the next delta generation")
  func setA158KeyframeResyncReanchorsGeneration() throws {
    var state = deltaState(158)
    _ = try record(surface(), state: &state)
    _ = try record(surface("b"), state: &state)
    state.requestResync(.init(scope: .keyframe))
    let keyframe = try record(surface("c"), state: &state)
    #expect(keyframe["epoch"] as? Int == 158)
    #expect(keyframe["gen"] as? Int == 3)
    #expect(keyframe["baselineGen"] == nil)
    #expect(keyframe["rows"] != nil)
    let next = try record(surface("d"), state: &state)
    #expect(next["gen"] as? Int == 4)
    #expect(next["baselineGen"] as? Int == 3)
    #expect(next["encoding"] as? String == "delta")
  }

  @Test("A159 selective image resync resends only the requested live payload")
  func setA159SelectiveImageResyncPreservesOtherPayloads() throws {
    let raster = imageSurface()
    var state = deltaState(159)
    let initial = try record(raster, state: &state)
    let originalImages = try #require(initial["images"] as? [[String: Any]])
    #expect(originalImages.count == 2)
    let requested = try #require(originalImages.first?["id"] as? String)
    _ = try record(raster, state: &state)
    let request = try #require(
      HostWireResyncRequest.fromRequestJSON(
        #"{"scope":"images","ids":["\#(requested)","missing"]}"#))
    state.requestResync(request)
    let repaired = try record(raster, state: &state)
    #expect(repaired["encoding"] as? String == "delta")
    let images = try #require(repaired["images"] as? [[String: Any]])
    #expect(images.filter { $0["dataBase64"] != nil }.count == 1)
    #expect(images.first { $0["dataBase64"] != nil }?["id"] as? String == requested)
    #expect(state.knownImageIDs.count == 2)
  }

  @Test("A160 all-image resync repairs payloads without resetting row delivery")
  func setA160AllImageResyncPreservesDeltaBaseline() throws {
    let raster = imageSurface()
    var state = deltaState(160)
    _ = try record(raster, state: &state)
    let cached = try record(raster, state: &state)
    #expect((cached["images"] as? [[String: Any]])?.allSatisfy { $0["dataBase64"] == nil } == true)
    state.requestResync(.init(scope: .images([])))
    let repaired = try record(raster, state: &state)
    #expect(repaired["encoding"] as? String == "delta")
    #expect(repaired["baselineGen"] as? Int == 2)
    #expect((repaired["images"] as? [[String: Any]])?.filter { $0["dataBase64"] != nil }.count == 2)
  }

  @Test("A161 a semantic-only delta replaces an opaque action target")
  func setA161SemanticOnlyDeltaRetargetsControl() throws {
    var state = deltaState(161)
    var node = controlNode(target: "old-token")
    _ = try record(surface(), nodes: [node], state: &state)
    node.actionTarget = "new-token"
    let updated = try record(surface(), nodes: [node], damage: .init(), state: &state)
    #expect((updated["deltaRows"] as? [Any])?.isEmpty == true)
    #expect(try firstNode(updated)["actionTarget"] as? String == "new-token")
    #expect(try firstNode(updated)["id"] as? String == node.identity.path)
  }

  @Test("A162 removing a control and acknowledgment leaves neither in the next delta")
  func setA162SemanticRemovalDoesNotReplayOldActions() throws {
    var state = deltaState(162)
    var semantics = SemanticSnapshot(accessibilityNodes: [controlNode(target: "retired")])
    semantics.accessibilityActionResponse = .init(
      requestID: 17, target: "retired", result: .accepted)
    _ = try record(surface(), semantics: semantics, state: &state)
    let empty = try record(surface(), damage: .init(), state: &state)
    #expect(empty["encoding"] as? String == "delta")
    #expect(empty["accessibilityTree"] == nil)
    #expect(empty["accessibilityActionResponse"] == nil)
  }

  @Test("A163 hyperlink-only changes travel with an otherwise empty delta")
  func setA163HyperlinkOnlyMutationUpdatesTargets() throws {
    var state = deltaState(163)
    func linked(_ destination: String?) -> RasterSurface {
      .init(
        size: .init(width: 1, height: 1), cells: [[.init(character: "a", hyperlink: destination)]])
    }
    _ = try record(linked("https://old.example/"), state: &state)
    let changed = try record(linked("https://new.example/"), damage: .init(), state: &state)
    #expect(changed["linkTargets"] as? [String] == ["https://new.example/"])
    #expect((changed["deltaRows"] as? [Any])?.isEmpty == true)
    let removed = try record(linked(nil), damage: .init(), state: &state)
    #expect(removed["links"] == nil)
    #expect(removed["linkTargets"] == nil)
  }

  @Test("A164 an escaped semantic budget failure cannot poison delivery state")
  func setA164RejectedSemanticPayloadKeepsGenerationAndImages() throws {
    var state = deltaState(164)
    _ = try record(imageSurface(), state: &state)
    let knownImages = state.knownImageIDs
    let generation = state.recordsEncoded
    var node = controlNode(target: "valid")
    node.label = String(repeating: "\u{0}", count: HostWireBudget.recordBytes / 6 + 1)
    let rejected = WebSurfaceFrameEncoder.encode(
      surface(), sequence: 2, semanticSnapshot: .init(accessibilityNodes: [node]),
      focusedIdentity: nil, damage: .init(), state: &state)
    #expect(rejected == HostWireBudget.rejectionRecord)
    #expect(state.recordsEncoded == generation)
    #expect(state.knownImageIDs == knownImages)
    let recovered = try record(surface("r"), state: &state)
    #expect(recovered["rows"] != nil)
    #expect(recovered["gen"] as? UInt64 == generation + 1)
  }

  @Test("A165 shrinking and regrowing the grid cannot reuse an obsolete baseline")
  func setA165GridABARequiresNewKeyframes() throws {
    var state = deltaState(165)
    for (index, text) in ["abc", "a", "abc"].enumerated() {
      let object = try record(surface(text), state: &state)
      #expect(object["rows"] != nil)
      #expect(object["deltaRows"] == nil)
      #expect(object["width"] as? Int == text.count)
      #expect(object["gen"] as? Int == index + 1)
    }
    #expect(try record(surface("xyz"), state: &state)["encoding"] as? String == "delta")
  }

  @Test("A166 stale and duplicate damage rows cannot select outside the current grid")
  func setA166StaleDamageIsClippedBeforeDeltaTraversal() throws {
    let raster = RasterSurface(size: .init(width: 3, height: 2), lines: ["abc", "xyz"])
    var state = deltaState(166)
    _ = try record(raster, state: &state)
    let damage = PresentationDamage(textRows: [
      .init(row: Int.max), .init(row: -1), .init(row: 1, columnRanges: [-5..<99]),
      .init(row: 1, columnRanges: [1..<2]),
    ])
    let changed = try record(raster, damage: damage, state: &state)
    let rows = try #require(changed["deltaRows"] as? [[Any]])
    #expect(rows.count == 1)
    #expect(rows.first?.first as? Int == 1)
    let encodedDamage = try #require(changed["damage"] as? [String: Any])
    let textRows = try #require(encodedDamage["textRows"] as? [[Any]])
    #expect(textRows.first?[1] as? [[Int]] == [[0, 3]])
  }

  @Test("A167 secure controls redact UTF-16 selection and values in full and delta frames")
  func setA167SecureControlRedactsBothFrameShapes() throws {
    var state = deltaState(167)
    var node = controlNode(target: "secret-target", role: .secureField)
    node.control = .init(actions: [.focus, .editText], value: .text("secr🚀et"))
    node.textInput = .init(selection: 1..<7, insertionOffset: 1, clusters: [], endAnchor: .zero)
    for _ in 0..<2 {
      let encoded = try record(surface(), nodes: [node], state: &state)
      let entry = try firstNode(encoded)
      #expect(entry["value"] == nil)
      #expect(entry["textSelection"] == nil)
      #expect(entry["actionTarget"] as? String == "secret-target")
      #expect(entry["actions"] as? [String] == ["focus", "editText"])
    }
  }

  @Test("A168 reversed selections retain UTF-16 direction across a delta")
  func setA168ReversedUTF16SelectionRemainsDirected() throws {
    var state = deltaState(168)
    var node = controlNode(target: "editor", role: .textField)
    node.control = .init(actions: [.editText, .selectText], value: .text("a🚀bc"))
    node.textInput = .init(selection: 1..<5, insertionOffset: 5, clusters: [], endAnchor: .zero)
    let forward = try record(surface(), nodes: [node], state: &state)
    #expect(try firstNode(forward)["textSelection"] as? [Int] == [1, 5])
    node.textInput = .init(selection: 1..<5, insertionOffset: 1, clusters: [], endAnchor: .zero)
    let reverse = try record(surface(), nodes: [node], damage: .init(), state: &state)
    #expect(try firstNode(reverse)["textSelection"] as? [Int] == [5, 1])
  }

  @Test("A169 control focus follows its action identity without changing its semantic ID")
  func setA169ActionIdentityFocusDoesNotRenameNode() throws {
    var state = deltaState(169)
    var node = controlNode(target: "opaque")
    let actionIdentity = Identity(components: ["nested-action"])
    node.actionIdentity = actionIdentity
    let focused = try record(
      surface(), nodes: [node], focusedIdentity: actionIdentity, state: &state)
    let entry = try firstNode(focused)
    #expect(entry["isFocused"] as? Bool == true)
    #expect(entry["id"] as? String == node.identity.path)
    let unfocused = try record(
      surface(), nodes: [node], focusedIdentity: node.identity, state: &state)
    #expect(try firstNode(unfocused)["isFocused"] as? Bool == false)
  }

  @Test("A170 an unbound control cannot publish callable actions or value data")
  func setA170MissingTargetKeepsControlInert() throws {
    var state = deltaState(170)
    var node = controlNode(target: "live")
    node.control = .init(actions: [.activate, .setValue], value: .text("private"))
    _ = try record(surface(), nodes: [node], state: &state)
    node.actionTarget = nil
    node.isEnabled = false
    let entry = try firstNode(record(surface(), nodes: [node], state: &state))
    #expect(entry["actionTarget"] == nil)
    #expect(entry["actions"] == nil)
    #expect(entry["value"] == nil)
    #expect(entry["isEnabled"] as? Bool == false)
  }

  @Test("A171 nonfinite control numbers cannot corrupt JSON or finite neighboring bounds")
  func setA171NonfiniteControlNumbersKeepJSONValid() throws {
    for value in [Double.nan, Double.infinity, -Double.infinity] {
      var state = deltaState(171)
      var node = controlNode(target: "number", role: .slider)
      node.control = .init(
        actions: [.setValue], value: .number(value), minimum: -.infinity,
        maximum: 100, step: .nan)
      let entry = try firstNode(record(surface(), nodes: [node], state: &state))
      let encodedValue = try #require(entry["value"] as? [String: Any])
      #expect(encodedValue["type"] as? String == "number")
      #expect(encodedValue["value"] is NSNull)
      #expect(entry["valueMin"] == nil)
      #expect(entry["valueStep"] == nil)
      #expect(entry["valueMax"] as? Int == 100)
    }
  }

  @Test("A172 escaped semantics and maximum request IDs round trip without record injection")
  func setA172EscapedSemanticsPreserveRecordFraming() throws {
    let text = "quote\"\\\n\r\t\u{0}\u{1E}surface:{🚀}"
    var node = controlNode(target: text, role: .textField)
    node.label = text
    node.control = .init(actions: [.setValue], value: .text(text), customActions: [text])
    var semantics = SemanticSnapshot(accessibilityNodes: [node])
    semantics.accessibilityActionResponse = .init(requestID: .max, target: text, result: .accepted)
    semantics.accessibilityFocusRequest = .init(generation: .max, target: text)
    var state = deltaState(172)
    let encoded = WebSurfaceFrameEncoder.encode(
      surface(), sequence: 1, semanticSnapshot: semantics,
      focusedIdentity: nil, damage: nil, state: &state)
    #expect(encoded.filter { $0 == "\u{1E}" }.count == 1)
    #expect(encoded.filter { $0 == "\n" }.count == 1)
    let object = try object(encoded)
    let entry = try firstNode(object)
    #expect(entry["label"] as? String == text)
    #expect(entry["actionTarget"] as? String == text)
    #expect((entry["value"] as? [String: Any])?["value"] as? String == text)
    let response = try #require(object["accessibilityActionResponse"] as? [String: Any])
    #expect(response["requestID"] as? String == String(UInt64.max))
    #expect(response["target"] as? String == text)
    let focus = try #require(object["accessibilityFocusRequest"] as? [String: Any])
    #expect(focus["generation"] as? String == String(UInt64.max))
  }

  @Test("A173 paragraphs crossing viewport edges publish only their visible rectangles")
  func setA173ParagraphClippingPreservesIdentity() throws {
    var semantics = SemanticSnapshot()
    semantics.paragraphs = [
      paragraph("left", x: -3, y: 0, width: 5, height: 1),
      paragraph("right", x: 3, y: 1, width: 5, height: 1),
      paragraph("bottom", x: 0, y: 2, width: 2, height: 4),
    ]
    var state = deltaState(173)
    let raster = RasterSurface(size: .init(width: 4, height: 3), lines: ["abcd", "efgh", "ijkl"])
    let object = try record(raster, semantics: semantics, state: &state)
    let paragraphs = try #require(object["paragraphs"] as? [[String: Any]])
    #expect(paragraphs.compactMap { $0["id"] as? String } == ["left", "right", "bottom"])
    #expect(
      paragraphs.compactMap { $0["rect"] as? [Int] } == [
        [0, 0, 2, 1], [3, 1, 1, 1], [0, 2, 2, 1],
      ])
  }

  @Test("A174 an offscreen duplicate paragraph cannot suppress its visible instance")
  func setA174OffscreenParagraphDuplicateIsHarmless() throws {
    var semantics = SemanticSnapshot()
    semantics.paragraphs = [
      paragraph("same", x: 5, y: 0, width: 2, height: 1),
      paragraph("same", x: 0, y: 0, width: 2, height: 1),
    ]
    var state = deltaState(174)
    let object = try record(surface("abc"), semantics: semantics, state: &state)
    let paragraphs = try #require(object["paragraphs"] as? [[String: Any]])
    #expect(paragraphs.count == 1)
    #expect(paragraphs.first?["id"] as? String == "same")
    #expect(paragraphs.first?["rect"] as? [Int] == [0, 0, 2, 1])
  }

  @Test("A175 ambiguous paragraph overlap drops metadata while preserving raster rows")
  func setA175OverlappingParagraphsCannotClaimEachOthersText() throws {
    var semantics = SemanticSnapshot()
    semantics.paragraphs = [
      paragraph("first", x: 0, y: 0, width: 2, height: 1),
      paragraph("second", x: 1, y: 0, width: 2, height: 1),
    ]
    var state = deltaState(175)
    let object = try record(surface("abc"), semantics: semantics, state: &state)
    #expect(object["paragraphs"] == nil)
    let rows = try #require(object["rows"] as? [[[Any]]])
    #expect(rows.first?.compactMap { $0[1] as? String } == ["a", "b", "c"])
  }

  private func deltaState(_ epoch: UInt32) -> HostWireEncodingState {
    HostWireCapabilities(acceptsDeltaFrames: true, styleAppend: true)
      .negotiatedEncodingState(epochID: epoch)
  }

  private func surface(_ text: String = "a") -> RasterSurface {
    RasterSurface(size: .init(width: text.count, height: 1), lines: [text])
  }

  private func record(
    _ raster: RasterSurface,
    nodes: [AccessibilityNode] = [],
    semantics: SemanticSnapshot? = nil,
    focusedIdentity: Identity? = nil,
    damage: PresentationDamage = .init(textRows: [.init(row: 0)]),
    state: inout HostWireEncodingState
  ) throws -> [String: Any] {
    try object(
      WebSurfaceFrameEncoder.encode(
        raster, sequence: state.recordsEncoded + 1,
        semanticSnapshot: semantics ?? .init(accessibilityNodes: nodes),
        focusedIdentity: focusedIdentity, damage: damage, state: &state))
  }

  private func object(_ encoded: String) throws -> [String: Any] {
    let prefix = "\u{1E}surface:"
    try #require(encoded.hasPrefix(prefix))
    return try #require(
      JSONSerialization.jsonObject(with: Data(encoded.dropFirst(prefix.count).utf8))
        as? [String: Any])
  }

  private func firstNode(_ object: [String: Any]) throws -> [String: Any] {
    try #require((object["accessibilityTree"] as? [[String: Any]])?.first)
  }

  private func controlNode(
    target: String, role: AccessibilityRole = .button
  ) -> AccessibilityNode {
    var node = AccessibilityNode(
      identity: Identity(components: ["semantic-node"]),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)), role: role)
    node.actionTarget = target
    node.control = .init(actions: [.focus, .activate])
    return node
  }

  private func paragraph(
    _ name: String, x: Int, y: Int, width: Int, height: Int
  ) -> ParagraphRegion {
    .init(
      identity: Identity(components: [name]),
      rect: .init(origin: .init(x: x, y: y), size: .init(width: width, height: height)))
  }

  private func imageSurface() -> RasterSurface {
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let images = [UInt8(21), 22].map { byte in
      let bytes: [UInt8] = [0x89, 0x50, byte]
      return RasterImageAttachment(
        identity: Identity(components: ["image-\(byte)"]), bounds: bounds,
        visibleBounds: bounds, source: .data(bytes), resolvedReference: .embeddedImage(bytes),
        pixelSize: .init(width: 1, height: 1), isResizable: false)
    }
    return RasterSurface(
      size: .init(width: 1, height: 1), lines: ["a"], imageAttachments: images)
  }
}
