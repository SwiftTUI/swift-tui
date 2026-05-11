public import Observation
import SwiftTUI

public struct SwiftUIHostSceneDescriptor: Identifiable, Hashable, Sendable {
  public var id: WindowIdentifier
  public var title: String?
  public var isDefault: Bool

  public init(
    id: WindowIdentifier,
    title: String? = nil,
    isDefault: Bool = false
  ) {
    self.id = id
    self.title = title
    self.isDefault = isDefault
  }

  init(_ descriptor: SceneDescriptor) {
    self.init(
      id: descriptor.id,
      title: descriptor.title,
      isDefault: descriptor.isDefault
    )
  }
}

@MainActor
@Observable
public final class SwiftUIHostAppState<A: SwiftTUI.App> {
  public let scenes: [SwiftUIHostSceneDescriptor]

  public private(set) var selectedSceneID: WindowIdentifier
  public private(set) var style: SwiftUIHostTerminalStyle {
    didSet {
      applyStyleToHosts()
    }
  }
  public private(set) var isRunning = false

  @ObservationIgnored
  private var hosts: [WindowIdentifier: SwiftUIHostSceneHost] = [:]

  public init(
    app: A,
    selectedSceneID: WindowIdentifier? = nil,
    style: SwiftUIHostTerminalStyle = .default
  ) throws {
    let manifest = SceneManifest(for: app)
    guard !manifest.scenes.isEmpty else {
      throw AppLaunchError.noScenes
    }

    scenes = manifest.scenes.map(SwiftUIHostSceneDescriptor.init)
    self.style = style

    let defaultSceneID = manifest.defaultSceneID
    self.selectedSceneID =
      selectedSceneID.flatMap { requestedID in
        manifest.scenes.contains(where: { $0.id == requestedID })
          ? requestedID
          : nil
      } ?? defaultSceneID

    for descriptor in scenes {
      let host = try SwiftUIHostSceneHost(
        app: app,
        descriptor: descriptor,
        style: style
      )
      hosts[descriptor.id] = host
    }
  }

  public func selectScene(_ sceneID: WindowIdentifier) {
    guard hosts[sceneID] != nil else {
      return
    }
    selectedSceneID = sceneID
  }

  public func setStyle(_ style: SwiftUIHostTerminalStyle) {
    self.style = style
  }

  public func start() {
    guard !isRunning else {
      return
    }

    isRunning = true
    for host in hosts.values {
      host.start()
    }
  }

  public func stop() {
    for host in hosts.values {
      host.stop()
    }
    isRunning = false
  }

  func sceneHost(
    for sceneID: WindowIdentifier
  ) -> SwiftUIHostSceneHost? {
    hosts[sceneID]
  }

  var currentSceneHost: SwiftUIHostSceneHost? {
    hosts[selectedSceneID]
  }

  private func applyStyleToHosts() {
    guard !hosts.isEmpty else {
      return
    }

    for host in hosts.values {
      host.apply(style: style)
    }
  }
}
