

import Foundation
import AVFAudio
import AudioEffectsSDK

let webRtcPcmMaxValue = Float32(32768)

enum AudioSampleFormat: CaseIterable {
	case pcmInt16
	case pcmFloat32
	case pcmFloat32WebRTC
	
	var byteSize:Int {
		return avCommonFormat.byteSize
	}
	
	var isFloat:Bool {
		switch self {
		case .pcmFloat32:
			return true
		case .pcmFloat32WebRTC:
			return true
			
		default:
			return false
		}
	}
	
	var avCommonFormat: AVAudioCommonFormat {
		switch self {
		case .pcmInt16:
			return .pcmFormatInt16
		case .pcmFloat32:
			return .pcmFormatFloat32
		case .pcmFloat32WebRTC:
			return .pcmFormatFloat32
		}
	}
	
	var sdkFormat: AudioFormatType {
		switch self {
		case .pcmInt16:
			return .pcmSignedInt16
		case .pcmFloat32:
			return .pcmFloat32
		case .pcmFloat32WebRTC:
			return .pcmFloat32
		}
	}
}

extension AVAudioCommonFormat 
{
	var byteSize: Int {
		switch self {
		case .pcmFormatInt16:
			return 2
		case .pcmFormatInt32:
			return 4
		case .pcmFormatFloat32:
			return 4
		case .pcmFormatFloat64:
			return 8
		default:
			return 0
		}
	}
}

enum PipelineState {
	case uninitialized
	case authorization
	case initialization
	case ready
}

enum PipelineMediaState {
	case inactive
	case starting
	case performing
	case stopping
}

enum PipelineMediaMode {
	case idle
	case playing
	case recording
}

enum ErrorStatus {
	case noErr
	case recordPermissionDenied
}

class AudioPipelineController: ObservableObject {
	@Published private(set) var state = PipelineState.uninitialized
	@Published private(set) var playingState = PipelineMediaState.inactive
	@Published private(set) var recordingState = PipelineMediaState.inactive
	@Published private(set) var mode = PipelineMediaMode.idle
	@Published private(set) var recordingFormat: AudioSampleFormat = .pcmFloat32
	@Published private(set) var recordingSampleRate: Int = 0
	@Published private(set) var recordedSecondCount = 0
	@Published private(set) var playingFileURL: URL? = nil
	@Published private(set) var playingSampleRate: Int = 0
	@Published private(set) var playingFormat: AudioSampleFormat = .pcmFloat32
	@Published var playingWithFilter = false {
		didSet {
			playingSDKPipeline?.noiseSuppressionEnabled = playingWithFilter
		}
	}
	@Published private(set) var errorStatus = ErrorStatus.noErr
	@Published var playback = false {
		didSet {
			lock.locked {
				playbackSDKFlushNeeded = playback
				playbackEnabled = playback
			}
		}
	}
	@Published var playbackNoiseSupression = false {
		didSet {
			playbackSDKPipeline?.noiseSuppressionEnabled = playbackNoiseSupression
		}
	}
	
	private var sdkFactory = Factory()
	private var playingSDKPipeline: Pipeline? = nil
	private var playingSDKSampleRate: Int = 0
	private var playingSDKFormat = AudioSampleFormat.pcmFloat32
	private var playingAVFormat: AVAudioFormat? = nil
	private var playingWebRTCScaleEnabled = false
	private var playbackSDKPipeline: Pipeline? = nil
	private var playbackSDKSampleRate: Int = 0
	private var playbackSDKFormat = AudioSampleFormat.pcmFloat32
	private var playbackEnabled = false
	private var playbackSDKFlushNeeded = false
	private var playbackWebRTCScaleEnabled = false
	private var lock = UnfairLock()
	private var audioIODevice: AudioIODevice? = nil
	private var tempAudioFileURL: URL? = nil
	private var audioFile: AVAudioFile? = nil
	private var recordingTempBuffer: AVAudioPCMBuffer? = nil
	private var recordedFrameCount: UInt32 = 0
	private var recordingAVFormat: AVAudioFormat? = nil
	private var prevNotifiedSecondCount: UInt32 = 0
	
	deinit {
		try! audioIODevice?.stop()
	}
	
	func initialize() async {
		let canContiniue: Bool = await MainActor.run {
			if (PipelineState.uninitialized != state) {
				return false
			}
			state = PipelineState.authorization
			return true
		}
		guard canContiniue else {
			return
		}
		
		do {
			let authResult = try await sdkFactory.auth(customerID: "CUSTOMER_ID")
			guard authResult.status == .active else {
				await MainActor.run {
					state = PipelineState.uninitialized
				}
				return
			}
		} catch {
			await MainActor.run {
				state = PipelineState.uninitialized
			}
			return
		}
		
		await MainActor.run {
			state = PipelineState.ready
		}
	}
	
