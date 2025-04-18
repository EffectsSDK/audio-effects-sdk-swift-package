![Effects SDK logo](Assets/Logo.png "a title")

# Audio Effects SDK

## Real-time AI-Powered Audio Noise Suppression SDK

Experience flawless audio with our real-time AI-powered noise suppression solution.
Enjoy super easy integration, allowing you to enhance your application’s audio quality
quickly and efficiently.

**Perfect for**:

* Video Conferencing: Ensure crystal-clear communication without background distractions.
* Live Streaming: Deliver professional-grade audio for live broadcasts and streams.
* Recording Applications: Capture high-quality audio by eliminating unwanted noise.

---

## Table of Contents

1. [Features](#features)
1. [Requirements](#requirements)
2. [Setup](#setup)
3. [Usage](#usage)
4. [Documentation](#Documentation)

---

## Features

* Real-time AI-powered noise suppression
* Supports formats: PCM Float 32bit, PCM 16
* Simple and seamless integration

## Trial evaluation

A Customer ID is required for the Effects SDK.
To receive a new trial Customer ID, please fill out the contact form on the [effectssdk.ai](https://effectssdk.ai/request-trial) website.

## Requirements

1. iOS 14
2. XCode

## Setup

Add package dependency into your project. See [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#)

Import Video Effects SDK into your code.
```swift
import AudioEffectsSDK
```

## Usage

### Create and authorize SDK factory instance

```swift
self.sdkFactory = Factory()
let authResult = try await self.sdkFactory.auth(customerID: "CUSTOMER_ID")
guard authResult.status == .active else {
    // Interrupt SDK initialization.
    return
}
```

### Create pipeline instance and enable noise suppression

```swift
let pipelineConfig = PipelineConfig(
    type: .pcmSignedInt16,
    sampleRate: UInt32(sampleRate)
)
self.sdkPipeline = try self.sdkFactory.newPipeline(pipelineConfig)
self.sdkpipeline.noiseSuppressionEnabled = true
```

### Process audio signal

```swift
func processAudio(frames: UnsafeMutableRawPointer, frameNum:UInt32) {
		self.sdkPipeline?.process(
			input: frames,
			inputFrameNum: frameNum,
			output: frames,
			outputFrameNum: frameNum
		)
	}
```

## Documentation

[Our Documentation](https://effectssdk.ai/sdk/audio/ios/documentation/audioeffectssdk)