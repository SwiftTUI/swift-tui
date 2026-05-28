/// Parses the `SWIFTTUI_PROFILE` environment grammar into a ``ProfileConfig``.
///
/// ```
/// SWIFTTUI_PROFILE = signal-list [ ";" sink-list ]
/// signal-list      = signal *( "," signal )
/// signal           = "frames" | "memory" [ "@" duration ] | "cpu" [ "@" duration ]
/// sink-list        = sink *( "," sink )
/// sink             = "tsv=" path | "jsonl=" path | "summary"
/// duration         = e.g. 100ms, 1s, 2s500ms
/// ```
///
/// Returns `nil` for an unset, empty, or malformed value — profiling stays
/// fully disabled rather than partially activating on bad input.
package enum EnvProfileParser {
  package static func parse(_ raw: String?) -> ProfileConfig? {
    guard let raw else {
      return nil
    }
    let normalized = trimmed(raw)
    guard !normalized.isEmpty else {
      return nil
    }

    let sections = normalized.split(separator: ";", omittingEmptySubsequences: false)
    guard sections.count <= 2 else {
      return nil
    }

    guard let signals = parseSignals(String(sections[0])) else {
      return nil
    }

    let sinks: [ProfileConfig.SinkDescriptor]
    if sections.count == 2 {
      guard let parsed = parseSinks(String(sections[1])) else {
        return nil
      }
      sinks = parsed
    } else {
      sinks = []
    }

    return ProfileConfig(signals: signals, sinks: sinks)
  }

  private static func parseSignals(_ section: String) -> Set<ProfileConfig.Signal>? {
    let tokens = section.split(separator: ",", omittingEmptySubsequences: false)
      .map { trimmed(String($0)) }
    guard !tokens.isEmpty, !tokens.contains(where: \.isEmpty) else {
      return nil
    }
    var signals: Set<ProfileConfig.Signal> = []
    for token in tokens {
      guard let signal = parseSignal(token) else {
        return nil
      }
      signals.insert(signal)
    }
    return signals.isEmpty ? nil : signals
  }

  private static func parseSignal(_ token: String) -> ProfileConfig.Signal? {
    if token == "frames" {
      return .frames
    }
    if let interval = intervalSignal(token, name: "memory") {
      return .memory(interval: interval ?? ProfileConfig.defaultMemoryInterval)
    }
    if let interval = intervalSignal(token, name: "cpu") {
      return .cpu(interval: interval ?? ProfileConfig.defaultCPUInterval)
    }
    return nil
  }

  /// Returns `.some(nil)` for a bare `name` (use the default interval),
  /// `.some(.some(duration))` for `name@duration`, and `nil` when `token` is not
  /// this signal or its duration is malformed.
  private static func intervalSignal(_ token: String, name: String) -> Duration?? {
    if token == name {
      return .some(nil)
    }
    guard token.hasPrefix("\(name)@") else {
      return nil
    }
    let durationText = String(token.dropFirst(name.count + 1))
    guard let duration = parseDuration(durationText) else {
      return nil
    }
    return .some(duration)
  }

  private static func parseSinks(_ section: String) -> [ProfileConfig.SinkDescriptor]? {
    let tokens = section.split(separator: ",", omittingEmptySubsequences: false)
      .map { trimmed(String($0)) }
    guard !tokens.isEmpty, !tokens.contains(where: \.isEmpty) else {
      return nil
    }
    var sinks: [ProfileConfig.SinkDescriptor] = []
    for token in tokens {
      guard let sink = parseSink(token) else {
        return nil
      }
      sinks.append(sink)
    }
    return sinks
  }

  private static func parseSink(_ token: String) -> ProfileConfig.SinkDescriptor? {
    if token == "summary" {
      return .summary
    }
    if let path = value(of: token, key: "tsv") {
      return .tsv(path: path)
    }
    if let path = value(of: token, key: "jsonl") {
      return .jsonl(path: path)
    }
    return nil
  }

  private static func value(of token: String, key: String) -> String? {
    guard token.hasPrefix("\(key)=") else {
      return nil
    }
    let path = String(token.dropFirst(key.count + 1))
    return path.isEmpty ? nil : path
  }

  package static func parseDuration(_ string: String) -> Duration? {
    guard !string.isEmpty else {
      return nil
    }
    var total: Duration = .zero
    var index = string.startIndex
    var sawComponent = false
    while index < string.endIndex {
      var numberEnd = index
      while numberEnd < string.endIndex, string[numberEnd].isNumber {
        numberEnd = string.index(after: numberEnd)
      }
      guard numberEnd > index, let value = Int(string[index..<numberEnd]) else {
        return nil
      }
      let rest = string[numberEnd...]
      if rest.hasPrefix("ms") {
        total += .milliseconds(value)
        index = string.index(numberEnd, offsetBy: 2)
      } else if rest.hasPrefix("s") {
        total += .seconds(value)
        index = string.index(after: numberEnd)
      } else {
        return nil
      }
      sawComponent = true
    }
    return sawComponent ? total : nil
  }

  private static func trimmed(_ string: String) -> String {
    var view = string[...]
    while let first = view.first, first == " " || first == "\t" {
      view = view.dropFirst()
    }
    while let last = view.last, last == " " || last == "\t" {
      view = view.dropLast()
    }
    return String(view)
  }
}