	func startRecording(sampleRate: Int, format: AudioSampleFormat) async {
		let canContinue = await MainActor.run {
			if (mode != .idle) {
				return false
			}
			recordingState = .starting
			mode = .recording
			recordedSecondCount = 0
			recordingFormat = format
			recordingSampleRate = sampleRate
			return true
		}
		guard canContinue else {
			return
		}
		
		guard await requestRecordPermission() else {
			await MainActor.run {
				recordingState = .inactive
				mode = .idle
				errorStatus = .recordPermissionDenied
			}
			return
		}
		
		recordedFrameCount = 0
		prevNotifiedSecondCount = 0
		
		do {
			let fileName = UUID().uuidString + "-output.wav"
			let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent(fileName)
			
			let audioFormat = AVAudioFormat(
				commonFormat: format.avCommonFormat,
				sampleRate: Double(sampleRate),
				channels: 1,
				interleaved: true
			)!
			recordingTempBuffer = AVAudioPCMBuffer(
				pcmFormat: audioFormat,
				frameCapacity: UInt32(sampleRate / 10)
			)
			audioFile = try AVAudioFile(
				forWriting: tempFileURL,
				settings: audioFormat.settings,
				commonFormat: audioFormat.commonFormat,
				interleaved: audioFormat.isInterleaved
			)
			tempAudioFileURL = tempFileURL			
			activateAudioSession()
			audioIODevice = AudioIODevice(sampleRate: UInt32(sampleRate), floatPCM: format.isFloat)
			
			let recreatePipelineNeeded =
				(playbackSDKFormat != format) ||
				(playbackSDKSampleRate != sampleRate) ||
				(nil == playbackSDKPipeline)
			
			if recreatePipelineNeeded {
				let sdkPipeline =
					try sdkFactory.newPipeline(makeSDKConfig(sampleRate: sampleRate, format: format))
				playbackSDKFormat = format
				playbackSDKSampleRate = sampleRate
				await MainActor.run {
					sdkPipeline.noiseSuppressionEnabled = playbackNoiseSupression
					playbackSDKPipeline = sdkPipeline
				}
			}
			
			recordingAVFormat = audioFormat
			playbackWebRTCScaleEnabled = format == .pcmFloat32WebRTC
			try audioIODevice?.start(
				receiveAudioHandler: { [weak self] inputPtr, frameNum in
					self?.onReceiveAudio(inputFrames: inputPtr, frameNum: frameNum)
				},
				produceAudioHandler:  { [weak self] outputPtr, frameNum in
					self?.onPlaybackProduceAudio(outputFrames: outputPtr, frameNum: frameNum)
				}
			)
		
			await MainActor.run {
				recordingState = .performing
			}
		}
		catch {
			await MainActor.run {
				recordingState = .inactive
				mode = .idle
			}
		}
	}
	
	func stopRecording() async -> URL? {
		let canContinue = await MainActor.run {
			if (mode != .recording || recordingState != .performing) {
				return false
			}
			recordingState = .stopping
			return true
		}
		guard canContinue else {
			return nil
		}
		
		do {
			try audioIODevice?.stop()
			audioIODevice = nil
			audioFile = nil
			deactivateAudioSession()
			recordingAVFormat = nil
			recordingTempBuffer = nil
			await MainActor.run {
				recordingState = .inactive
				mode = .idle
			}
			return tempAudioFileURL
		}
		catch {}
		return nil
	}
	
