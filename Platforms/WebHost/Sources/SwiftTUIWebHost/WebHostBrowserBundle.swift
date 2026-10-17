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

package struct WebHostBrowserBundle: Sendable {
  package static let bundled = WebHostBrowserBundle()
  private let directory: String?

  package init(directory: String? = nil) {
    self.directory = directory
  }

  package func resource(
    for requestPath: String
  ) throws -> WebHostBrowserResource {
    let path = try normalizedResourcePath(for: requestPath)
    // The inventory is the route authority, including exact spelling on a
    // case-insensitive file system. Containment is checked again below.
    guard try assetPaths().contains(path) else { throw WebHostBrowserBundleError.notFound(path) }
    let url = try resourceURL(for: path)
    return WebHostBrowserResource(
      path: path,
      data: try Data(contentsOf: url),
      contentType: contentType(for: path)
    )
  }

  package func indexHTML(
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

  package func contentType(
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
    case "txt":
      return "text/plain; charset=utf-8"
    case "woff":
      return "font/woff"
    case "ttf":
      return "font/ttf"
    case "otf":
      return "font/otf"
    case "webp":
      return "image/webp"
    case "avif":
      return "image/avif"
    case "ico":
      return "image/vnd.microsoft.icon"
    case "woff2":
      return "font/woff2"
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

  package func assetPaths() throws -> [String] {
    let baseURL = try browserResourceDirectory()
    guard let enumerator = FileManager.default.enumerator(atPath: baseURL.path) else {
      return []
    }

    var paths: [String] = []
    for case let relativePath as String in enumerator {
      guard !relativePath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
        continue
      }
      let fileURL = baseURL.appendingPathComponent(relativePath, isDirectory: false)
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else {
        continue
      }
      // FileManager emits native separators on Windows; this inventory is
      // consumed as HTTP resource paths on every platform.
      paths.append(relativePath.replacingOccurrences(of: "\\", with: "/"))
    }
    return paths.sorted()
  }

  private func normalizedResourcePath(
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
    if directory == nil {
      if path == "static/webhost.js" {
        return try primaryJavaScriptAssetPath()
      }
      if path.hasPrefix("static/") {
        path.removeFirst("static/".count)
      }
    }
    guard !path.contains("\\"), !path.utf8.contains(0),
      !path.split(separator: "/").contains(where: { $0.hasPrefix(".") })
    else {
      throw WebHostBrowserBundleError.notFound(requestPath)
    }
    return path
  }

  private func primaryJavaScriptAssetPath() throws -> String {
    guard let path = try assetPaths().first(where: { $0.hasSuffix(".js") }) else {
      throw WebHostBrowserBundleError.notFound("static/webhost.js")
    }
    return path
  }

  private func resourceURL(
    for path: String
  ) throws -> URL {
    let baseURL = try browserResourceDirectory()
    let url = baseURL.appendingPathComponent(path, isDirectory: false)
      .standardizedFileURL.resolvingSymlinksInPath()
    let basePath = baseURL.standardizedFileURL.resolvingSymlinksInPath().path
    guard url.path.hasPrefix(basePath + "/") else {
      throw WebHostBrowserBundleError.notFound(path)
    }
    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
      throw WebHostBrowserBundleError.notFound(path)
    }
    return url
  }

  private func browserResourceDirectory() throws -> URL {
    if let directory {
      let url = URL(fileURLWithPath: directory, isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
        throw WebHostBrowserBundleError.missingDirectory(directory)
      }
      return url
    }
    // `.copy("Resources/browser")` preserves the directory in SwiftPM's module
    // bundle, so request paths remain rooted at its contents rather than at the
    // module bundle itself.
    let browserURL = Bundle.module.resourceURL?
      .appendingPathComponent("browser", isDirectory: true)
    guard let browserURL else {
      throw WebHostBrowserBundleError.missingBundle
    }
    guard
      let values = try? browserURL.resourceValues(forKeys: [.isDirectoryKey]),
      values.isDirectory == true
    else {
      throw WebHostBrowserBundleError.missingBundle
    }
    return browserURL
  }
}

package enum WebHostBrowserBundleError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingDirectory(String)
  case missingBundle
  case notFound(String)

  package var description: String {
    switch self {
    case .missingDirectory(let path):
      return "The custom WebHost browser bundle directory is missing: \(path)."
    case .missingBundle:
      return "The WebHost browser bundle is missing."
    case .notFound(let path):
      return "WebHost browser resource not found: \(path)."
    }
  }
}
