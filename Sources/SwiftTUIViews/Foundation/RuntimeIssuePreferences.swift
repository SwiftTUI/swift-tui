package import SwiftTUICore

/// Resolve-authored runtime issues collected at the committed root alongside
/// layout-authored issues.
package enum RuntimeIssuePreferenceKey: PreferenceKey {
  package static var defaultValue: [RuntimeIssue] { [] }

  package static func reduce(
    value: inout [RuntimeIssue],
    nextValue: () -> [RuntimeIssue]
  ) {
    for issue in nextValue() where !value.contains(issue) {
      value.append(issue)
    }
  }
}
