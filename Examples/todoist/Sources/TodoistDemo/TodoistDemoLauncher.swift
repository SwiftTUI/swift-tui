import Foundation
import Observation

struct TodoistDemoPaths: Sendable {
  let directoryURL: URL
  let databaseURL: URL
  let apiTokenURL: URL
}

enum TodoistDemoConfiguration {
  static func paths() throws -> TodoistDemoPaths {
    let appSupport =
      try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )

    let directoryURL =
      appSupport
      .appendingPathComponent("swift-terminal-ui")
      .appendingPathComponent("todoist-demo")

    return TodoistDemoPaths(
      directoryURL: directoryURL,
      databaseURL: directoryURL.appendingPathComponent("todoist.sqlite3"),
      apiTokenURL: directoryURL.appendingPathComponent("todoist-api-token.txt")
    )
  }

  static func environmentAuthToken() -> String? {
    normalizedToken(ProcessInfo.processInfo.environment["TODOIST_API_TOKEN"])
  }

  static func storedAuthToken() throws -> String? {
    let apiTokenURL = try paths().apiTokenURL
    guard FileManager.default.fileExists(atPath: apiTokenURL.path) else {
      return nil
    }

    let rawToken = try String(contentsOf: apiTokenURL, encoding: .utf8)
    return normalizedToken(rawToken)
  }

  static func resolvedAuthToken() throws -> String? {
    if let environmentAuthToken = Self.environmentAuthToken() {
      return environmentAuthToken
    }
    return try Self.storedAuthToken()
  }

  static func saveAuthToken(_ token: String) throws {
    let paths = try paths()
    let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    try FileManager.default.createDirectory(
      at: paths.directoryURL,
      withIntermediateDirectories: true
    )
    try normalizedToken.write(to: paths.apiTokenURL, atomically: true, encoding: .utf8)
  }

  private static func normalizedToken(_ token: String?) -> String? {
    guard let token else {
      return nil
    }

    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

enum TodoistDemoPhase: Sendable {
  case setup
  case initializing
  case ready
}

@MainActor
@Observable
final class TodoistDemoLauncher: Sendable {
  @ObservationIgnored private let environmentToken: String?

  var phase: TodoistDemoPhase
  var model: TodoistAppModel?
  var apiTokenInput: String
  var databasePath: String
  var setupStatusMessage: String

  init() throws {
    let paths = try TodoistDemoConfiguration.paths()
    environmentToken = TodoistDemoConfiguration.environmentAuthToken()
    databasePath = paths.databaseURL.path

    if let token = environmentToken {
      apiTokenInput = token
      do {
        model = try TodoistAppModel.live(authTokenOverride: token)
        phase = .ready
        setupStatusMessage = "Using TODOIST_API_TOKEN from the environment."
      } catch {
        model = nil
        phase = .setup
        setupStatusMessage = error.localizedDescription
      }
    } else if let token = try TodoistDemoConfiguration.storedAuthToken() {
      apiTokenInput = token
      do {
        model = try TodoistAppModel.live(authTokenOverride: token)
        phase = .ready
        setupStatusMessage = "Using the saved Todoist API token."
      } catch {
        model = nil
        phase = .setup
        setupStatusMessage = error.localizedDescription
      }
    } else {
      model = nil
      apiTokenInput = ""
      phase = .setup
      setupStatusMessage =
        "Enter your Todoist API token to initialize the database and start syncing."
    }
  }

  var isInitializing: Bool {
    phase == .initializing
  }

  var canInitialize: Bool {
    !apiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isInitializing
  }

  func requestInitialize() {
    Task { @MainActor in
      await initialize(persistToken: true)
    }
  }
}

extension TodoistDemoLauncher {
  private func initialize(persistToken: Bool) async {
    let trimmedToken = apiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedToken.isEmpty else {
      phase = .setup
      setupStatusMessage =
        "A Todoist API token is required before the demo can initialize its database."
      return
    }

    phase = .initializing
    setupStatusMessage = "Initializing the local Todoist database..."

    do {
      if persistToken && environmentToken == nil {
        try TodoistDemoConfiguration.saveAuthToken(trimmedToken)
      }

      model = try TodoistAppModel.live(authTokenOverride: trimmedToken)
      phase = .ready
      setupStatusMessage = "Local cache initialized."
    } catch {
      model = nil
      phase = .setup
      setupStatusMessage = error.localizedDescription
    }
  }
}
