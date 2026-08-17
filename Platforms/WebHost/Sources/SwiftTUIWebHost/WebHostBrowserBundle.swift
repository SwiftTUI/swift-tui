// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
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
#endif