	func startPlaying(fileURL: URL, format: AudioSampleFormat) async {
		let canContinue = await MainActor.run {
			if (mode != .idle) {
				return false
			}
			mode = .playing
			playingState = .starting
			return true
		}
		guard canContinue else {
			return
		}
		
		do {
			audioFile = try AVAudioFile(
				forReading: fileURL,
				commonFormat: format.avCommonFormat,
				interleaved: true
			)
			guard let sampleRateF = audioFile?.processingFormat.sampleRate else {
				audioFile = nil
				await MainActor.run {
					mode = .idle
					playingState = .inactive
					playingFileURL = nil
				}
				return
			}
			let sampleRate = Int(sampleRateF)
			
			let recreatePipelineNeeded =
				(playingSDKFormat != format) ||
				(playingSDKSampleRate != sampleRate) ||
				(nil == playingSDKPipeline)
			
			if recreatePipelineNeeded {
				let sdkPipeline =
					try sdkFactory.newPipeline(makeSDKConfig(sampleRate: sampleRate, format: format))
				playingSDKFormat = format
				playingSDKSampleRate = sampleRate
				await MainActor.run {
					sdkPipeline.noiseSuppressionEnabled = playingWithFilter
					playingSDKPipeline = sdkPipeline
				}
			}
			else {
				emptyPipeline(playingSDKPipeline)
			}
			activateAudioSession()
			playingAVFormat = AVAudioFormat(
				commonFormat: format.avCommonFormat,
				sampleRate: Double(sampleRate),
				channels: 1,
				interleaved: true
			)
			playingWebRTCScaleEnabled = format == .pcmFloat32WebRTC
			audioIODevice = AudioIODevice(sampleRate: UInt32(sampleRate), floatPCM: format.isFloat)
			try audioIODevice?.start(
				produceAudioHandler: { [weak self] outputPtr, frameNum in
				   self?.onPlayingProduceAudio(outputFrames: outputPtr, frameNum: frameNum)
			   }
			)
			
			await MainActor.run {
				playingFileURL = fileURL
				playingState = .performing
				playingFormat = format
				playingSampleRate = Int(sampleRate)
			}
		}
		catch {
			audioFile = nil
			audioIODevice = nil
			await MainActor.run {
				mode = .idle
				playingState = .inactive
				playingFileURL = nil
			}
		}
	}
	
	func stopPlaying() async {
		let canContinue = await MainActor.run {
			if (mode != .playing || playingState != .performing) {
				return false
			}
			playingState = .stopping
			return true
		}
		guard canContinue else {
			return
		}
		
		do {
			try audioIODevice?.stop()
			audioIODevice = nil
			audioFile = nil
			deactivateAudioSession()
			playingAVFormat = nil
			await MainActor.run {
				playingState = .inactive
				mode = .idle
				playingFileURL = nil
			}
		}
		catch { }
	}
	
	func resetErrorStatus() {
		errorStatus = .noErr
	}
	
	private func onReceiveAudio(inputFrames: UnsafeRawPointer, frameNum:UInt32) {
		var framesPtr = inputFrames
		var framesToProcessNum = frameNum
		guard let recordingTempBuffer else { return }
		guard let recordingAVFormat else { return }
		
		let (playback, flushNeeded) = lock.locked {
			let flushValue = playbackSDKFlushNeeded
			playbackSDKFlushNeeded = false
			return (playbackEnabled, flushValue)
		}
		
		if flushNeeded {
			emptyPipeline(playbackSDKPipeline)
		}
		
		while (framesToProcessNum > 0) {
			let bufferPtr = recordingTempBuffer.audioBufferList.pointee.mBuffers.mData
			let framesToCopy = min(framesToProcessNum, recordingTempBuffer.frameCapacity)
			let bytesToCopy = Int(framesToCopy) * recordingAVFormat.commonFormat.byteSize
			memcpy(bufferPtr, framesPtr, bytesToCopy)
			framesPtr = framesPtr.advanced(by: bytesToCopy)
			framesToProcessNum -= framesToCopy
			recordingTempBuffer.frameLength = framesToCopy
			
			try? audioFile?.write(from: recordingTempBuffer)
			
			guard playback else {
				continue
			}
			
			if (playbackWebRTCScaleEnabled) {
				scaleFloatPCM(recordingTempBuffer, multiplier: webRtcPcmMaxValue)
			}
			
			playbackSDKPipeline?.process(
				input: bufferPtr,
				inputFrameNum: framesToCopy,
				output: nil,
				outputFrameNum: 0
			)
		}
		
		recordedFrameCount += frameNum
		let recordedSeconds = recordedFrameCount / UInt32(recordingAVFormat.sampleRate)
		if (recordedSeconds > prevNotifiedSecondCount) {
			prevNotifiedSecondCount = recordedSeconds
			Task {
				await MainActor.run {
					recordedSecondCount = Int(recordedSeconds)
				}
			}
		}
	}
	
