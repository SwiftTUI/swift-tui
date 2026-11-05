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

  private enum CodingKeys: String, CodingKey { case id, title, isDefault }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(WindowIdentifier.self, forKey: .id),
      title: try container.decodeIfPresent(String.self, forKey: .title),
      isDefault: try container.contains(.isDefault)
        ? container.decode(Bool.self, forKey: .isDefault) : false)
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
    let selected =
      defaultSceneID.flatMap { requested in
        scenes.first(where: { $0.id == requested })?.id
      } ?? scenes.first(where: \.isDefault)?.id ?? scenes.first?.id
    self.defaultSceneID = selected
    self.scenes = scenes.map {
      SceneDescriptor(id: $0.id, title: $0.title, isDefault: $0.id == selected)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case defaultSceneId, defaultSceneID, scenes
  }

  public init(from decoder: any Decoder) throws {
    let scenes: [SceneDescriptor]
    let explicit: WindowIdentifier?
    if let array = try? decoder.singleValueContainer().decode([SceneDescriptor].self) {
      scenes = array
      explicit = nil
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      scenes = try container.decode([SceneDescriptor].self, forKey: .scenes)
      let canonical = try container.decodeIfPresent(WindowIdentifier.self, forKey: .defaultSceneId)
      let legacy = try container.decodeIfPresent(WindowIdentifier.self, forKey: .defaultSceneID)
      if let canonical, let legacy, canonical != legacy {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath, debugDescription: "conflicting scene defaults"))
      }
      explicit = canonical ?? legacy
    }
    guard Set(scenes.map(\.id)).count == scenes.count,
      scenes.allSatisfy({ !$0.id.rawValue.isEmpty }),
      explicit.map({ id in scenes.contains(where: { $0.id == id }) }) ?? true,
      explicit != nil || scenes.filter(\.isDefault).count <= 1
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription:
            "scene catalog has duplicate IDs, an unknown default or multiple default flags"))
    }
    self.init(defaultSceneID: explicit, scenes: scenes)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(defaultSceneID, forKey: .defaultSceneId)
    try container.encode(scenes, forKey: .scenes)
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
  SceneManifest(
    defaultSceneID: nil,
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
