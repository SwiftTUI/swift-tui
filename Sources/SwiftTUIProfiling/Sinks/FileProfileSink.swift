import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// File-backed sink. `tsv` writes the frame signal as the legacy
/// tab-separated columns (memory/cpu are not column-shaped and are skipped).
/// `jsonl` writes one JSON object per record for every signal.
@MainActor
package final class FileProfileSink: ProfileSink {
  package enum Format: Sendable {
    case tsv
    case jsonl
  }

  private let fileDescriptor: Int32
  private let ownsDescriptor: Bool
  private let format: Format
  private var tsvHeaderWritten = false

  package init?(path: String, format: Format) {
    self.format = format
    #if !canImport(WASILibc)
      let descriptor = unsafe open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      guard descriptor >= 0 else {
        return nil
      }
      fileDescriptor = descriptor
      ownsDescriptor = true
    #else
      fileDescriptor = -1
      ownsDescriptor = false
      return nil
    #endif
  }

  deinit {
    #if !canImport(WASILibc)
      if ownsDescriptor {
        close(fileDescriptor)
      }
    #endif
  }

  package func emit(_ record: ProfileRecord) {
    switch format {
    case .tsv:
      emitTSV(record)
    case .jsonl:
      writeLine(jsonLine(for: record))
    }
  }

  private func emitTSV(_ record: ProfileRecord) {
    guard case .frame(let frame) = record else {
      return
    }
    if !tsvHeaderWritten {
      writeLine(FrameDiagnosticsTSVFormatting.headerFields.joined(separator: "\t"))
      tsvHeaderWritten = true
    }
    writeLine(FrameDiagnosticsTSVFormatting.fields(for: frame).joined(separator: "\t"))
  }

  private func jsonLine(for record: ProfileRecord) -> String {
    switch record {
    case .frame(let frame):
      return """
        {"signal":"frame","frameNumber":\(frame.frameNumber),\
        "causeSummary":\(quoted(frame.causeSummary)),\
        "resolvedNodes":\(frame.resolvedNodeCount),"measuredNodes":\(frame.measuredNodeCount),\
        "placedNodes":\(frame.placedNodeCount),"drawNodes":\(frame.drawNodeCount),\
        "presentationStrategy":\(quoted(frame.presentationStrategy)),\
        "presentationBytesWritten":\(frame.presentationBytesWritten)}
        """
    case .memory(let snapshots):
      let entries = snapshots.map { snapshot -> String in
        let bytes = snapshot.approxBytes.map { ",\"approxBytes\":\($0)" } ?? ""
        return "{\"name\":\(quoted(snapshot.name)),\"count\":\(snapshot.count)\(bytes)}"
      }
      return "{\"signal\":\"memory\",\"providers\":[\(entries.joined(separator: ","))]}"
    case .cpu(let sample):
      return """
        {"signal":"cpu","estimatedCPUPercent":\(sample.estimatedCPUPercent),\
        "totalCPUSeconds":\(sample.totalCPUSeconds),\
        "maxResidentBytes":\(sample.maxResidentBytes)}
        """
    }
  }

  private func quoted(_ string: String) -> String {
    var escaped = ""
    for character in string {
      switch character {
      case "\\":
        escaped += "\\\\"
      case "\"":
        escaped += "\\\""
      case "\n":
        escaped += "\\n"
      case "\t":
        escaped += "\\t"
      default:
        escaped.append(character)
      }
    }
    return "\"\(escaped)\""
  }

  private func writeLine(_ line: String) {
    #if !canImport(WASILibc)
      guard ownsDescriptor else {
        return
      }
      var data = line + "\n"
      data.withUTF8 { buffer in
        guard let base = buffer.baseAddress, buffer.count > 0 else {
          return
        }
        _ = unsafe write(fileDescriptor, base, buffer.count)
      }
    #endif
  }
}
