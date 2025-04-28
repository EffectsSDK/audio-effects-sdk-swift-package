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
			url: "https://github.com/EffectsSDK/audio-effects-sdk-swift-package/releases/download/1.6.0/AudioEffectsSDK.xcframework-1.6.0.112239.zip",
			checksum: "d34c5e2fb58f9b3e8807e7feec0ae07c14807e923d5594856e0c90c7d4a29767"
		)
	]
)
