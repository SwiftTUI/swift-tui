private enum ReducesMotionKey: EnvironmentKey {
  static let defaultValue = false
}

private enum SuppressesProgressKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  package var reducesMotion: Bool {
    get { self[ReducesMotionKey.self] }
    set { self[ReducesMotionKey.self] = newValue }
  }

  package var suppressesProgress: Bool {
    get { self[SuppressesProgressKey.self] }
    set { self[SuppressesProgressKey.self] = newValue }
  }
}
