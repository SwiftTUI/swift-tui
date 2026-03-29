import Foundation

public enum JSONUtils {
    public static func toJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        return decoded as? [String: Any] ?? [:]
    }

    public static func toJSONObject(_ value: [String: Any]) -> [String: Any] {
        value
    }
}
