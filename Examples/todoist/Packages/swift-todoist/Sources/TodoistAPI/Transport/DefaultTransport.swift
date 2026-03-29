import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

public struct DefaultTodoistTransport: Transport {
    public struct RetryPolicy: Sendable {
        public let maxRetries: Int
        public let retryDelay: @Sendable (Int) -> UInt64

        public init(
            maxRetries: Int = 3,
            retryDelay: @escaping @Sendable (Int) -> UInt64 = { attempt in
                attempt == 1 ? 0 : 500
            },
        ) {
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
        }
    }

    private let policy: RetryPolicy
    private let executor: @Sendable (TodoistHTTPRequest) async throws -> TodoistHTTPResponse

    public init(client: HTTPClient = .shared, policy: RetryPolicy = .init()) {
        self.policy = policy
        self.executor = { request in
            try await Self.send(request, using: client)
        }
    }

    init(
        policy: RetryPolicy = .init(),
        executor: @escaping @Sendable (TodoistHTTPRequest) async throws -> TodoistHTTPResponse,
    ) {
        self.policy = policy
        self.executor = executor
    }

    public func perform(_ request: TodoistHTTPRequest) async throws -> TodoistHTTPResponse {
        var attempt = 0
        var lastError: Error?
        var request = request
        request.timeoutInterval = 30

        while attempt <= policy.maxRetries {
            do {
                let result = try await executor(request)
                return result
            } catch {
                lastError = error
                if attempt >= policy.maxRetries || !Self.isNetworkError(error) {
                    throw error
                }
                attempt += 1
                let delayMs = policy.retryDelay(attempt)
                if delayMs > 0 {
                    try await Swift.Task.sleep(nanoseconds: delayMs * 1_000_000)
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func send(_ request: TodoistHTTPRequest, using client: HTTPClient) async throws -> TodoistHTTPResponse {
        var httpRequest = HTTPClientRequest(url: request.url.absoluteString)
        httpRequest.method = httpMethod(for: request.method)

        for (key, value) in request.allHTTPHeaderFields {
            httpRequest.headers.add(name: key, value: value)
        }

        if let body = request.httpBody {
            httpRequest.body = .bytes(body)
        }

        let response = try await client.execute(httpRequest, timeout: timeout(for: request.timeoutInterval))
        let buffer = try await response.body.collect(upTo: Int.max)
        let data = Data(buffer.readableBytesView)

        let headers = response.headers.reduce(into: [String: String]()) { result, entry in
            result[entry.name.lowercased()] = entry.value
        }

        return TodoistHTTPResponse(
            statusCode: Int(response.status.code),
            statusText: response.status.reasonPhrase,
            headers: headers,
            data: data,
        )
    }

    private static func httpMethod(for method: HTTPMethod) -> NIOHTTP1.HTTPMethod {
        switch method {
        case .get:
            return .GET
        case .post:
            return .POST
        case .put:
            return .PUT
        case .delete:
            return .DELETE
        }
    }

    private static func timeout(for timeoutInterval: TimeInterval) -> TimeAmount {
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            return .seconds(30)
        }

        let nanoseconds = timeoutInterval * 1_000_000_000
        if nanoseconds >= Double(Int64.max) {
            return .nanoseconds(Int64.max)
        }

        return .nanoseconds(Int64(nanoseconds.rounded()))
    }

    public static func isNetworkError(_ error: Error) -> Bool {
        if let clientError = error as? HTTPClientError {
            return [
                .cancelled,
                .connectTimeout,
                .deadlineExceeded,
                .getConnectionFromPoolTimeout,
                .httpProxyHandshakeTimeout,
                .readTimeout,
                .remoteConnectionClosed,
                .requestStreamCancelled,
                .socksHandshakeTimeout,
                .tlsHandshakeTimeout,
                .writeTimeout,
            ].contains(clientError)
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        let networkCodes: [Int] = [
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorDataNotAllowed,
        ]
        return networkCodes.contains(nsError.code)
    }
}
