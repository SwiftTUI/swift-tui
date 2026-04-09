import Foundation

public enum CaseConversion {
  public static func toSnakeCase(_ value: String) -> String {
    guard !value.isEmpty else {
      return value
    }

    var result = ""
    for scalar in value.unicodeScalars {
      if CharacterSet.uppercaseLetters.contains(scalar) {
        if !result.isEmpty {
          result.append("_")
        }
        result.append(contentsOf: String(scalar).lowercased())
      } else {
        result.append(String(scalar))
      }
    }
    return result
  }

  public static func toCamelCase(_ value: String) -> String {
    let parts = value.split(separator: "_")
    guard parts.count > 1 else {
      return value
    }

    return parts.enumerated().reduce(into: "") { result, item in
      let part = String(item.element)
      if item.offset == 0 {
        result = part
      } else {
        result += part.prefix(1).uppercased() + part.dropFirst()
      }
    }
  }

  public static func toSnakeCaseDictionary(_ value: [String: Any?]) -> [String: Any] {
    var output: [String: Any] = [:]
    for (key, nested) in value {
      let snakeKey = toSnakeCase(key)
      output[snakeKey] = convertAnyToSnakeCase(nested)
    }
    return output
  }

  public static func convertAnyToSnakeCase(_ value: Any?) -> Any {
    guard let value else {
      return NSNull()
    }
    if let dictionary = value as? [String: Any] {
      return toSnakeCaseDictionary(dictionary)
    }
    if let dictionary = value as? [String: Any?] {
      return toSnakeCaseDictionary(dictionary)
    }
    if let array = value as? [Any] {
      return array.map(convertAnyToSnakeCase(_:))
    }
    if let date = value as? Date {
      return ISO8601DateFormatter().string(from: date)
    }
    return value
  }

  public static func paramsValueString(_ value: Any) -> String? {
    if let value = value as? String {
      return value
    }
    if let value = value as? Bool {
      return value ? "true" : "false"
    }
    if let value = value as? NSNumber {
      return value.stringValue
    }
    if let value = value as? Int {
      return String(value)
    }
    if let value = value as? Double {
      return String(value)
    }

    if JSONSerialization.isValidJSONObject(value) {
      guard
        let data = try? JSONSerialization.data(withJSONObject: value, options: []),
        let text = String(data: data, encoding: .utf8)
      else {
        return nil
      }
      return text
    }
    return nil
  }

  public static func serializeQueryParameters(_ parameters: [String: Any]) -> String {
    let components = parameters.compactMap { item -> String? in
      let snakeKey = toSnakeCase(item.key)
      let value = item.value

      if let values = value as? [Any] {
        guard let serialized = paramsValueString(values) else { return nil }
        return
          "\(snakeKey)=\(serialized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? serialized)"
      }

      guard let raw = paramsValueString(value) else {
        return nil
      }
      return
        "\(snakeKey)=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)"
    }

    return components.joined(separator: "&")
  }
}
