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
		.binaryTarget(
			name: "AudioEffectsSDK", 
			url: "https://github.com/EffectsSDK/audio-effects-sdk-swift-package/releases/download/1.7.1/AudioEffectsSDK.xcframework-1.7.1.113247.zip",
			checksum: "b26d7c829a189510a51978c3a07ee8ba30b31d2d5d891404ad1dd3a9c9f4f446"
		)
	]
)
