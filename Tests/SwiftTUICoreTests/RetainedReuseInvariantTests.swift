import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore

@Suite("Retained reuse invariants")
struct RetainedReuseInvariantTests {
  @Test("PlacedNodeResolvedMetadata round-trips every resolved projection")
  func placedNodeResolvedMetadataRoundTripsEveryProjection() {
    var placed = PlacedNode(
      identity: testIdentity("Projection"),
      resolvedMetadata: makeMetadata("first", semanticRole: .control, isTransient: true),
      bounds: rect(x: 1, y: 2, width: 3, height: 4)
    )
    let replacement = makeMetadata("second", semanticRole: .scroll, isTransient: false)

    #expect(
      placed.resolvedMetadata == makeMetadata("first", semanticRole: .control, isTransient: true)
    )

    placed.resolvedMetadata = replacement

    #expect(placed.resolvedMetadata == replacement)
  }

  @Test("retained placement refreshes resolved metadata while preserving geometry")
  func retainedPlacementRefreshesResolvedMetadataWhilePreservingGeometry() {
    let engine = LayoutEngine()
    let parentIdentity = testIdentity("Retained", "Parent")
    let childIdentity = testIdentity("Retained", "Child")
    let oldChild = PlacedNode(
      identity: childIdentity,
      resolvedMetadata: makeMetadata("old-child", semanticRole: .generic, isTransient: false),
      bounds: rect(x: 4, y: 5, width: 6, height: 7),
      contentBounds: rect(x: 4, y: 5, width: 5, height: 6),
      clipBounds: rect(x: 4, y: 5, width: 4, height: 5),
      zIndex: 3
    )
    let oldParent = PlacedNode(
      identity: parentIdentity,
      resolvedMetadata: makeMetadata("old-parent", semanticRole: .generic, isTransient: false),
      bounds: rect(x: 1, y: 2, width: 12, height: 14),
      contentBounds: rect(x: 2, y: 3, width: 10, height: 12),
      clipBounds: rect(x: 2, y: 3, width: 9, height: 11),
      zIndex: 8,
      children: [oldChild]
    )
    let currentChild = makeResolvedNode(
      identity: childIdentity,
      metadata: makeMetadata("new-child", semanticRole: .control, isTransient: true)
    )
    let currentParent = makeResolvedNode(
      identity: parentIdentity,
      metadata: makeMetadata("new-parent", semanticRole: .control, isTransient: true),
      children: [currentChild]
    )

    let refreshed = engine.synchronizeRetainedPhaseMetadata(
      placed: oldParent,
      from: currentParent
    )

    #expect(refreshed.bounds == oldParent.bounds)
    #expect(refreshed.contentBounds == oldParent.contentBounds)
    #expect(refreshed.clipBounds == oldParent.clipBounds)
    #expect(refreshed.zIndex == oldParent.zIndex)
    #expect(refreshed.children.map(\.bounds) == oldParent.children.map(\.bounds))
    #expect(refreshed.children.map(\.contentBounds) == oldParent.children.map(\.contentBounds))
    #expect(refreshed.children.map(\.clipBounds) == oldParent.children.map(\.clipBounds))
    #expect(refreshed.children.map(\.zIndex) == oldParent.children.map(\.zIndex))
    #expect(refreshed.resolvedMetadata == projectedMetadata(from: currentParent, using: engine))
    #expect(
      refreshed.children.first?.resolvedMetadata
        == projectedMetadata(from: currentChild, using: engine)
    )
  }

  @Test("PlacedNodeResolvedMetadata field manifest stays synchronized")
  func placedNodeResolvedMetadataFieldManifestStaysSynchronized() throws {
    let fields = try parsedPackageVars(
      inStruct: "PlacedNodeResolvedMetadata",
      sourcePath: "Sources/SwiftTUICore/Place/PlacedNode.swift"
    )

    #expect(
      fields == [
        "kind",
        "environmentSnapshot",
        "semanticRole",
        "layoutMetadata",
        "drawMetadata",
        "semanticMetadata",
        "lifecycleMetadata",
        "drawPayload",
        "layoutBehavior",
        "isTransient",
        "matchedGeometry",
      ])
  }
}

