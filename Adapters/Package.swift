// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Adapters",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "OmniFocusAdapter", targets: ["OmniFocusAdapter"])
  ],
  dependencies: [
    .package(path: "../MoonShineCore")
  ],
  targets: [
    .target(
      name: "OmniFocusAdapter",
      dependencies: [.product(name: "MoonShineCore", package: "MoonShineCore")]),
    .testTarget(
      name: "OmniFocusAdapterTests",
      dependencies: [
        "OmniFocusAdapter",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "MoonShineFixtures", package: "MoonShineCore"),
      ]),
  ]
)
