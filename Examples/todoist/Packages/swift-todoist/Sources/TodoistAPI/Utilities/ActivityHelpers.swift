public enum ActivityHelpers {
    public static func normalizeObjectTypeForAPI(_ objectType: String?) -> String? {
        guard let objectType else {
            return nil
        }
        switch objectType {
        case "task":
            return "item"
        case "comment":
            return "note"
        default:
            return objectType
        }
    }

    public static func denormalizeObjectTypeFromAPI(_ objectType: String?) -> String? {
        guard let objectType else {
            return nil
        }
        switch objectType {
        case "item":
            return "task"
        case "note":
            return "comment"
        default:
            return objectType
        }
    }

    public static func normalizeObjectEventTypeForAPI(_ value: String) -> String {
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count == 1 {
            return normalizeObjectTypeForAPI(value) ?? value
        }
        return "\(normalizeObjectTypeForAPI(String(pieces[0])) ?? String(pieces[0])):\(pieces.dropFirst().joined())"
    }

    public static func denormalizeObjectEventTypeFromAPI(_ value: String) -> String {
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count == 1 {
            return denormalizeObjectTypeFromAPI(value) ?? value
        }
        return "\(denormalizeObjectTypeFromAPI(String(pieces[0])) ?? String(pieces[0])):\(pieces.dropFirst().joined())"
    }
}
