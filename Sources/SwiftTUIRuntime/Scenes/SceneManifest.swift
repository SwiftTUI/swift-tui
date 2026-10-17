import SwiftTUICore

public struct SceneDescriptor: Codable, Hashable, Sendable {
  public let id: WindowIdentifier
  public let title: String?
  public let isDefault: Bool

  public init(
    id: WindowIdentifier,
    title: String?,
    isDefault: Bool
  ) {
    self.id = id
    self.title = title
    self.isDefault = isDefault
  }
}

public struct SceneManifest: Codable, Sendable {
  /// The declared default, or nil when the app has no window scenes.
  public let defaultSceneID: WindowIdentifier?
  public let scenes: [SceneDescriptor]

  public init(
    defaultSceneID: WindowIdentifier?,
    scenes: [SceneDescriptor]
  ) {
    self.defaultSceneID =
      defaultSceneID.flatMap { requested in
        scenes.first(where: { $0.id == requested })?.id
      } ?? scenes.first?.id
    self.scenes = scenes
  }

  @MainActor
  public init<A: App>(for app: A) {
    self = sceneManifest(
      from: collectWindowSceneDescriptors(from: app.body)
    )
  }
}

package func sceneManifest(
  from descriptors: [SceneDescriptor]
) -> SceneManifest {
  let defaultSceneID = descriptors.first?.id

  return SceneManifest(
    defaultSceneID: defaultSceneID,
    scenes: descriptors
  )
}

extension SceneManifest {
  @_spi(Runners) public var jsonString: String {
    let scenesJSON = scenes.map(\.jsonString).joined(separator: ",")
    let defaultJSON = defaultSceneID.map { "\"" + escapedJSONString($0.rawValue) + "\"" } ?? "null"
    return """
      {"defaultSceneID":\(defaultJSON),"scenes":[\(scenesJSON)]}
      """
  }
}

extension SceneDescriptor {
  @_spi(Runners) public var jsonString: String {
    let titleValue =
      if let title {
        "\"\(escapedJSONString(title))\""
      } else {
        "null"
      }

    return """
      {"id":"\(escapedJSONString(id.rawValue))","title":\(titleValue),"isDefault":\(isDefault ? "true" : "false")}
      """
  }
}

private func escapedJSONString(
  _ text: String
) -> String {
  JSONStringEncoding.contents(text)
}
