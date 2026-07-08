import Foundation
import Testing

@testable import SwiftTUIWebHost

struct WebHostBrowserBundleTests {
  @Test("browser bundle contains index and JavaScript assets")
  func browserBundleContainsIndexAndJavaScriptAssets() throws {
    let paths = try WebHostBrowserBundle.assetPaths()

    #expect(paths.contains("index.html"))
    #expect(paths.contains { $0.hasSuffix(".js") })
  }

  @Test("browser bundle resource lookup returns stable content types")
  func browserBundleResourceLookupReturnsStableContentTypes() throws {
    let index = try WebHostBrowserBundle.resource(for: "/")
    let scriptPath = try #require(
      try WebHostBrowserBundle.assetPaths().first { $0.hasSuffix(".js") })
    let script = try WebHostBrowserBundle.resource(for: "/\(scriptPath)")

    #expect(index.contentType.hasPrefix("text/html"))
    #expect(script.contentType.hasPrefix("application/javascript"))

    if let cssPath = try WebHostBrowserBundle.assetPaths().first(where: { $0.hasSuffix(".css") }) {
      let css = try WebHostBrowserBundle.resource(for: "/\(cssPath)")
      #expect(css.contentType.hasPrefix("text/css"))
    }
  }

  @Test("browser bundle index injects tokenized asset URLs")
  func browserBundleIndexInjectsTokenizedAssetURLs() throws {
    let html = String(
      decoding: try WebHostBrowserBundle.indexHTML(token: WebHostToken(rawValue: "test-token")),
      as: UTF8.self
    )

    #expect(html.contains("?token=test-token"))
  }

  @Test("browser bundle records the swift-tui-web revision it was built from")
  func browserBundleRecordsBuildProvenance() throws {
    // Scripts/update_webhost_bundle.sh writes this stamp; the coordination
    // root's webhost_bundle_provenance gate compares it against the pinned
    // swift-tui-web submodule to catch stale vendored bundles (F56).
    let provenance = try WebHostBrowserBundle.resource(for: "/bundle-provenance.json")
    let decoded = try JSONSerialization.jsonObject(with: provenance.data)
    let record = try #require(decoded as? [String: Any])

    let revision = try #require(record["webRevision"] as? String)
    #expect(revision.count == 40)
    #expect(revision.allSatisfy { $0.isHexDigit })
    let describe = try #require(record["webDescribe"] as? String)
    #expect(!describe.isEmpty)
    let builtAt = try #require(record["builtAt"] as? String)
    #expect(!builtAt.isEmpty)
  }
}
