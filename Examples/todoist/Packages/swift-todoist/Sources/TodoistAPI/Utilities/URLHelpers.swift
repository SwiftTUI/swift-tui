import Foundation

public enum URLHelpers {
  private static let webBase = "https://app.todoist.com/app"

  public static func getTaskUrl(taskId: String, content: String? = nil) -> String {
    let slug = content.flatMap(slugify)
    if let slug, !slug.isEmpty {
      return "\(webBase)/task/\(slug)-\(taskId)"
    }
    return "\(webBase)/task/\(taskId)"
  }

  public static func getProjectUrl(projectId: String, name: String? = nil) -> String {
    let slug = name.flatMap(slugify)
    if let slug, !slug.isEmpty {
      return "\(webBase)/project/\(slug)-\(projectId)"
    }
    return "\(webBase)/project/\(projectId)"
  }

  public static func getSectionUrl(sectionId: String, name: String? = nil) -> String {
    let slug = name.flatMap(slugify)
    if let slug, !slug.isEmpty {
      return "\(webBase)/section/\(slug)-\(sectionId)"
    }
    return "\(webBase)/section/\(sectionId)"
  }

  public static func formatDateToYYYYMMDD(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func slugify(_ value: String) -> String {
    let normalized = value.folding(options: .diacriticInsensitive, locale: .current)
    let asciiOnly = normalized.replacingOccurrences(
      of: "[^\\x20-\\x7E]", with: "", options: .regularExpression)
    let valid = asciiOnly.lowercased().replacingOccurrences(
      of: "[^\\w\\s-]", with: "", options: .regularExpression)
    let hyphenated =
      valid
      .replacingOccurrences(of: "[\\s-]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return hyphenated
  }
}
