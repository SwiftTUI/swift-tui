import Foundation
import Testing

@testable import SwiftTUIRuntime

// Negotiation totality guard — enforced by source scrape (pattern:
// `HandlerDescriptorIntakeTotalityTests`, `ViewGraphCheckpointTotalityTests`).
//
// `HostWireCapabilities.negotiatedEncodingState()` exists so that a transport
// cannot decide for itself what record shapes a host accepts. Before it, the
// gating predicate was written out at each transport — and the third one
// skipped it, taking its delta switch from a separately resolved source. That
// transport then emitted delta records to a host whose declaration had not
// asked for them, with every test in every repo green: no behavioural test in
// transports A and B can observe transport C bypassing the door.
//
// The failure mode is structural, so the guard is too:
//
// 1. No production file outside `HostWireCapabilities.swift` may construct a
//    `HostWireEncodingState` directly. Constructing one is what re-anchors the
//    delta baseline and the transmitted-image set, so it is the epoch, and the
//    epoch belongs to the declaration.
// 2. No production file may reintroduce a version-ceiling comparison. The
//    retired `maxWebSurfaceVersion` was an integer only ever compared against
//    one threshold; the decoder-side skew guard is the real protection, and a
//    second, weaker copy of it in encoder code is what made a contradictory
//    declaration expressible.

@Suite
struct HostWireNegotiationTotalityTests {
  /// The one file allowed to build an encoding state: it owns the derivation
  /// and documents the epoch rule.
  private static let encodingStateConstructionExemptions: Set<String> = [
    "Sources/SwiftTUIRuntime/Terminal/HostWireCapabilities.swift"
  ]

  @Test("only the capability type constructs an encoding state in production")
  func encodingStateConstructionIsConfinedToTheNegotiatedDoor() throws {
    // Both spellings: the WASI bridge reaches the same type through the
    // `WebSurfaceFrameEncodingState` typealias, so matching only the
    // canonical name would leave the transport that had the defect uncovered.
    let construction = try Regex(#"(?:HostWire|WebSurfaceFrame)EncodingState\("#)
    let violations = try productionSourceFiles().filter { file in
      !Self.encodingStateConstructionExemptions.contains(file.relativePath)
        && file.contents.contains(construction)
    }
    #expect(
      violations.isEmpty,
      """
      Transports must obtain an encoding state from \
      HostWireCapabilities.negotiatedEncodingState(); found direct \
      construction in: \(violations.map(\.relativePath).sorted())
      """
    )
  }

  @Test("no production file reintroduces a wire version ceiling")
  func noProductionFileComparesAWireVersionCeiling() throws {
    let ceiling = try Regex(#"maxWebSurfaceVersion\s*[<>=]"#)
    let violations = try productionSourceFiles().filter { file in
      file.contents.contains(ceiling)
    }
    #expect(
      violations.isEmpty,
      """
      Capabilities are named feature bits, not a version ceiling — the \
      decoder-side skew guard is the protection. Found a ceiling comparison \
      in: \(violations.map(\.relativePath).sorted())
      """
    )
  }

  @Test("the scrape actually reaches the transports it is meant to guard")
  func scrapeReachesEveryTransport() throws {
    // The guard's own teeth: a scrape that silently matched nothing would
    // pass both tests above forever. Pin that the three transport files are
    // in the scraped set.
    let scraped = Set(try productionSourceFiles().map(\.relativePath))
    let transports = [
      "Platforms/WASI/Sources/WASISurfaceBridge/WebSurfaceTransport.swift",
      "Platforms/WebHost/Sources/SwiftTUIWebHost/WebSocketSurfaceTransport.swift",
      "Platforms/Android/Sources/SwiftTUIAndroidHost/AndroidHostSceneHost.swift",
    ]
    for transport in transports {
      #expect(
        scraped.contains(transport),
        "negotiation scrape missed \(transport) — did the file move?"
      )
    }
  }
}

private struct ProductionSourceFile {
  let relativePath: String
  let contents: String
}

/// Every checked-in production Swift file: library sources plus the platform
/// transports, excluding test targets.
private func productionSourceFiles() throws -> [ProductionSourceFile] {
  let root = try repositoryRoot()
  var files: [ProductionSourceFile] = []
  for treeName in ["Sources", "Platforms"] {
    let tree = root.appendingPathComponent(treeName)
    guard
      let enumerator = FileManager.default.enumerator(
        at: tree,
        includingPropertiesForKeys: nil
      )
    else {
      throw NegotiationScrapeError.missingSources(treeName)
    }
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
      guard !relative.contains("/Tests/") else {
        continue
      }
      files.append(
        ProductionSourceFile(
          relativePath: relative,
          contents: try String(contentsOf: url, encoding: .utf8)
        )
      )
    }
  }
  guard !files.isEmpty else {
    throw NegotiationScrapeError.missingSources("Sources+Platforms")
  }
  return files
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw NegotiationScrapeError.missingPackageRoot
}

private enum NegotiationScrapeError: Error {
  case missingPackageRoot
  case missingSources(String)
}
