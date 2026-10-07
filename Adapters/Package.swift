// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Adapters",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "OmniFocusAdapter", targets: ["OmniFocusAdapter"]),
    .library(name: "ObsidianAdapter", targets: ["ObsidianAdapter"]),
    .library(name: "SQLiteStore", targets: ["SQLiteStore"]),
  ],
  dependencies: [
    .package(path: "../MoonShineCore"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
  ],
  targets: [
    .target(
      name: "OmniFocusAdapter",
      dependencies: [.product(name: "MoonShineCore", package: "MoonShineCore")]),
    .target(
      name: "ObsidianAdapter",
      dependencies: [
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "Yams", package: "Yams"),
      ]),
    .target(
      name: "SQLiteStore",
      dependencies: [
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]),
    // Measures the live import and checks the vault; prints counts and timings only.
    .executableTarget(
      name: "moonshine-import",
      dependencies: [
        "OmniFocusAdapter", "ObsidianAdapter", "SQLiteStore",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
      ]),
    .testTarget(
      name: "OmniFocusAdapterTests",
      dependencies: [
        "OmniFocusAdapter",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "MoonShineFixtures", package: "MoonShineCore"),
      ]),
    .testTarget(
      name: "ObsidianAdapterTests",
      dependencies: [
        "ObsidianAdapter",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
      ]),
    .testTarget(
      name: "SQLiteStoreTests",
      dependencies: [
        "SQLiteStore",
        "OmniFocusAdapter",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "MoonShineFixtures", package: "MoonShineCore"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]),
  ]
)
