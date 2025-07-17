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
			url: "https://github.com/EffectsSDK/audio-effects-sdk-swift-package/releases/download/1.7.0/AudioEffectsSDK.xcframework-1.7.0.113272.zip",
			checksum: "640222904d8f612c16f8f3facac53dfc6df136cb0aa28d6ebe162640449c6942"
		)
	]
)
