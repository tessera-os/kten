// swift-tools-version: 6.0
import PackageDescription

/// Kten's release version. CI releases it when it names the current
/// release week (RELEASES.md).
let version: String = "26.10.4"

let package = Package(
  name: "Kten",
  platforms: [.iOS(.v16), .macOS(.v13)],
  products: [.library(name: "Kten", targets: ["Kten"])],
  targets: [
    .target(name: "Kten"),
    .testTarget(name: "KtenTests", dependencies: ["Kten"]),
  ],
  swiftLanguageModes: [.v6]
)
