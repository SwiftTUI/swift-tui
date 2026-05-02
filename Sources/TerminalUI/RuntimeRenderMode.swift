#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// Selects the runtime rendering pipeline used by ``RunLoop``.
public enum RuntimeRenderMode: String, Sendable {
  case sync
  case async
  case asyncNoCancel = "async-no-cancel"
  case asyncNoDrop = "async-no-drop"

  public static let environmentVariableName = "TERMUI_RENDER_MODE"
  public static let defaultMode: Self = .async

  public static func parse(_ rawValue: String?) -> Self {
    guard let rawValue else {
      return defaultMode
    }
    return Self(rawValue: rawValue) ?? defaultMode
  }

  public static func environmentDefault() -> Self {
    parse(environmentValue(named: environmentVariableName))
  }
}

private func environmentValue(named name: String) -> String? {
  unsafe name.withCString { cName in
    guard let rawValue = unsafe getenv(cName) else {
      return nil
    }
    return unsafe String(cString: rawValue)
  }
}
