import Foundation

public struct TodoistHTTPRequest: Sendable {
  public var url: URL
  public var method: HTTPMethod
  public var timeoutInterval: TimeInterval
  public var httpBody: Data?
  private var headerFields: [String: String]

  public init(
    url: URL,
    method: HTTPMethod = .get,
    timeoutInterval: TimeInterval = 60,
    httpBody: Data? = nil,
    headers: [String: String] = [:],
  ) {
    self.url = url
    self.method = method
    self.timeoutInterval = timeoutInterval
    self.httpBody = httpBody
    self.headerFields = headers.reduce(into: [String: String]()) { result, entry in
      result[entry.key.lowercased()] = entry.value
    }
  }

  public var httpMethod: String {
    method.rawValue
  }

  public var allHTTPHeaderFields: [String: String] {
    headerFields
  }

  public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
    let normalizedField = field.lowercased()
    if let value {
      headerFields[normalizedField] = value
    } else {
      headerFields.removeValue(forKey: normalizedField)
    }
  }

  public func value(forHTTPHeaderField field: String) -> String? {
    headerFields[field.lowercased()]
  }
}

public struct TodoistHTTPResponse: Sendable {
  public let statusCode: Int
  public let statusText: String
  public let headers: [String: String]
  public let data: Data

  public init(statusCode: Int, statusText: String, headers: [String: String], data: Data) {
    self.statusCode = statusCode
    self.statusText = statusText
    self.headers = headers
    self.data = data
  }
}

public struct TodoistFileResponse: Sendable {
  public let statusCode: Int
  public let statusText: String
  public let headers: [String: String]
  public let rawData: Data

  public init(statusCode: Int, statusText: String, headers: [String: String], rawData: Data) {
    self.statusCode = statusCode
    self.statusText = statusText
    self.headers = headers
    self.rawData = rawData
  }

  public var ok: Bool {
    (200..<300).contains(statusCode)
  }

  public func text() async throws -> String {
    guard let value = String(data: rawData, encoding: .utf8) else {
      throw NSError(
        domain: "TodoistFileResponseError",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Unable to decode file response body"],
      )
    }
    return value
  }

  public func arrayBuffer() async -> Data {
    rawData
  }

  public func json<T: Decodable>() async throws -> T {
    try JSONDecoder().decode(T.self, from: rawData)
  }
}

public protocol Transport: Sendable {
  func perform(_ request: TodoistHTTPRequest) async throws -> TodoistHTTPResponse
}
