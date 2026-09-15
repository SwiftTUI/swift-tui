#!/usr/bin/env bash
# Build external packages using only each supported product dependency.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
scratch="${repo_root}/.build/public-import-consumers"
mkdir -p "${scratch}"

for product in SwiftTUIViews SwiftTUIRuntime; do
  consumer="${scratch}/${product}"
  mkdir -p "${consumer}/Sources/Consumer"
  # JSON string quoting also handles spaces/backslashes in the local package path.
  bun -e '
    const [root, product, consumer] = process.argv.slice(1);
    await Bun.write(`${consumer}/Package.swift`, `// swift-tools-version: 6.4
import PackageDescription
let package = Package(
  name: "ImportConsumer",
  platforms: [.macOS(.v15), .iOS(.v18)],
  dependencies: [.package(name: "swift-tui", path: ${JSON.stringify(root)})],
  targets: [.executableTarget(
    name: "Consumer",
    dependencies: [.product(name: ${JSON.stringify(product)}, package: "swift-tui")],
    swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("InternalImportsByDefault"), .enableUpcomingFeature("MemberImportVisibility")]
  )]
)
`);
  ' "${repo_root}" "${product}" "${consumer}"
  cp "${repo_root}/Scripts/data/public-import-consumers/${product}.swift" \
    "${consumer}/Sources/Consumer/Consumer.swift"
  echo "[check_public_import_consumers] Building ${product}-only consumer"
  # Separate scratch directories prevent unrelated products from making an
  # accidental import succeed. Never inherit the producer's package identity.
  swiftly run swift build --package-path "${consumer}" --jobs "${SWIFTTUI_PUBLIC_API_SWIFT_JOBS:-4}"
done
echo "[check_public_import_consumers] ok"