private func makeMetadata(
  _ token: String,
  semanticRole: SemanticRole,
  isTransient: Bool
) -> PlacedNodeResolvedMetadata {
  PlacedNodeResolvedMetadata(
    kind: .view("Projection-\(token)"),
    environmentSnapshot: .init(
      debugSignature: "env-\(token)",
      values: ["token": token]
    ),
    semanticRole: semanticRole,
    layoutMetadata: .init(
      layoutPriority: token == "second" ? 2 : 1,
      fixedSizeHorizontal: true,
      fixedSizeVertical: token != "second",
      minimumWidth: token.count + 1,
      minimumHeight: token.count + 2,
      lineLimit: token.count + 3,
      textTruncationMode: .tail,
      textWrappingStrategy: .wordBoundary,
      alignmentKeys: ["alignment-\(token)"],
      layoutValues: ["layout": token]
    ),
    drawMetadata: DrawMetadata(
      emphasis: [.bold],
      opacity: token == "second" ? 0.75 : 0.5,
      clipsToBounds: true,
      clipIdentifier: "clip-\(token)",
      compositingHint: "composite-\(token)",
      imagePreference: "image-\(token)"
    ),
    semanticMetadata: .init(
      isFocusable: true,
      participatesInPointerHitTesting: true,
      accessibilityRole: .button,
      accessibilityLabel: "Label \(token)",
      accessibilityHint: "Hint \(token)"
    ),
    lifecycleMetadata: .init(
      appearHandlerIDs: ["appear-\(token)"],
      disappearHandlerIDs: ["disappear-\(token)"]
    ),
    drawPayload: .text("payload-\(token)"),
    layoutBehavior: .offset(x: token.count, y: token.count + 1),
    isTransient: isTransient,
    matchedGeometry: .init(
      key: .init(id: "matched-\(token)"),
      isSource: token != "second"
    )
  )
}

private func makeResolvedNode(
  identity: Identity,
  metadata: PlacedNodeResolvedMetadata,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  var resolved = ResolvedNode(
    identity: identity,
    kind: metadata.kind,
    children: children,
    environmentSnapshot: metadata.environmentSnapshot,
    layoutBehavior: metadata.layoutBehavior,
    layoutMetadata: metadata.layoutMetadata,
    drawMetadata: metadata.drawMetadata,
    semanticMetadata: metadata.semanticMetadata,
    lifecycleMetadata: metadata.lifecycleMetadata,
    drawPayload: metadata.drawPayload
  )
  resolved.isTransient = metadata.isTransient
  resolved.matchedGeometry = metadata.matchedGeometry
  return resolved
}

private func projectedMetadata(
  from resolved: ResolvedNode,
  using engine: LayoutEngine
) -> PlacedNodeResolvedMetadata {
  PlacedNodeResolvedMetadata(
    resolved: resolved,
    semanticRole: engine.semanticRole(for: resolved)
  )
}

private func parsedPackageVars(
  inStruct structName: String,
  sourcePath: String
) throws -> [String] {
  let source = try sourceText(relativePath: sourcePath)
  let body = try topLevelBody(named: structName, in: source)
  return
    body
    .components(separatedBy: .newlines)
    .compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("package var ") else { return nil }
      let remainder = trimmed.dropFirst("package var ".count)
      return String(remainder.prefix { $0 != ":" && !$0.isWhitespace })
    }
}

private func sourceText(relativePath: String) throws -> String {
  let root = try repositoryRoot()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}

private func topLevelBody(
  named structName: String,
  in source: String
) throws -> String {
  guard let declaration = source.range(of: "struct \(structName)") else {
    throw TestSourceParseError.missingStruct(structName)
  }
  guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
    throw TestSourceParseError.missingOpeningBrace(structName)
  }

  var depth = 0
  var index = openingBrace
  while index < source.endIndex {
    let character = source[index]
    if character == "{" {
      depth += 1
    } else if character == "}" {
      depth -= 1
      if depth == 0 {
        let bodyStart = source.index(after: openingBrace)
        return String(source[bodyStart..<index])
      }
    }
    index = source.index(after: index)
  }
  throw TestSourceParseError.missingClosingBrace(structName)
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path)
    {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw TestSourceParseError.missingPackageRoot
}

private func rect(
  x: Int,
  y: Int,
  width: Int,
  height: Int
) -> CellRect {
  CellRect(
    origin: CellPoint(x: x, y: y),
    size: CellSize(width: width, height: height)
  )
}

private enum TestSourceParseError: Error {
  case missingPackageRoot
  case missingStruct(String)
  case missingOpeningBrace(String)
  case missingClosingBrace(String)
}
