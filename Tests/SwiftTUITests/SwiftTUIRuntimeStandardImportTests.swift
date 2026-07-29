import SwiftTUIRuntime
import Testing

@Suite("SwiftTUIRuntime Standard import surface")
struct SwiftTUIRuntimeStandardImportTests {
  @Test("unqualified Standard and FileOpenError remain available")
  func standardAndFileOpenErrorRemainAvailable() {
    _ = Standard.Error()

    do {
      throw FileOpenError.failed(path: "/not-opened", errno: 2)
    } catch is FileOpenError {
      // Compilation is the contract: SwiftTUIRuntime re-exports the one
      // surviving declaration from SwiftTUIViews.
    } catch {
      Issue.record("expected FileOpenError, got \(error)")
    }
  }
}
