import Testing

@testable import SwiftTUICLI

@Suite("PtyPair characterization")
struct PtyPairCharacterizationTests {
  @Test("init opens a usable master fd and slave path")
  func initOpensUsableFds() throws {
    let pair = try PtyPair()
    defer { pair.close() }
    #expect(pair.masterFD >= 0)
    #expect(!pair.slavePath.isEmpty)
    #expect(pair.slavePath.hasPrefix("/dev/"))
  }

  @Test("hasAttachedClient returns false when no client has opened the slave")
  func hasAttachedClientFalseInitially() throws {
    let pair = try PtyPair()
    defer { pair.close() }
    #expect(pair.hasAttachedClient() == false)
  }
}