	private func onPlayingProduceAudio(outputFrames: UnsafeMutableRawPointer, frameNum:UInt32) {
		guard let playingAVFormat else {
			return
		}
		let audioBuffer = AudioBuffer(
			mNumberChannels: 1,
			mDataByteSize:frameNum * UInt32(playingAVFormat.commonFormat.byteSize),
			mData:outputFrames
		)
		var audioBuffers = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
		let avAudioBuffer = AVAudioPCMBuffer(
			pcmFormat: playingAVFormat,
			bufferListNoCopy: &audioBuffers,
			deallocator: nil
		)!
		avAudioBuffer.frameLength = 0
		
		do {
			try audioFile?.read(into: avAudioBuffer)
			if avAudioBuffer.frameLength < frameNum {
				audioFile = nil
			}
		}
		catch {
			audioFile = nil
		}
		
		if avAudioBuffer.frameLength > 0 {
			if (playingWebRTCScaleEnabled) {
				scaleFloatPCM(avAudioBuffer, multiplier: webRtcPcmMaxValue)
			}
			
			playingSDKPipeline?.process(
				input: outputFrames,
				inputFrameNum: avAudioBuffer.frameLength,
				output: outputFrames,
				outputFrameNum: avAudioBuffer.frameLength
			)
			
			if (playingWebRTCScaleEnabled) {
				scaleFloatPCM(avAudioBuffer, multiplier: 1.0/webRtcPcmMaxValue)
			}
		}
		
		guard avAudioBuffer.frameLength < frameNum else {
			return
		}
		
		let filledOutputFramesByteSize = Int(avAudioBuffer.frameLength) * playingAVFormat.commonFormat.byteSize
		let unfilledOutputFrames = outputFrames.advanced(by: filledOutputFramesByteSize)
		let unfilledFrameNum = frameNum - avAudioBuffer.frameLength
		
		let pulledFrameCount = playingSDKPipeline?.flush(
			toOutput: unfilledOutputFrames,
			frameNum: unfilledFrameNum
		) ?? 0 //< To drop optionality
		
		if (playingWebRTCScaleEnabled && pulledFrameCount > 0) {
			scaleFloatPCM(
				srcPtr: unfilledOutputFrames,
				dstPtr: unfilledOutputFrames,
				sampleNum: pulledFrameCount,
				multiplier: 1.0/webRtcPcmMaxValue
			)
		}
		
		let isDrainedUp = (pulledFrameCount < unfilledFrameNum)
		if isDrainedUp {
			Task {
				await stopPlaying()
			}
		}
	}
	
	private func onPlaybackProduceAudio(outputFrames: UnsafeMutableRawPointer, frameNum:UInt32) {
		let playback = lock.locked { playbackEnabled }
		
		if playback {
			let readNum = playbackSDKPipeline?.process(
				input: nil,
				inputFrameNum: 0,
				output: outputFrames,
				outputFrameNum: frameNum
			) ?? 0
			if (playbackWebRTCScaleEnabled) {
				scaleFloatPCM(
					srcPtr: outputFrames,
					dstPtr: outputFrames,
					sampleNum: readNum,
					multiplier: 1.0/webRtcPcmMaxValue
				)
			}
		}
		else {
			guard let recordingAVFormat else { return }
			memset(outputFrames, 0, Int(frameNum) * recordingAVFormat.commonFormat.byteSize)
		}
	}
	
	private func emptyPipeline(_ sdkPipeline: Pipeline?) {
		sdkPipeline?.flush(toOutput: nil, frameNum: 0)
	}
	
	private func requestRecordPermission() async -> Bool {
		if #available(iOS 17.0, *) {
			return await AVAudioApplication.requestRecordPermission()
		} else {
			return await withCheckedContinuation { continuation in
				AVAudioSession.sharedInstance().requestRecordPermission { result in
					continuation.resume(returning: result)
				}
			}
		}
	}
	
	private func activateAudioSession() {
		let session = AVAudioSession.sharedInstance()
		try? session.setActive(true)
		try? session.setCategory(
			.playAndRecord ,
			mode: .default,
			options: [.allowBluetooth, .defaultToSpeaker]
		)
	}
	
	private func deactivateAudioSession() {
		let session = AVAudioSession.sharedInstance()
		try? session.setActive(false)
	}
	
	private func scaleFloatPCM(_ buffer: AVAudioPCMBuffer, multiplier: Float32) {
		guard let floatPtr = buffer.floatChannelData?[0] else {
			return
		}
		
		let sampleNum = buffer.frameLength
		for i in 0...Int(sampleNum) {
			floatPtr[i] *= multiplier
		}
	}
	
	private func scaleFloatPCM(srcPtr: UnsafeRawPointer, dstPtr: UnsafeMutableRawPointer, sampleNum: UInt32, multiplier: Float32) {
		let srcFloatPtr = srcPtr.assumingMemoryBound(to: Float.self)
		let dstFloatPtr = dstPtr.assumingMemoryBound(to: Float.self)
		for i in 0...Int(sampleNum) {
			dstFloatPtr[i] = srcFloatPtr[i] * multiplier
		}
	}
	
	private func makeSDKConfig(sampleRate: Int, format: AudioSampleFormat) -> PipelineConfig {
		let config = PipelineConfig(type: format.sdkFormat, sampleRate: UInt32(sampleRate))
		if format == .pcmFloat32WebRTC {
			config.pcmFloatMinValue = -webRtcPcmMaxValue
			config.pcmFloatMaxValue = webRtcPcmMaxValue
		}
		return config
	}
}
