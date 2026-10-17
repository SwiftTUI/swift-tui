/// The encoded path of a local file URL. Remote authorities are deliberately
/// unsupported; their path must never be mistaken for a local filesystem path.
package func localFileURLPathComponent(_ value: String) -> String? {
  guard value.prefix(7).lowercased() == "file://" else { return nil }
  let suffix = value.dropFirst(7)
  guard let slash = suffix.firstIndex(of: "/") else { return nil }
  let authority = suffix[..<slash]
  guard authority.isEmpty || authority.lowercased() == "localhost" else { return nil }
  let path = String(suffix[slash...])
  guard !path.utf8.contains(0) else { return nil }
  return path
}
