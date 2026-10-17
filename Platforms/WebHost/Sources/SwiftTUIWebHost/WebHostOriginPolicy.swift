import Foundation

package struct WebHostOriginPolicy: Equatable, Sendable {
  package var allowedHosts: Set<String>
  package var allowMissingOrigin: Bool
  private var allowsNetworkAddresses: Bool

  package init(
    bind: String,
    allowMissingOrigin: Bool = true
  ) {
    allowedHosts = [bind.lowercased(), "127.0.0.1", "localhost"]
    allowsNetworkAddresses = bind == "0.0.0.0"
    self.allowMissingOrigin = allowMissingOrigin
  }

  package func allows(
    origin: String?,
    port: Int,
    requestAuthority: String? = nil
  ) -> Bool {
    guard let origin, !origin.isEmpty else {
      return allowMissingOrigin
    }
    guard let url = URL(string: origin),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = url.host?.lowercased(), !host.isEmpty,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.isEmpty || url.path == "/"
    else {
      return false
    }
    guard (url.port ?? (scheme == "https" ? 443 : 80)) == port else { return false }
    if allowedHosts.contains(host) { return true }
    guard allowsNetworkAddresses, Self.isIPv4Address(host) else { return false }
    // A wildcard listener can be reached through any interface address. The
    // route additionally checks the origin against the request's authority.
    if let requestAuthority {
      guard let authority = URL(string: "http://" + requestAuthority),
        authority.host?.lowercased() == host, (authority.port ?? 80) == port,
        authority.user == nil, authority.password == nil,
        authority.path.isEmpty, authority.query == nil, authority.fragment == nil
      else { return false }
    }
    return true
  }
  private static func isIPv4Address(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 4
      && parts.allSatisfy {
        guard let byte = UInt8($0) else { return false }
        return String(byte) == $0
      }
  }

}
