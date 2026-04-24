import Testing

@testable import Layouts

/// Shortens parameterised-test failure output so a smoke-test
/// regression prints the entry ID instead of the full debug
/// description of every field.
extension LayoutEntry: CustomTestStringConvertible {
  public var testDescription: String { id }
}
