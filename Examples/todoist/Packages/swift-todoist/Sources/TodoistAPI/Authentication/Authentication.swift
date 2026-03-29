import Foundation

public enum TodoistPermission: String, Sendable {
    case taskAdd = "task:add"
    case dataRead = "data:read"
    case dataReadWrite = "data:read_write"
    case dataDelete = "data:delete"
    case projectDelete = "project:delete"
    case backupsRead = "backups:read"
}

public let PERMISSIONS: [String] = [
    "task:add",
    "data:read",
    "data:read_write",
    "data:delete",
    "project:delete",
    "backups:read",
]

public struct AuthOptions {
    public let baseUrl: String?
    public let customTransport: Transport?

    public init(baseUrl: String? = nil, customTransport: Transport? = nil) {
        self.baseUrl = baseUrl
        self.customTransport = customTransport
    }
}

public struct AuthTokenRequest: Sendable {
    public let clientId: String
    public let clientSecret: String
    public let code: String

    public init(clientId: String, clientSecret: String, code: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.code = code
    }
}

public struct RevokeTokenRequest: Sendable {
    public let clientId: String
    public let clientSecret: String
    public let token: String

    public init(clientId: String, clientSecret: String, token: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.token = token
    }
}

public struct MigratePersonalTokenRequest: Sendable {
    public let clientId: String
    public let clientSecret: String
    public let personalToken: String
    public let scope: [String]

    public init(
        clientId: String,
        clientSecret: String,
        personalToken: String,
        scope: [String],
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.personalToken = personalToken
        self.scope = scope
    }
}

public struct AuthTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String

    public init(accessToken: String, tokenType: String) {
        self.accessToken = accessToken
        self.tokenType = tokenType
    }
}

public struct MigratePersonalTokenResponse: Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int

    public init(accessToken: String, tokenType: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }
}

private struct OAuthTokenResponse: Codable {
    let accessToken: String?
    let tokenType: String?
    let access_token: String?
    let token_type: String?
}

private struct OAuthTokenResponseV1: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
}

public func getAuthStateParameter() -> String {
    UUID().uuidString
}

public func getAuthorizationUrl(
    clientId: String,
    permissions: [String],
    state: String,
    baseUrl: String? = nil,
) throws -> String {
    guard !permissions.isEmpty else {
        throw TodoistArgumentError("At least one scope value should be passed for permissions.")
    }

    let base = (baseUrl ?? todoistAuthURL).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let normalized = "\(base)/oauth/"
    let scope = permissions.joined(separator: ",")
    return "\(normalized)authorize?client_id=\(clientId)&scope=\(scope)&state=\(state)"
}

public func getAuthToken(_ args: AuthTokenRequest, options: AuthOptions? = nil) async throws -> AuthTokenResponse {
    let transport = options?.customTransport ?? DefaultTodoistTransport()
    let base = options?.baseUrl ?? todoistAuthURL
    let client = TodoistHTTPClient(transport: transport, baseURL: "\(base)/oauth/", authToken: nil)

    do {
        let response: (TodoistHTTPResponse, OAuthTokenResponse) = try await client.request(
            method: .post,
            path: "access_token",
            payload: [
                "clientId": args.clientId,
                "clientSecret": args.clientSecret,
                "code": args.code,
            ],
            includeRequestIdForSync: true,
            decoder: .default,
        )

        let payload = response.1
        let token = payload.accessToken ?? payload.access_token
        guard let token, !token.isEmpty else {
            throw TodoistRequestError(
                "Authentication token exchange failed.",
                httpStatusCode: response.0.statusCode,
                responseData: response.0.data,
            )
        }

        let tokenType = payload.tokenType ?? payload.token_type ?? "Bearer"
        return AuthTokenResponse(accessToken: token, tokenType: tokenType)
    } catch {
        if let requestError = error as? TodoistRequestError {
            throw TodoistRequestError(
                "Authentication token exchange failed.",
                httpStatusCode: requestError.httpStatusCode,
                responseData: requestError.responseData,
            )
        }
        throw TodoistRequestError("Authentication token exchange failed.")
    }
}

public func revokeToken(_ args: RevokeTokenRequest, options: AuthOptions? = nil) async throws -> Bool {
    let transport = options?.customTransport ?? DefaultTodoistTransport()
    let credentials = "\(args.clientId):\(args.clientSecret)"
    guard let token = credentials.data(using: .utf8)?.base64EncodedString() else {
        throw TodoistArgumentError("Invalid client credentials.")
    }

    let client = TodoistHTTPClient(
        transport: transport,
        baseURL: getSyncBaseURI(domainBase: options?.baseUrl ?? todoistBaseURL),
        authToken: nil,
    )

    _ = try await client.requestVoid(
        method: .post,
        path: "revoke",
        payload: [
            "token": args.token,
            "token_type_hint": "access_token",
        ],
        includeRequestIdForSync: true,
        customHeaders: ["Authorization": "Basic \(token)"],
    )
    return true
}

public func migratePersonalToken(
    _ args: MigratePersonalTokenRequest,
    options: AuthOptions? = nil,
) async throws -> MigratePersonalTokenResponse {
    let transport = options?.customTransport ?? DefaultTodoistTransport()
    let client = TodoistHTTPClient(
        transport: transport,
        baseURL: getSyncBaseURI(domainBase: options?.baseUrl ?? todoistBaseURL),
        authToken: nil,
    )

    do {
        let response: (TodoistHTTPResponse, OAuthTokenResponseV1) = try await client.request(
            method: .post,
            path: "access_tokens/migrate_personal_token",
            payload: [
                "client_id": args.clientId,
                "client_secret": args.clientSecret,
                "personal_token": args.personalToken,
                "scope": args.scope.joined(separator: ","),
            ],
            decoder: .default,
        )
        let responseData = response.1
        guard let expiresIn = responseData.expiresIn else {
            throw TodoistRequestError(
                "Personal token migration failed.",
                httpStatusCode: response.0.statusCode,
                responseData: response.0.data,
            )
        }
        return MigratePersonalTokenResponse(
            accessToken: responseData.accessToken,
            tokenType: responseData.tokenType,
            expiresIn: expiresIn,
        )
    } catch {
        if let requestError = error as? TodoistRequestError {
            throw TodoistRequestError(
                "Personal token migration failed.",
                httpStatusCode: requestError.httpStatusCode,
                responseData: requestError.responseData,
            )
        }
        throw TodoistRequestError("Personal token migration failed.")
    }
}
