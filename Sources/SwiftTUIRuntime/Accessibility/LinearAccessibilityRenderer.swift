import SwiftTUICore

package struct LinearAccessibilityRenderer: Equatable, Sendable {
  private let textSanitizer = AccessibilityTextSanitizer()

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

    let nodesByIdentity = Dictionary(
      nodes.map { ($0.identity, $0) },
      uniquingKeysWith: { _, last in last }
    )
    var lines: [String] = []
    lines.reserveCapacity(nodes.count + warnings.count)

    for node in nodes {
      guard let line = line(for: node) else {
        continue
      }
      lines.append(String(repeating: " ", count: depth(for: node, in: nodesByIdentity) * 2) + line)
    }

    for warning in warnings {
      if let message = textSanitizer.sanitized(warning.message) {
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
    let label = textSanitizer.sanitized(node.label)
    let hint = textSanitizer.sanitized(node.hint)

    if node.role == .group, label == nil, hint == nil {
      return nil
    }

    let role = textSanitizer.sanitized(node.role.description) ?? "unknown"
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
}

package struct JSONFrameRenderer: Equatable, Sendable {
  package init() {}

  package func render(
    surface: RasterSurface,
    semanticSnapshot: SemanticSnapshot,
    focusedIdentity: Identity?
  ) -> String {
    object([
      ("type", string("frame")),
      ("size", size(surface.size)),
      ("rows", array(surface.lines.map(string))),
      (
        "accessibilityNodes",
        array(
          semanticSnapshot.accessibilityNodes.map {
            node($0, focusedIdentity: focusedIdentity)
          })
      ),
      (
        "accessibilityAnnouncements",
        array(semanticSnapshot.accessibilityAnnouncements.map(announcement))
      ),
      ("accessibilityWarnings", array(semanticSnapshot.accessibilityWarnings.map(warning))),
    ]) + "\n"
  }

  private func node(
    _ node: AccessibilityNode,
    focusedIdentity: Identity?
  ) -> String {
    object([
      ("id", string(node.identity.path)),
      ("parentId", optionalString(node.parentIdentity?.path)),
      ("role", string(node.role.description)),
      ("label", optionalString(node.label)),
      ("hint", optionalString(node.hint)),
      ("rect", rect(node.rect)),
      ("hidden", bool(node.hidden)),
      ("focused", bool(node.identity == focusedIdentity)),
      ("liveRegion", optionalString(node.liveRegion?.description)),
      ("cursorAnchor", optionalPoint(node.cursorAnchor)),
    ])
  }

  private func announcement(
    _ announcement: AccessibilityAnnouncement
  ) -> String {
    object([
      ("message", string(announcement.message)),
      ("politeness", string(announcement.politeness.description)),
    ])
  }

  private func warning(
    _ warning: AccessibilityWarning
  ) -> String {
    object([
      ("id", string(warning.identity.path)),
      ("kind", string(warning.kind)),
      ("message", string(warning.message)),
    ])
  }

  private func rect(
    _ rect: CellRect
  ) -> String {
    object([
      ("x", number(rect.origin.x)),
      ("y", number(rect.origin.y)),
      ("width", number(rect.size.width)),
      ("height", number(rect.size.height)),
    ])
  }

  private func optionalPoint(
    _ point: CellPoint?
  ) -> String {
    guard let point else {
      return "null"
    }
    return object([
      ("x", number(point.x)),
      ("y", number(point.y)),
    ])
  }

  private func size(
    _ size: CellSize
  ) -> String {
    object([
      ("width", number(size.width)),
      ("height", number(size.height)),
    ])
  }

  private func object(
    _ fields: [(String, String)]
  ) -> String {
    "{" + fields.map { string($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
  }

  private func array(
    _ values: [String]
  ) -> String {
    "[" + values.joined(separator: ",") + "]"
  }

  private func optionalString(
    _ value: String?
  ) -> String {
    guard let value else {
      return "null"
    }
    return string(value)
  }

  private func string(
    _ value: String
  ) -> String {
    var output = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x22:
        output += "\\\""
      case 0x5C:
        output += "\\\\"
      case 0x08:
        output += "\\b"
      case 0x09:
        output += "\\t"
      case 0x0A:
        output += "\\n"
      case 0x0C:
        output += "\\f"
      case 0x0D:
        output += "\\r"
      case 0x00...0x1F:
        output += "\\u00" + twoDigitHex(Int(scalar.value))
      default:
        output.unicodeScalars.append(scalar)
      }
    }
    output += "\""
    return output
  }

  private func twoDigitHex(
    _ value: Int
  ) -> String {
    let digits = Array("0123456789ABCDEF")
    return String([digits[(value >> 4) & 0xF], digits[value & 0xF]])
  }

  private func bool(
    _ value: Bool
  ) -> String {
    value ? "true" : "false"
  }

  private func number(
    _ value: Int
  ) -> String {
    String(value)
  }
}
