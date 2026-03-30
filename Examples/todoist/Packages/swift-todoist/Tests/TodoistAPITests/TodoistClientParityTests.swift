import Foundation
import Testing
@testable import TodoistAPI

@Suite("Todoist Client Parity")
struct TodoistClientParityTests {
    @Test("task update maps legacy edge cases to TS-compatible payloads")
    func taskUpdateMapsLegacyEdgeCases() async throws {
        let transport = MockTransport(actions: [.response(try jsonResponse(taskJSON(defaultTask)))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        _ = try await client.tasks.update(
            "1234",
            TaskUpdateRequest(
                content: "Read docs",
                order: 7,
                dueString: .null,
                deadlineDate: .null,
                isUncompletable: true,
            ),
        )

        let request = try #require(await transport.lastRequest())
        let body = try requestJSONBody(request)

        #expect(body["content"] as? String == "* Read docs")
        #expect(body["child_order"] as? Int == 7)
        #expect(body["due_string"] as? String == "no date")
        #expect(body["deadline_date"] is NSNull)
        #expect(body["is_uncompletable"] as? Bool == true)
    }

    @Test("moveTasks generates one sync command per task and filters returned items by id")
    func moveTasksGeneratesUniqueCommandsAndFiltersResults() async throws {
        let movedTaskA = Task(
            id: "task-1",
            userId: defaultTask.userId,
            projectId: defaultTask.projectId,
            sectionId: defaultTask.sectionId,
            parentId: defaultTask.parentId,
            assignedByUid: defaultTask.assignedByUid,
            responsibleUid: defaultTask.responsibleUid,
            labels: defaultTask.labels,
            deadline: defaultTask.deadline,
            duration: defaultTask.duration,
            checked: defaultTask.checked,
            isDeleted: defaultTask.isDeleted,
            addedAt: defaultTask.addedAt,
            completedAt: defaultTask.completedAt,
            updatedAt: defaultTask.updatedAt,
            due: defaultTask.due,
            priority: defaultTask.priority,
            childOrder: defaultTask.childOrder,
            content: defaultTask.content,
            description: defaultTask.description,
            dayOrder: defaultTask.dayOrder,
            isCollapsed: defaultTask.isCollapsed,
            isUncompletable: defaultTask.isUncompletable,
            order: defaultTask.order,
            recurring: defaultTask.recurring,
            hasSubTasks: defaultTask.hasSubTasks,
            url: defaultTask.url,
        )
        let movedTaskB = Task(
            id: "task-2",
            userId: defaultTask.userId,
            projectId: defaultTask.projectId,
            sectionId: defaultTask.sectionId,
            parentId: defaultTask.parentId,
            assignedByUid: defaultTask.assignedByUid,
            responsibleUid: defaultTask.responsibleUid,
            labels: defaultTask.labels,
            deadline: defaultTask.deadline,
            duration: defaultTask.duration,
            checked: defaultTask.checked,
            isDeleted: defaultTask.isDeleted,
            addedAt: defaultTask.addedAt,
            completedAt: defaultTask.completedAt,
            updatedAt: defaultTask.updatedAt,
            due: defaultTask.due,
            priority: defaultTask.priority,
            childOrder: defaultTask.childOrder,
            content: defaultTask.content,
            description: defaultTask.description,
            dayOrder: defaultTask.dayOrder,
            isCollapsed: defaultTask.isCollapsed,
            isUncompletable: defaultTask.isUncompletable,
            order: defaultTask.order,
            recurring: defaultTask.recurring,
            hasSubTasks: defaultTask.hasSubTasks,
            url: defaultTask.url,
        )

        let syncResponse = try jsonResponse([
            "sync_token": "*",
            "sync_status": ["command-a": "ok", "command-b": "ok"],
            "items": [taskJSON(movedTaskA), taskJSON(defaultTask), taskJSON(movedTaskB)],
        ])
        let transport = MockTransport(actions: [.response(syncResponse)])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        let tasks = try await client.tasks.move(["task-1", "task-2"], to: .project("project-9"))

        #expect(tasks.map(\.id) == ["task-1", "task-2"])

        let request = try #require(await transport.lastRequest())
        let body = try requestJSONBody(request)
        let commands = try #require(body["commands"] as? [[String: Any]])
        #expect(commands.count == 2)

        let firstUUID = try #require(commands.first?["uuid"] as? String)
        let secondUUID = try #require(commands.last?["uuid"] as? String)
        #expect(firstUUID.isEmpty == false)
        #expect(secondUUID.isEmpty == false)
        #expect(firstUUID != secondUUID)

        let firstArgs = try #require(commands.first?["args"] as? [String: Any])
        #expect(firstArgs["id"] as? String == "task-1")
        #expect(firstArgs["project_id"] as? String == "project-9")
    }

    @Test("moveTasks surfaces sync errors from sync_status")
    func moveTasksSurfacesSyncErrors() async throws {
        let transport = MockTransport(actions: [.response(try jsonResponse([
            "sync_token": "*",
            "sync_status": [
                "command-1": [
                    "error": "Project not found",
                    "http_code": 404,
                ],
            ],
        ]))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        do {
            _ = try await client.tasks.move(["task-1"], to: .project("missing-project"))
            Issue.record("Expected moveTasks to throw")
        } catch let error as TodoistRequestError {
            #expect(error.message == "Project not found")
            #expect(error.httpStatusCode == 404)
        }
    }

    @Test("moveTasks throws not found when sync returns no matching tasks")
    func moveTasksThrowsWhenSyncReturnsNoMatchingTasks() async throws {
        let transport = MockTransport(actions: [.response(try jsonResponse([
            "sync_token": "*",
            "sync_status": ["command-1": "ok"],
            "items": [taskJSON(defaultTask)],
        ]))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        do {
            _ = try await client.tasks.move(["missing-task"], to: .section("section-1"))
            Issue.record("Expected moveTasks to throw")
        } catch let error as TodoistRequestError {
            #expect(error.message == "Tasks not found")
            #expect(error.httpStatusCode == 404)
        }
    }

    @Test("time-based reminder lookup guides callers to location endpoint")
    func timeBasedReminderLookupGuidesToLocationEndpoint() async throws {
        let transport = MockTransport(actions: [.response(textResponse("{\"error\":\"Not Found\"}", statusCode: 404))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        do {
            _ = try await client.reminders.get("location-reminder-id")
            Issue.record("Expected get reminder to throw")
        } catch let error as TodoistArgumentError {
            #expect(error.message.contains("use getLocationReminder instead"))
        }
    }

    @Test("absolute reminder update validates endpoint payload")
    func absoluteReminderUpdateValidatesEndpointPayload() async throws {
        let transport = MockTransport(actions: [.response(try jsonResponse(reminderJSON(defaultAbsoluteReminder)))])
        let client = TodoistClient(authToken: "secret-token", transport: transport)

        let reminder = try await client.reminders.update(
            "6XGgmFQrx44wfGHr",
            AbsoluteReminderUpdateRequest(
                due: defaultDue,
                notifyUid: "42",
                isUrgent: false,
            ),
        )

        #expect(reminder.id == "6XGgmFQrx44wfGHr")

        let request = try #require(await transport.lastRequest())
        let body = try requestJSONBody(request)
        #expect(body["reminder_type"] as? String == "absolute")
        #expect(body["notify_uid"] as? String == "42")
        #expect(body["is_urgent"] as? Bool == false)
        let due = try #require(body["due"] as? [String: Any])
        #expect(due["string"] as? String == defaultDue.string)
    }

    @Test("query serialization keeps arrays as JSON strings and bools as raw values")
    func querySerializationMatchesTypeScriptSemantics() async throws {
        let transport = MockTransport(actions: [.response(textResponse("", statusCode: 200))])
        let httpClient = TodoistHTTPClient(
            transport: transport,
            baseURL: "https://api.todoist.com/api/v1/",
            authToken: "secret-token",
        )

        _ = try await httpClient.requestVoid(
            method: .get,
            path: "tasks",
            payload: [
                "ids": ["task-1", "task-2"],
                "isDeleted": true,
                "limit": 20,
            ],
        )

        let request = try #require(await transport.allRequests().first)
        let items = queryItems(request)

        #expect(items["ids"] == "[\"task-1\",\"task-2\"]")
        #expect(items["is_deleted"] == "true")
        #expect(items["limit"] == "20")
    }

    @Test("task decoding defaults missing is_uncompletable to false like the TS client")
    func taskDecodingDefaultsMissingIsUncompletableToFalse() throws {
        var liveLikeTask = taskJSON(defaultTask)
        liveLikeTask["is_uncompletable"] = nil

        let data = try JSONSerialization.data(withJSONObject: [
            "results": [liveLikeTask],
        ])

        let page = try JSONDecoder.default.decode(TodoistPage<Task>.self, from: data)

        #expect(page.results.count == 1)
        #expect(page.results[0].isUncompletable == false)
    }
}
