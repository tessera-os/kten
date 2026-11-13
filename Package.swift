// swift-tools-version: 6.0
import PackageDescription

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
