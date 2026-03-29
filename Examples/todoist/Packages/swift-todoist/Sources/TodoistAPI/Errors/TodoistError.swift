import Foundation

public struct TodoistRequestError: LocalizedError {
    public let message: String
    public let httpStatusCode: Int?
    public let responseData: Data?

    public init(_ message: String, httpStatusCode: Int? = nil, responseData: Data? = nil) {
        self.message = message
        self.httpStatusCode = httpStatusCode
        self.responseData = responseData
    }

    public var errorDescription: String? {
        message
    }

    public var isAuthenticationError: Bool {
        guard let status = httpStatusCode else {
            return false
        }
        return status == 401 || status == 403
    }
}

public struct TodoistArgumentError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public enum TodoistFileValidationError: LocalizedError {
    case fileNameRequired(transport: String)
    case emptyFile

    public var errorDescription: String? {
        switch self {
        case let .fileNameRequired(transport):
            return "fileName is required when uploading from a \(transport)"
        case .emptyFile:
            return "File data is empty"
        }
    }
}
