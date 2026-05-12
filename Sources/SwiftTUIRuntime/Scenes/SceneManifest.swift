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
  public let defaultSceneID: WindowIdentifier
  public let scenes: [SceneDescriptor]

  public init(
    defaultSceneID: WindowIdentifier,
    scenes: [SceneDescriptor]
  ) {
    self.defaultSceneID = defaultSceneID
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
  let defaultSceneID = descriptors.first?.id ?? WindowIdentifier("window")

  return SceneManifest(
    defaultSceneID: defaultSceneID,
    scenes: descriptors
  )
}

extension SceneManifest {
  @_spi(Runners) public var jsonString: String {
    let scenesJSON = scenes.map(\.jsonString).joined(separator: ",")
    return """
      {"defaultSceneID":"\(escapedJSONString(defaultSceneID.rawValue))","scenes":[\(scenesJSON)]}
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
  var escaped = ""
  escaped.reserveCapacity(text.count)

  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x08:
      escaped += "\\b"
    case 0x09:
      escaped += "\\t"
    case 0x0A:
      escaped += "\\n"
    case 0x0C:
      escaped += "\\f"
    case 0x0D:
      escaped += "\\r"
    case 0x22:
      escaped += "\\\""
    case 0x5C:
      escaped += "\\\\"
    case 0x00...0x1F:
      let hex = String(scalar.value, radix: 16, uppercase: true)
      escaped += "\\u"
      escaped += String(repeating: "0", count: max(0, 4 - hex.count))
      escaped += hex
    default:
      escaped.unicodeScalars.append(scalar)
    }
  }

  return escaped
}
