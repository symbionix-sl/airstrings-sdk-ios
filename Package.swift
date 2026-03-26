// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AirStrings",
  platforms: [
    .iOS(.v17),
    .macOS(.v14)
  ],
  products: [
    .library(name: "AirStrings", targets: ["AirStrings"])
  ],
  dependencies: [
    .package(url: "https://github.com/vetrek/SmartNet.git", from: "2.0.1")
  ],
  targets: [
    .target(
      name: "AirStrings",
      dependencies: ["SmartNet"]
    ),
    .testTarget(
      name: "AirStringsTests",
      dependencies: ["AirStrings"]
    )
  ]
)
