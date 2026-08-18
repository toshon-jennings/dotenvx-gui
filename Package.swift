// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "DotenvxGUI",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "DotenvxGUI", targets: ["DotenvxGUI"])
  ],
  targets: [
    .executableTarget(
      name: "DotenvxGUI",
      path: "Sources/DotenvxGUI"
    ),
    .testTarget(
      name: "DotenvxGUITests",
      dependencies: ["DotenvxGUI"],
      path: "Tests/DotenvxGUITests"
    ),
  ]
)
