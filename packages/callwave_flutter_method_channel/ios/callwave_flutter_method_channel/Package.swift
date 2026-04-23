// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "callwave_flutter_method_channel",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(
      name: "callwave-flutter-method-channel",
      targets: ["callwave_flutter_method_channel"]
    )
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "callwave_flutter_method_channel",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ],
      linkerSettings: [
        .linkedFramework("AVFAudio"),
        .linkedFramework("CallKit"),
        .linkedFramework("UIKit"),
        .linkedFramework("UserNotifications")
      ]
    )
  ]
)
