import Foundation

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let values = try? container.decode([AnyCodable].self) {
            value = values.map(\.value)
        } else if let values = try? container.decode([String: AnyCodable].self) {
            value = values.reduce(into: [String: Any]()) { result, item in
                result[item.key] = item.value.value
            }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let values = value as? [AnyCodable] {
            try container.encode(values)
        } else if let values = value as? [Any] {
            let wrapped = values.map(AnyCodable.init)
            try container.encode(wrapped)
        } else if let values = value as? [String: Any] {
            let wrapped = values.reduce(into: [String: AnyCodable]()) { result, item in
                result[item.key] = AnyCodable(item.value)
            }
            try container.encode(wrapped)
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"),
            )
        }
    }
}
