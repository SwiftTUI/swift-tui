import SwiftTUICore

package struct LinearAccessibilityRenderer: Equatable, Sendable {
  package init() {}

  package func render(_ snapshot: SemanticSnapshot) -> String {
    render(
      snapshot.accessibilityNodes,
      warnings: snapshot.accessibilityWarnings
    )
  }

  package func render(_ nodes: [AccessibilityNode]) -> String {
    render(nodes, warnings: [])
  }

  private func render(
    _ nodes: [AccessibilityNode],
    warnings: [AccessibilityWarning]
  ) -> String {
    guard !nodes.isEmpty || !warnings.isEmpty else {
      return ""
    }

    let nodesByIdentity = Dictionary(uniqueKeysWithValues: nodes.map { ($0.identity, $0) })
    var lines: [String] = []
    lines.reserveCapacity(nodes.count + warnings.count)

    for node in nodes {
      guard let line = line(for: node) else {
        continue
      }
      lines.append(String(repeating: " ", count: depth(for: node, in: nodesByIdentity) * 2) + line)
    }

    for warning in warnings {
      if let message = sanitized(warning.message) {
        lines.append("warning: \(message)")
      }
    }

    guard !lines.isEmpty else {
      return ""
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func line(
    for node: AccessibilityNode
  ) -> String? {
    let label = sanitized(node.label)
    let hint = sanitized(node.hint)

    if node.role == .group, label == nil, hint == nil {
      return nil
    }

    let role = sanitized(node.role.description) ?? "unknown"
    var line =
      if let label {
        "\(role): \(label)"
      } else {
        role
      }

    if let hint {
      line += " - \(hint)"
    }
    return line
  }

  private func depth(
    for node: AccessibilityNode,
    in nodesByIdentity: [Identity: AccessibilityNode]
  ) -> Int {
    var depth = 0
    var visited: Set<Identity> = [node.identity]
    var parentIdentity = node.parentIdentity

    while let currentParentIdentity = parentIdentity,
      let parent = nodesByIdentity[currentParentIdentity],
      !visited.contains(currentParentIdentity)
    {
      depth += 1
      visited.insert(currentParentIdentity)
      parentIdentity = parent.parentIdentity
    }

    return depth
  }

  private func sanitized(
    _ value: String?
  ) -> String? {
    guard let value else {
      return nil
    }

    var scalars: [Unicode.Scalar] = []
    scalars.reserveCapacity(value.unicodeScalars.count)
    var previousWasSpace = false

    func appendSpaceIfNeeded() {
      guard !previousWasSpace else {
        return
      }
      scalars.append(Unicode.Scalar(0x20)!)
      previousWasSpace = true
    }

    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x20:
        appendSpaceIfNeeded()
      case 0x21...0x7E:
        scalars.append(scalar)
        previousWasSpace = false
      case 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
        appendSpaceIfNeeded()
      default:
        scalars.append(Unicode.Scalar(0x3F)!)
        previousWasSpace = false
      }
    }

    let trimmed = trimmingAsciiSpaces(scalars)
    guard !trimmed.isEmpty else {
      return nil
    }
    return String(String.UnicodeScalarView(trimmed))
  }

  private func trimmingAsciiSpaces(
    _ scalars: [Unicode.Scalar]
  ) -> [Unicode.Scalar] {
    var start = scalars.startIndex
    var end = scalars.endIndex

    while start < end, scalars[start].value == 0x20 {
      start = scalars.index(after: start)
    }
    while start < end {
      let previous = scalars.index(before: end)
      guard scalars[previous].value == 0x20 else {
        break
      }
      end = previous
    }

    return Array(scalars[start..<end])
  }
}
