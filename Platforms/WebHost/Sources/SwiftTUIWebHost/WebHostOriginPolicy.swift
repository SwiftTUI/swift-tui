import Foundation

package struct WebHostOriginPolicy: Equatable, Sendable {
  package var allowedHosts: Set<String>
  package var allowMissingOrigin: Bool

  package init(
    bind: String,
    allowMissingOrigin: Bool = true
  ) {
    var hosts: Set<String> = [bind, "127.0.0.1", "localhost"]
    if bind == "0.0.0.0" {
      hosts.insert("localhost")
      hosts.insert("127.0.0.1")
    }
    allowedHosts = hosts
    self.allowMissingOrigin = allowMissingOrigin
  }

  package func allows(
    origin: String?,
    port: Int
  ) -> Bool {
    guard let origin, !origin.isEmpty else {
      return allowMissingOrigin
    }
    guard let url = URL(string: origin),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = url.host?.lowercased(),
      allowedHosts.contains(host)
    else {
      return false
    }
    return url.port == nil || url.port == port
  }
}
