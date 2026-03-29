import AsyncHTTPClient
import Foundation
import Testing
@testable import TodoistAPI

@Suite("Transport", .serialized)
struct TransportTests {
    @Test("retries network errors and eventually succeeds")
    func retriesNetworkErrorsAndEventuallySucceeds() async throws {
        let state = MockExecutorState()
        await state.enqueue(.failure(HTTPClientError.deadlineExceeded))
        await state.enqueue(.failure(HTTPClientError.remoteConnectionClosed))
        await state.enqueue(.success(statusCode: 200, headers: ["content-type": "application/json"], data: Data("{\"ok\":true}".utf8)))

        let transport = DefaultTodoistTransport(policy: .init()) { request in
            await state.record(request)
            return try await state.nextResponse()
        }
        let response = try await transport.perform(TodoistHTTPRequest(url: URL(string: "https://example.com/tasks")!))

        #expect(response.statusCode == 200)
        #expect(String(data: response.data, encoding: .utf8) == "{\"ok\":true}")

        let requests = await state.requests()
        #expect(requests.count == 3)
    }

    @Test("forces a 30 second timeout on AsyncHTTPClient requests")
    func forcesThirtySecondTimeout() async throws {
        let state = MockExecutorState()
        await state.enqueue(.success(statusCode: 204, data: Data()))

        let transport = DefaultTodoistTransport(policy: .init()) { request in
            await state.record(request)
            return try await state.nextResponse()
        }
        var request = TodoistHTTPRequest(url: URL(string: "https://example.com/tasks")!)
        request.timeoutInterval = 5

        _ = try await transport.perform(request)

        let recorded = try #require(await state.lastRequest())
        #expect(recorded.timeoutInterval == 30)
    }

    @Test("TodoistClient uses injected custom transport")
    func todoistClientUsesInjectedCustomTransport() async throws {
        let transport = MockTransport(actions: [.response(try jsonResponse(taskJSON(defaultTask)))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        let task = try await client.tasks.get("1234")

        #expect(task.id == "1234")

        let recorded = try #require(await transport.lastRequest())
        #expect(recorded.httpMethod == "GET")
        #expect(recorded.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(recorded.url.absoluteString == "https://api.todoist.com/api/v1/tasks/1234")
    }
}

private actor MockExecutorState {
    enum Action {
        case success(statusCode: Int, headers: [String: String] = [:], data: Data)
        case failure(Error)
    }

    private var actions: [Action] = []
    private var recordedRequests: [TodoistHTTPRequest] = []

    func enqueue(_ action: Action) {
        actions.append(action)
    }

    func record(_ request: TodoistHTTPRequest) {
        recordedRequests.append(request)
    }

    func nextAction() -> Action? {
        guard !actions.isEmpty else {
            return nil
        }
        return actions.removeFirst()
    }

    func nextResponse() throws -> TodoistHTTPResponse {
        guard let action = nextAction() else {
            throw HTTPClientError.remoteConnectionClosed
        }

        switch action {
        case let .success(statusCode, headers, data):
            return TodoistHTTPResponse(
                statusCode: statusCode,
                statusText: statusText(for: statusCode),
                headers: headers,
                data: data,
            )
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [TodoistHTTPRequest] {
        recordedRequests
    }

    func lastRequest() -> TodoistHTTPRequest? {
        recordedRequests.last
    }
}
