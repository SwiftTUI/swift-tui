import Foundation

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

    public init(policy: RetryPolicy = .init()) {
        self.policy = policy
        self.executor = { request in
            try await Self.send(request)
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

    private static func send(_ request: TodoistHTTPRequest) async throws -> TodoistHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = timeoutInterval(for: request.timeoutInterval)
        urlRequest.httpBody = request.httpBody

        for (key, value) in request.allHTTPHeaderFields {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else {
                return
            }
            result[key.lowercased()] = String(describing: entry.value)
        }

        return TodoistHTTPResponse(
            statusCode: httpResponse.statusCode,
            statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            headers: headers,
            data: data,
        )
    }

    public static func isNetworkError(_ error: Error) -> Bool {
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

    private static func timeoutInterval(for timeoutInterval: TimeInterval) -> TimeInterval {
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            return 30
        }
        return timeoutInterval
    }
}
