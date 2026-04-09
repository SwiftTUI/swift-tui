import Foundation

public enum UncompletableHelpers {
  public static let prefix = "* "

  public static func hasUncompletablePrefix(_ content: String) -> Bool {
    content.hasPrefix(prefix)
  }

  public static func addUncompletablePrefix(_ content: String) -> String {
    if hasUncompletablePrefix(content) {
      return content
    }
    return "\(prefix)\(content)"
  }

  public static func removeUncompletablePrefix(_ content: String) -> String {
    guard hasUncompletablePrefix(content) else {
      return content
    }
    return String(content.dropFirst(prefix.count))
  }

  public static func processTaskContent(_ content: String, isUncompletable: Bool?) -> String {
    if hasUncompletablePrefix(content) {
      return content
    }
    if isUncompletable == true {
      return addUncompletablePrefix(content)
    }
    return content
  }
}
