import Synchronization

package enum BodyChangeFormat: Sendable {
  case text
  case json
}

/// The host can install a session sink without adding a Runtime dependency to
/// the authoring products. Only the sink is inherited by tasks, never a body.
package struct BodyChangeSink: Sendable {
  package var emit: @MainActor @Sendable (BodyChangeRecord, BodyChangeFormat) -> Void

  package init(_ emit: @escaping @MainActor @Sendable (BodyChangeRecord, BodyChangeFormat) -> Void)
  {
    self.emit = emit
  }
}

package enum BodyChangeOutput {
  @TaskLocal package static var sink: BodyChangeSink?

  @MainActor
  package static func emit(_ record: BodyChangeRecord, format: BodyChangeFormat) {
    #if DEBUG
      if let sink {
        sink.emit(record, format)
      } else {
        emitPortable(record, format: format)
      }
    #endif
  }
  private static let suppressed = Mutex<Int>(0)

  package static func emitPortable(
    _ record: BodyChangeRecord, format: BodyChangeFormat, descriptor: Int32 = 2
  ) {
    let written = DebugLogRouter.emit(
      record.formatted(format),
      toFileAt: DebugLogRouter.resolvedFilePath(
        override: nil, bundleFileName: format == .text ? "changes.log" : "changes.jsonl"),
      fallback: .safeStandardError, standardErrorDescriptor: descriptor)
    if !written { suppressed.withLock { $0 = min($0, Int.max - 1) + 1 } }
  }

  /// No record payload is buffered. Report a bounded count after all owned
  /// terminals are restored. If stderr is still disconnected, retain the count.
  package static func flushSuppressed(to descriptor: Int32 = 2) {
    guard !DiagnosticScreenOwnership.isScreenOwned else { return }
    suppressed.withLock { count in
      guard count > 0 else { return }
      if DebugLogRouter.writeDiagnostic(
        "\nSwiftTUI body diagnostics: \(count) record(s) suppressed; use a debug bundle or redirect stderr to another terminal.\n",
        to: descriptor)
      {
        count = 0
      }
    }
  }

}

extension BodyChangeRecord {
  package static let maximumEncodedBytes = 8_192

  /// One physical line, with bounded metadata and no application values.
  package func formatted(_ format: BodyChangeFormat) -> String {
    var record = self
    record.typeName = Self.bounded(typeName, bytes: 512)
    record.kind = Self.bounded(kind, bytes: 32)
    let sorted = Set(causes).sorted {
      ($0.category, $0.property ?? "", $0.precision) < (
        $1.category, $1.property ?? "", $1.precision
      )
    }
    let excessCauses = max(0, sorted.count - 64)
    record.omitted = min(record.omitted, Int.max - excessCauses) + excessCauses
    record.causes = sorted.prefix(64).map { cause in
      Cause(
        Self.bounded(cause.category, bytes: 64),
        precision: Self.bounded(cause.precision, bytes: 32),
        property: cause.property.map { Self.bounded($0, bytes: 256) })
    }
    if record.typeName != typeName || record.kind != kind
      || zip(record.causes, sorted).contains(where: { $0 != $1 })
    {
      record.omitted = min(record.omitted, Int.max - 1) + 1
    }
    while true {
      let line = record.encode(format)
      if line.utf8.count <= Self.maximumEncodedBytes { return line }
      guard !record.causes.isEmpty else { return "{\"schema\":1,\"omitted\":1}\n" }
      record.causes.removeLast()
      record.omitted = min(record.omitted, Int.max - 1) + 1
    }
  }

  private func encode(_ format: BodyChangeFormat) -> String {
    if format == .text {
      let reasons = causes.map { cause in
        let name = cause.property.map { Self.escaped($0) + " " } ?? ""
        return name + "(\(Self.escaped(cause.category)), \(Self.escaped(cause.precision)))"
      }.joined(separator: ", ")
      return
        "\(Self.escaped(typeName)) [kind=\(Self.escaped(kind)) graph=\(graph) owner=\(owner) body=\(body) attempt=\(attempt) phase=evaluate]: \(reasons)"
        + (omitted > 0 ? " omitted=\(omitted)" : "") + "\n"
    }
    let reasons = causes.map { cause in
      "{\"category\":\(Self.quoted(cause.category)),\"precision\":\(Self.quoted(cause.precision))"
        + (cause.property.map { ",\"property\":\(Self.quoted($0))" } ?? "") + "}"
    }.joined(separator: ",")
    return
      "{\"schema\":1,\"type\":\(Self.quoted(typeName)),\"kind\":\(Self.quoted(kind)),\"graph\":\(graph),\"owner\":\(owner),\"body\":\(body),\"attempt\":\(attempt),\"phase\":\"evaluate\",\"causes\":[\(reasons)],\"omitted\":\(omitted)}\n"
  }

  private static func bounded(_ text: String, bytes: Int) -> String {
    var result = ""
    var remaining = bytes
    for scalar in text.unicodeScalars {
      let part = String(scalar)
      guard part.utf8.count <= remaining else { break }
      result += part
      remaining -= part.utf8.count
    }
    return result
  }

  private static func quoted(_ text: String) -> String { "\"" + escaped(text) + "\"" }

  private static func escaped(_ text: String) -> String {
    var result = ""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x22: result += "\\\""
      case 0x5C: result += "\\\\"
      case 0...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
        let hex = String(scalar.value, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }
}
