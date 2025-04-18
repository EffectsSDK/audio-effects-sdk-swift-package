

import Foundation
import AVFAudio
import AudioEffectsSDK

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
	@Published private(set) var recordedSecondCount = 0
	@Published private(set) var playingFileURL: URL? = nil
	@Published private(set) var playingWithFilter = false
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
	
	private var playingSDKPipeline: Pipeline? = nil
	private var playbackSDKPipeline: Pipeline? = nil
	private var playbackEnabled = false
	private var playbackSDKFlushNeeded = false
	private var lock = UnfairLock()
	private var audioIODevice: AudioIODevice? = nil
	private var tempAudioFileURL: URL? = nil
	private var audioFile: AVAudioFile? = nil
	private var recordedFrameCount: UInt32 = 0
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
		
		let factory = Factory()
		do {
			let authResult = try await factory.auth(customerID: "CUSTOMER_ID")
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
			state = PipelineState.initialization
		}
		
		do {
			let pipelineConfig = PipelineConfig(
				type: .pcmSignedInt16,
				sampleRate: UInt32(sampleRate)
			)
			playingSDKPipeline = try factory.newPipeline(pipelineConfig)
			playbackSDKPipeline = try factory.newPipeline(pipelineConfig)
			playbackSDKPipeline?.latencyMode = .playback
			audioIODevice = AudioIODevice(
				sampleRate: UInt32(sampleRate),
				floatPCM: false
			)
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
	
	func startRecording() async {
		let canContinue = await MainActor.run {
			if (mode != .idle) {
				return false
			}
			recordingState = .starting
			mode = .recording
			recordedSecondCount = 0
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
			audioFile = try AVAudioFile(
				forWriting: tempFileURL,
				settings: audioFormat.settings,
				commonFormat: audioFormat.commonFormat,
				interleaved: audioFormat.isInterleaved
			)
			tempAudioFileURL = tempFileURL			
			activateAudioSession(playAndRecord: true)
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
			audioFile = nil
			deactivateAudioSession()
			await MainActor.run {
				recordingState = .inactive
				mode = .idle
			}
			return tempAudioFileURL
		}
		catch {}
		return nil
	}
	
	func startPlaying(fileURL: URL, withFilter: Bool) async {
		let canContinue = await MainActor.run {
			if (mode != .idle) {
				return false
			}
			mode = .playing
			playingState = .starting
			playingWithFilter = withFilter
			return true
		}
		guard canContinue else {
			return
		}
		
		do {
			audioFile = try AVAudioFile(
				forReading: fileURL,
				commonFormat: audioFormat.commonFormat,
				interleaved: audioFormat.isInterleaved
			)
			if playingWithFilter {
				emptyPipeline(playingSDKPipeline)
				playingSDKPipeline?.noiseSuppressionEnabled = true
			}
			activateAudioSession(playAndRecord: false)
			try audioIODevice?.start(
				produceAudioHandler: { [weak self] outputPtr, frameNum in
				   self?.onPlayingProduceAudio(outputFrames: outputPtr, frameNum: frameNum)
			   }
			)
			
			await MainActor.run {
				playingFileURL = fileURL
				playingState = .performing
			}
		}
		catch {
			audioFile = nil
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
			audioFile = nil
			deactivateAudioSession()
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
		guard let audioBuffer = AVAudioPCMBuffer(
			pcmFormat: audioFormat,
			frameCapacity: frameNum
		) else {
			return
		}
		
		guard let dataPtr = audioBuffer.audioBufferList.pointee.mBuffers.mData else {
			return
		}
		
		memcpy(dataPtr, inputFrames, Int(frameNum * frameByteLength))
		audioBuffer.frameLength = frameNum
		
		try? audioFile?.write(from: audioBuffer)
		
		recordedFrameCount += frameNum
		let recordedSeconds = recordedFrameCount / UInt32(sampleRate)
		if (recordedSeconds > prevNotifiedSecondCount) {
			prevNotifiedSecondCount = recordedSeconds
			Task {
				await MainActor.run {
					recordedSecondCount = Int(recordedSeconds)
				}
			}
		}
		
		let (playback, flushNeeded) = lock.locked {
			let flushValue = playbackSDKFlushNeeded
			playbackSDKFlushNeeded = false
			return (playbackEnabled, flushValue)
		}
		
		if flushNeeded {
			emptyPipeline(playbackSDKPipeline)
		}
		if playback {
			playbackSDKPipeline?.process(
				input: inputFrames,
				inputFrameNum: frameNum,
				output: nil,
				outputFrameNum: 0
			)
		}
	}
	
	private func onPlayingProduceAudio(outputFrames: UnsafeMutableRawPointer, frameNum:UInt32) {
		let audioBuffer = AudioBuffer(
			mNumberChannels: 1,
			mDataByteSize:frameNum * frameByteLength,
			mData:outputFrames
		)
		var audioBuffers = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
		let avAudioBuffer = AVAudioPCMBuffer(
			pcmFormat: audioFormat,
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
		
		if nil == audioFile && !playingWithFilter {
			Task {
				await stopPlaying()
			}
			return
		}
		
		guard playingWithFilter else {
			return
		}
		
		if avAudioBuffer.frameLength > 0 {
			playingSDKPipeline?.process(
				input: outputFrames,
				inputFrameNum: avAudioBuffer.frameLength,
				output: outputFrames,
				outputFrameNum: avAudioBuffer.frameLength
			)
		}
		
		guard avAudioBuffer.frameLength < frameNum else {
			return
		}
		
		let filledOutputFramesByteSize = Int(avAudioBuffer.frameLength * frameByteLength)
		let unfilledOutputFrames = outputFrames.advanced(by: filledOutputFramesByteSize)
		let unfilledFrameNum = frameNum - avAudioBuffer.frameLength
		
		let pulledFrameCount = playingSDKPipeline?.flush(
			toOutput: unfilledOutputFrames,
			frameNum: unfilledFrameNum
		) ?? 0 //< To drop optionality
		
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
			playbackSDKPipeline?.process(
				input: nil,
				inputFrameNum: 0,
				output: outputFrames,
				outputFrameNum: frameNum
			)
		}
		else {
			memset(outputFrames, 0, Int(frameNum * frameByteLength))
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
	
	private func activateAudioSession(playAndRecord: Bool) {
		let session = AVAudioSession.sharedInstance()
		try? session.setCategory(
			playAndRecord ? .playAndRecord : .playback,
			options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
		)
		try? session.setActive(true)
	}
	
	private func deactivateAudioSession() {
		let session = AVAudioSession.sharedInstance()
		try? session.setActive(false)
	}
	
	var audioFormat: AVAudioFormat {
		AVAudioFormat(
			commonFormat: .pcmFormatInt16,
			sampleRate: sampleRate,
			channels: 1,
			interleaved: true
		)!
	}
	
	var sampleRate:Double {
		48000
	}
	
	var frameByteLength: UInt32 { 2 }
}
