package import Foundation

package struct WebHostBrowserResource: Equatable, Sendable {
  package var path: String
  package var data: Data
  package var contentType: String

  package init(
    path: String,
    data: Data,
    contentType: String
  ) {
    self.path = path
    self.data = data
    self.contentType = contentType
  }
}

package enum WebHostBrowserBundle {
  package static func resource(
    for requestPath: String
  ) throws -> WebHostBrowserResource {
    let path = try normalizedResourcePath(for: requestPath)
    let url = try resourceURL(for: path)
    return WebHostBrowserResource(
      path: path,
      data: try Data(contentsOf: url),
      contentType: contentType(for: path)
    )
  }

  package static func indexHTML(
    token: WebHostToken
  ) throws -> Data {
    let resource = try resource(for: "/")
    guard var html = String(data: resource.data, encoding: .utf8) else {
      return resource.data
    }

    html = html.replacingOccurrences(of: ".js\"", with: ".js?token=\(token.rawValue)\"")
    html = html.replacingOccurrences(of: ".css\"", with: ".css?token=\(token.rawValue)\"")
    return Data(html.utf8)
  }

  package static func contentType(
    for path: String
  ) -> String {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "html":
      return "text/html; charset=utf-8"
    case "js", "mjs":
      return "application/javascript; charset=utf-8"
    case "css":
      return "text/css; charset=utf-8"
    case "json":
      return "application/json; charset=utf-8"
    case "wasm":
      return "application/wasm"
    case "svg":
      return "image/svg+xml"
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "gif":
      return "image/gif"
    default:
      return "application/octet-stream"
    }
  }

  package static func assetPaths() throws -> [String] {
    let baseURL = try browserResourceDirectory()
    guard
      let enumerator = FileManager.default.enumerator(
        at: baseURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var paths: [String] = []
    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else {
        continue
      }
      let relativePath = String(fileURL.path.dropFirst(baseURL.path.count + 1))
      paths.append(relativePath)
    }
    return paths.sorted()
  }

  private static func normalizedResourcePath(
    for requestPath: String
  ) throws -> String {
    let pathWithoutQuery =
      requestPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
    var path = pathWithoutQuery
    while path.hasPrefix("/") {
      path.removeFirst()
    }
    if path.isEmpty {
      return "index.html"
    }
    if path == "static/webhost.js" {
      return try primaryJavaScriptAssetPath()
    }
    if path.hasPrefix("static/") {
      path.removeFirst("static/".count)
    }
    guard !path.split(separator: "/").contains("..") else {
      throw WebHostBrowserBundleError.notFound(requestPath)
    }
    return path
  }

  private static func primaryJavaScriptAssetPath() throws -> String {
    guard let path = try assetPaths().first(where: { $0.hasSuffix(".js") }) else {
      throw WebHostBrowserBundleError.notFound("static/webhost.js")
    }
    return path
  }

  private static func resourceURL(
    for path: String
  ) throws -> URL {
    let baseURL = try browserResourceDirectory()
    let url = baseURL.appendingPathComponent(path, isDirectory: false).standardizedFileURL
    let basePath = baseURL.standardizedFileURL.path
    guard url.path.hasPrefix(basePath + "/") else {
      throw WebHostBrowserBundleError.notFound(path)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw WebHostBrowserBundleError.notFound(path)
    }
    return url
  }

  private static func browserResourceDirectory() throws -> URL {
    if let url = Bundle.module.url(forResource: "browser", withExtension: nil) {
      return url
    }
    throw WebHostBrowserBundleError.missingBundle
  }
}

package enum WebHostBrowserBundleError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingBundle
  case notFound(String)

  package var description: String {
    switch self {
    case .missingBundle:
      return "The WebHost browser bundle is missing."
    case .notFound(let path):
      return "WebHost browser resource not found: \(path)."
    }
  }
}
