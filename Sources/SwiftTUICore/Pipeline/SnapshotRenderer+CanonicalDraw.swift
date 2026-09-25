@_spi(Testing) import SwiftTUIPrimitives

extension SnapshotRenderer {
  package enum CanonicalDrawError: Error, Equatable {
    case unsupportedValue(String)
  }

  /// A diagnostic format, versioned independently of the concise draw printer.
  /// Only allocation IDs, cached identity hashes, derived subtree aggregates,
  /// and non-style environment bookkeeping are omitted. Paint order is exact.
  package func canonicalDrawTree(_ node: DrawNode) throws -> String {
    var lines = ["SwiftTUI canonical draw v1"]
    try appendCanonicalDraw(node, path: "root", lines: &lines)
    return lines.joined(separator: "\n")
  }

  package func canonicalDrawDifference(_ before: DrawNode, _ after: DrawNode) throws -> String {
    let lhs = try canonicalDrawTree(before).split(separator: "\n", omittingEmptySubsequences: false)
    let rhs = try canonicalDrawTree(after).split(separator: "\n", omittingEmptySubsequences: false)
    var lines: [String] = []
    for index in 0..<max(lhs.count, rhs.count) {
      let old = index < lhs.count ? String(lhs[index]) : nil
      let new = index < rhs.count ? String(rhs[index]) : nil
      if old != new {
        lines.append("@@ line \(index + 1) @@")
        if let old { lines.append("- \(old)") }
        if let new { lines.append("+ \(new)") }
      }
    }
    return lines.isEmpty ? "canonical draw v1: equal" : lines.joined(separator: "\n")
  }

  private func appendCanonicalDraw(
    _ node: DrawNode, path: String, lines: inout [String]
  ) throws {
    lines.append("\(path) identity=\(try canonicalValue(node.identity))")
    lines.append(
      "\(path) bounds=\(describe(node.bounds)) clip=\(node.clipBounds.map(describe) ?? "nil")")
    lines.append("\(path) style=\(try canonicalValue(node.environmentSnapshot.style))")
    lines.append("\(path) metadata=\(try canonicalValue(node.metadata))")
    lines.append("\(path) effects=\(try canonicalValue(node.drawEffects.ordered))")
    for (index, command) in node.commands.enumerated() {
      try appendCanonicalCommand(command, path: "\(path).paint[\(index)]", lines: &lines)
    }
    for (index, child) in node.children.enumerated() {
      try appendCanonicalDraw(child, path: "\(path).child[\(index)]", lines: &lines)
    }
    for (index, command) in node.postCommands.enumerated() {
      try appendCanonicalCommand(command, path: "\(path).post[\(index)]", lines: &lines)
    }
    lines.append("\(path) end")
  }

  private func appendCanonicalCommand(
    _ command: DrawCommand, path: String, lines: inout [String]
  ) throws {
    // Existing formatters provide the concise readable label. The structural
    // value below retains details those intentionally abbreviated labels omit.
    lines.append("\(path) \(String(reflecting: describe(command)))")
    lines.append("\(path) value=\(try canonicalValue(command))")
  }

  private func canonicalValue(_ value: Any) throws -> String {
    if let value = value as? Identity {
      return "Identity(\(try canonicalValue(value.components)))"
    }
    if let value = value as? BoxedPath {
      return "BoxedPath(\(try canonicalValue(value.path.elements)))"
    }
    if let value = value as? Boxed<DrawMetadata.HeavyFields> {
      return "DrawMetadata.HeavyFields(\(try canonicalValue(value.value)))"
    }
    if let value = value as? StyleHeavyFieldsStorage {
      return
        "StyleHeavyFields(appearance:\(try canonicalValue(value.appearance)),theme:\(try canonicalValue(value.theme)))"
    }
    if let value = value as? MeshGradient {
      // The mesh keeps its fields in boxed storage, and a `SIMD2` point has
      // no reflectable fields. The public accessors are the whole value.
      let points = try value.points.map {
        "(\(try canonicalValue($0.x)),\(try canonicalValue($0.y)))"
      }
      let fields = [
        "\"width\":\(try canonicalValue(value.width))",
        "\"height\":\(try canonicalValue(value.height))",
        "\"points\":[\(points.joined(separator: ","))]",
        "\"colors\":\(try canonicalValue(value.colors))",
        "\"background\":\(try canonicalValue(value.background))",
        "\"smoothsColors\":\(try canonicalValue(value.smoothsColors))",
        "\"colorSpace\":\(try canonicalValue(value.colorSpace))",
      ]
      return "\(String(reflecting: MeshGradient.self)){\(fields.joined(separator: ","))}"
    }
    if let command = value as? DrawCommand {
      switch command {
      case .canvas, .foreignSurface:
        // User drawing implementations and live foreign surfaces have no
        // closed value schema. Never label a lossy projection as equivalent.
        throw CanonicalDrawError.unsupportedValue("canvas or foreignSurface")
      default:
        break
      }
    }
    if let value = value as? String { return String(reflecting: value) }
    if let value = value as? Character { return String(reflecting: String(value)) }
    if let value = value as? Bool { return value ? "true" : "false" }
    if let value = value as? any BinaryInteger { return String(describing: value) }
    if let value = value as? Double { return "f64:\(String(value.bitPattern, radix: 16))" }
    if let value = value as? Float { return "f32:\(String(value.bitPattern, radix: 16))" }
    let mirror = Mirror(reflecting: value)
    let type = String(reflecting: Swift.type(of: value))
    guard let displayStyle = mirror.displayStyle, displayStyle != .class else {
      throw CanonicalDrawError.unsupportedValue(type)
    }
    var fields = try mirror.children.map { child in
      "\(child.label.map { String(reflecting: $0) } ?? "_"):\(try canonicalValue(child.value))"
    }
    if displayStyle == .dictionary || displayStyle == .set { fields.sort() }
    if fields.isEmpty && displayStyle == .enum {
      return "\(type).\(String(describing: value))"
    }
    return "\(type){\(fields.joined(separator: ","))}"
  }
}
