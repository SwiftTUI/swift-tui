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
}
