import SwiftTUICore

/// Host sessions register their actual output terminals with the portable
/// diagnostic router. Redirected stderr can stream while all owned terminals
/// remain protected. Unknown destinations conservatively defer.
enum TerminalScreenOwnership {
  static func acquire(_ descriptor: Int32 = -1) { DiagnosticScreenOwnership.acquire(descriptor) }
  static func release(_ descriptor: Int32 = -1) { DiagnosticScreenOwnership.release(descriptor) }
  static var isScreenOwned: Bool { DiagnosticScreenOwnership.isScreenOwned }
}
