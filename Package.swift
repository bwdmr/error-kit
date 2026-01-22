// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "error-kit",
    products: [ .library(name: "ErrorKit", targets: ["ErrorKit"]) ],
    targets: [
        .target(name: "ErrorKit"),
        .testTarget(name: "ErrorKitTests", dependencies: ["ErrorKit"]),
    ]
)
