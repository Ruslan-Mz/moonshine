// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Adapters",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "OmniFocusAdapter", targets: ["OmniFocusAdapter"]),
    .library(name: "SQLiteStore", targets: ["SQLiteStore"]),
  ],
  dependencies: [
    .package(path: "../MoonShineCore"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
  ],
  targets: [
    .target(
      name: "OmniFocusAdapter",
      dependencies: [.product(name: "MoonShineCore", package: "MoonShineCore")]),
    .target(
      name: "SQLiteStore",
      dependencies: [
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ]),
    .testTarget(
      name: "OmniFocusAdapterTests",
      dependencies: [
        "OmniFocusAdapter",
        .product(name: "MoonShineCore", package: "MoonShineCore"),
        .product(name: "MoonShineFixtures", package: "MoonShineCore"),
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
