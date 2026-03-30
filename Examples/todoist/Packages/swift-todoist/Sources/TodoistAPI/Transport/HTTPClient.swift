import Foundation

public struct TodoistHTTPClient: Sendable {
    public let transport: Transport
    public let baseURL: String
    public let authToken: String?

    public init(transport: Transport = DefaultTodoistTransport(), baseURL: String, authToken: String?) {
        self.transport = transport
        self.baseURL = baseURL
        self.authToken = authToken
    }

    public init(baseURL: String, authToken: String?) {
        self.init(transport: DefaultTodoistTransport(), baseURL: baseURL, authToken: authToken)
    }

    public func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        payload: [String: Any]? = nil,
        requestId: String? = nil,
        includeRequestIdForSync: Bool = false,
        customHeaders: [String: String] = [:],
        decoder: JSONDecoder = .default,
    ) async throws -> (response: TodoistHTTPResponse, value: T) {
        let url = makeURL(for: path, method: method, payload: payload)
        var request = TodoistHTTPRequest(url: url)
        request.method = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var headers = customHeaders
        if let authToken {
            headers["Authorization"] = "Bearer \(authToken)"
        }

        if let requestId {
            headers["X-Request-Id"] = requestId
        } else if method == .post && includeRequestIdForSync {
            headers["X-Request-Id"] = UUID().uuidString
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if method != .get {
            if let payload {
                let convertedPayload = CaseConversion.toSnakeCaseDictionary(payload.compactMapValues { $0 })
                request.httpBody = try JSONSerialization.data(withJSONObject: convertedPayload, options: [])
            }
        }

        let response = try await transport.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw TodoistRequestError(
                responseMessage(from: response),
                httpStatusCode: response.statusCode,
                responseData: response.data,
            )
        }

        do {
            let value = try decoder.decode(T.self, from: response.data)
            return (response, value)
        } catch {
            throw TodoistRequestError(
                decodingFailureMessage(
                    for: T.self,
                    error: error,
                ),
                httpStatusCode: response.statusCode,
                responseData: response.data,
            )
        }
    }

    public func requestVoid(
        method: HTTPMethod,
        path: String,
        payload: [String: Any]? = nil,
        requestId: String? = nil,
        includeRequestIdForSync: Bool = false,
        customHeaders: [String: String] = [:],
    ) async throws -> TodoistHTTPResponse {
        let url = makeURL(for: path, method: method, payload: payload)
        var request = TodoistHTTPRequest(url: url)
        request.method = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var headers = customHeaders
        if let authToken {
            headers["Authorization"] = "Bearer \(authToken)"
        }
        if let requestId {
            headers["X-Request-Id"] = requestId
        } else if method == .post && includeRequestIdForSync {
            headers["X-Request-Id"] = UUID().uuidString
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if method != .get, let payload {
            let convertedPayload = CaseConversion.toSnakeCaseDictionary(payload.compactMapValues { $0 })
            request.httpBody = try JSONSerialization.data(withJSONObject: convertedPayload, options: [])
        }

        return try await transport.perform(request)
    }

    private func makeURL(for path: String, method: HTTPMethod, payload: [String: Any]?) -> URL {
        if method == .get, let payload, !payload.isEmpty {
            let query = CaseConversion.serializeQueryParameters(
                CaseConversion.toSnakeCaseDictionary(payload.compactMapValues { $0 }),
            )
            let separator = baseURL.hasSuffix("/") ? "" : "/"
            let fullURL = "\(baseURL)\(separator)\(path)?\(query)"
            return URL(string: fullURL)!
        }

        let separator = baseURL.hasSuffix("/") ? "" : "/"
        let fullURL = "\(baseURL)\(separator)\(path)"
        return URL(string: fullURL)!
    }

    private func responseMessage(from response: TodoistHTTPResponse) -> String {
        if let parsed = try? JSONDecoder().decode([String: String].self, from: response.data),
            let error = parsed["error"]
        {
            return error
        }
        return response.statusText
    }

    private func decodingFailureMessage<T>(for type: T.Type, error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return "Response decoding failed: "
                + decodingErrorDescription(decodingError)
                + " while decoding \(String(reflecting: type))"
        }

        return "Response decoding failed while decoding \(String(reflecting: type)): "
            + error.localizedDescription
    }

    private func decodingErrorDescription(_ error: DecodingError) -> String {
        switch error {
        case let .dataCorrupted(context):
            return context.debugDescription
        case let .keyNotFound(key, context):
            let path = codingPath(context.codingPath + [key])
            return "missing key \(path)"
        case let .typeMismatch(_, context):
            let path = codingPath(context.codingPath)
            return "type mismatch at \(path): \(context.debugDescription)"
        case let .valueNotFound(_, context):
            let path = codingPath(context.codingPath)
            return "missing value at \(path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func codingPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "<root>"
        }

        return codingPath.map(\.stringValue).joined(separator: ".")
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public extension JSONDecoder {
    static let `default`: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
