import Foundation
import Testing

@testable import TodoistAPI

@Suite("Authentication And Uploads")
struct AuthenticationAndUploadsTests {
  @Test("authorization URL matches Todoist OAuth semantics")
  func authorizationURLMatchesTodoistOAuthSemantics() throws {
    let url = try getAuthorizationUrl(
      clientId: "client-123",
      permissions: [TodoistPermission.dataRead.rawValue, TodoistPermission.taskAdd.rawValue],
      state: "state-abc",
    )

    #expect(
      url
        == "https://todoist.com/oauth/authorize?client_id=client-123&scope=data:read,task:add&state=state-abc"
    )
  }

  @Test("token exchange uses auth endpoint and decodes success payload")
  func tokenExchangeUsesAuthEndpointAndDecodesSuccessPayload() async throws {
    let transport = MockTransport(actions: [
      .response(
        try jsonResponse([
          "access_token": "oauth-token",
          "token_type": "Bearer",
        ]))
    ])

    let response = try await getAuthToken(
      AuthTokenRequest(clientId: "client", clientSecret: "secret", code: "auth-code"),
      options: AuthOptions(baseUrl: "https://todoist.com", customTransport: transport),
    )

    #expect(response.accessToken == "oauth-token")
    #expect(response.tokenType == "Bearer")

    let request = try #require(await transport.lastRequest())
    #expect(request.url.absoluteString == "https://todoist.com/oauth/access_token")

    let body = try requestJSONBody(request)
    #expect(body["client_id"] as? String == "client")
    #expect(body["client_secret"] as? String == "secret")
    #expect(body["code"] as? String == "auth-code")
  }

  @Test("revoke and migrate personal token keep TS-compatible auth semantics")
  func revokeAndMigratePersonalTokenKeepCompatibility() async throws {
    let revokeTransport = MockTransport(actions: [.response(textResponse("", statusCode: 200))])
    let revokeSucceeded = try await revokeToken(
      RevokeTokenRequest(clientId: "client", clientSecret: "secret", token: "access-token"),
      options: AuthOptions(baseUrl: "https://api.todoist.com", customTransport: revokeTransport),
    )

    #expect(revokeSucceeded)

    let revokeRequest = try #require(await revokeTransport.lastRequest())
    #expect(revokeRequest.url.absoluteString == "https://api.todoist.com/api/v1/revoke")
    #expect(
      revokeRequest.value(forHTTPHeaderField: "Authorization") == "Basic Y2xpZW50OnNlY3JldA==")

    let revokeBody = try requestJSONBody(revokeRequest)
    #expect(revokeBody["token"] as? String == "access-token")
    #expect(revokeBody["token_type_hint"] as? String == "access_token")

    let migrateTransport = MockTransport(actions: [
      .response(
        try jsonResponse([
          "access_token": "migrated-token",
          "token_type": "Bearer",
          "expires_in": 3600,
        ]))
    ])

    let migrated = try await migratePersonalToken(
      MigratePersonalTokenRequest(
        clientId: "client",
        clientSecret: "secret",
        personalToken: "legacy-token",
        scope: ["data:read", "task:add"],
      ),
      options: AuthOptions(baseUrl: "https://api.todoist.com", customTransport: migrateTransport),
    )

    #expect(migrated.accessToken == "migrated-token")
    #expect(migrated.tokenType == "Bearer")
    #expect(migrated.expiresIn == 3600)

    let migrateRequest = try #require(await migrateTransport.lastRequest())
    #expect(
      migrateRequest.url.absoluteString
        == "https://api.todoist.com/api/v1/access_tokens/migrate_personal_token")

    let migrateBody = try requestJSONBody(migrateRequest)
    #expect(migrateBody["client_id"] as? String == "client")
    #expect(migrateBody["client_secret"] as? String == "secret")
    #expect(migrateBody["personal_token"] as? String == "legacy-token")
    #expect(migrateBody["scope"] as? String == "data:read,task:add")
  }

  @Test("upload validates missing filename for in-memory sources")
  func uploadValidatesMissingFileNameForInMemorySources() async throws {
    let client = TodoistClient(authToken: "secret-token", transport: MockTransport())

    do {
      _ = try await client.uploads.upload(UploadRequest(file: .data(Data("hello".utf8))))
      Issue.record("Expected buffer upload to require a file name")
    } catch let error as TodoistFileValidationError {
      #expect(error.errorDescription == "fileName is required when uploading from a buffer")
    }

    let stream = InputStream(data: Data("hello".utf8))
    do {
      _ = try await client.uploads.upload(UploadRequest(file: .stream(stream)))
      Issue.record("Expected stream upload to require a file name")
    } catch let error as TodoistFileValidationError {
      #expect(error.errorDescription == "fileName is required when uploading from a stream")
    }
  }

  @Test("upload builds multipart request and forwards X-Request-Id")
  func uploadBuildsMultipartRequestAndForwardsRequestID() async throws {
    let transport = MockTransport(actions: [
      .response(try jsonResponse(attachmentJSON(defaultComment.fileAttachment!)))
    ])
    let client = TodoistClient(authToken: "secret-token", transport: transport)

    let attachment = try await client.uploads.upload(
      UploadRequest(
        file: .data(Data("image-bytes".utf8)),
        fileName: "receipt.png",
        projectId: "project-1",
      ),
      requestId: "request-123",
    )

    #expect(attachment.fileName == "file.png")

    let request = try #require(await transport.lastRequest())
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "request-123")

    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.contains("multipart/form-data; boundary="))

    let body = try #require(request.httpBody)
    let bodyString = try #require(String(data: body, encoding: .utf8))
    #expect(bodyString.contains("name=\"projectId\""))
    #expect(bodyString.contains("project-1"))
    #expect(bodyString.contains("filename=\"receipt.png\""))
    #expect(bodyString.contains("image-bytes"))
  }

  @Test("viewAttachment enforces todoist domains and exposes text plus raw bytes")
  func viewAttachmentEnforcesTodoistDomainsAndExposesReadableResponses() async throws {
    let transport = MockTransport(actions: [
      .response(textResponse("hello attachment", headers: ["content-type": "text/plain"]))
    ])
    let client = TodoistClient(authToken: "secret-token", transport: transport)

    let response = try await client.uploads.viewAttachment(
      url: "https://files.todoist.com/user_upload/v2/123/file.txt")
    #expect(response.ok)
    #expect(try await response.text() == "hello attachment")
    #expect(await response.arrayBuffer() == Data("hello attachment".utf8))

    let request = try #require(await transport.lastRequest())
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")

    do {
      _ = try await client.uploads.viewAttachment(url: "https://example.com/file.txt")
      Issue.record("Expected non-Todoist attachment URLs to be rejected")
    } catch let error as TodoistArgumentError {
      #expect(error.message == "Attachment URLs must be on a todoist.com domain")
    }
  }
}
