// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AudioEffectsSDK",
	products: [
		.library(
			name: "AudioEffectsSDKPackage",
			targets: ["AudioEffectsSDKPackage"]),
	],
	dependencies: [
	],
	targets: [
		.target(name: "AudioEffectsSDKPackage", dependencies: ["AudioEffectsSDK"]),
		.binaryTarget(name: "AudioEffectsSDK", path: "AudioEffectsSDK.xcframework")
	]
)
