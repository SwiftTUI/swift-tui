#if os(Windows)
  import Foundation
  import Testing
  @testable import SwiftTUITerminalCLI

  @MainActor @Suite
  struct WindowsCompanionDiscoveryTests {
    @Test(
      "private Windows companion discovery finds only the requested live app and removes on shutdown"
    )
    func discoveryLifecycle() throws {
      let app = "DiscoveryTest-" + UUID().uuidString
      let url = "http://127.0.0.1:12345/?token=disposable-fixture&renderer=canvas"
      #expect(try WindowsCompanionRegistration.urls(app: app).isEmpty)
      let first = try WindowsCompanionRegistration(app: app, url: url)
      defer { first.remove() }
      #expect(try WindowsCompanionRegistration.urls(app: app) == [url])
      #expect(try WindowsCompanionRegistration.urls(app: app + "-other").isEmpty)
      first.remove()
      first.remove()
      #expect(try WindowsCompanionRegistration.urls(app: app).isEmpty)
    }

    @Test("discovery refuses a non-loopback or unauthenticated URL")
    func discoveryRequiresPrivateURL() {
      for url in ["https://example.com/?token=fixture", "http://127.0.0.1:12345/"] {
        #expect(throws: (any Error).self) {
          try WindowsCompanionRegistration(app: "InvalidDiscoveryTest", url: url)
        }
      }
    }
  }
#endif
