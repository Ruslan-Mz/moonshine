// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MoonShineCore",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "MoonShineCore", targets: ["MoonShineCore"]),
    .library(name: "MoonShineFixtures", targets: ["MoonShineFixtures"]),
  ],
  targets: [
    .target(name: "MoonShineCore"),
    .target(name: "MoonShineFixtures", dependencies: ["MoonShineCore"]),
    .testTarget(name: "MoonShineCoreTests", dependencies: ["MoonShineCore", "MoonShineFixtures"]),
    .testTarget(
      name: "MoonShineFixturesTests", dependencies: ["MoonShineCore", "MoonShineFixtures"]),
  ]
)
