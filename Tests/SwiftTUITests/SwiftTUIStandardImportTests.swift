import SwiftTUI
import Testing

@Suite("SwiftTUI Standard import surface")
struct SwiftTUIStandardImportTests {
  @Test("unqualified Standard and FileOpenError remain available")
  func standardAndFileOpenErrorRemainAvailable() {
    _ = Standard.Error()

    do {
      throw FileOpenError.failed(path: "/not-opened", errno: 2)
    } catch is FileOpenError {
      // Compilation is the contract: SwiftTUI re-exports the one surviving
      // declaration from SwiftTUIViews.
    } catch {
      Issue.record("expected FileOpenError, got \(error)")
    }
  }
}
