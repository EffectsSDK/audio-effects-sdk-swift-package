
import AVFoundation
import AudioToolbox

// A VP I/O unit's bus 1 connects to input hardware (microphone).
let kInputBus: AudioUnitElement = 1;
// A VP I/O unit's bus 0 connects to output hardware (speaker).
let kOutputBus: AudioUnitElement = 0;

typealias ReceiveAudioHandler = (_ inputPtr: UnsafeRawPointer, _ frameNum: UInt32) -> Void;
typealias ProduceAudioHandler = (_ outputPtr: UnsafeMutableRawPointer, _ frameNum: UInt32) -> Void;

enum AudioIOError: Error {
	case deviceNotFound
	case auInstantiateError
	case errorStatus(status: OSStatus)
}

class AudioIODevice {
	var audioUnit: AudioUnit? = nil
	var audioUnitInitialized: Bool = false
	var audioUnitStarted: Bool = false
	var propertiesUpdateIsNeeded: Bool = true

	var sampleRate: UInt32 = 0
	var floatPCM: Bool = false
	var receiveAudioHandler: ReceiveAudioHandler? = nil
	var produceAudioHandler: ProduceAudioHandler? = nil

	init(
		sampleRate: UInt32,
		floatPCM:Bool = false)
	{
		self.sampleRate = sampleRate
		self.floatPCM = floatPCM
	}

	deinit {
		self.disposeAudioUnit()
	}

	public func start(
		receiveAudioHandler: ReceiveAudioHandler? = nil,
		produceAudioHandler: ProduceAudioHandler? = nil
	) throws {
		if (self.audioUnitStarted) {
			return
		}
		
		self.receiveAudioHandler = receiveAudioHandler
		self.produceAudioHandler = produceAudioHandler
		
		if ((nil == receiveAudioHandler) && (nil == produceAudioHandler)) {
			return
		}

		try updateAudioUnit()

		if (!self.audioUnitInitialized) {
			let status = AudioUnitInitialize(self.audioUnit!)
			guard status == noErr else {
				throw AudioIOError.errorStatus(status: status)
			}
			self.audioUnitInitialized = true
		}

		let status = AudioOutputUnitStart(self.audioUnit!)
		guard status == noErr else {
			throw AudioIOError.errorStatus(status: status)
		}
		self.audioUnitStarted = true
	}

	public func stop() throws {
		if (!self.audioUnitStarted) {
			return
		}

		let status = AudioOutputUnitStop(self.audioUnit!)
		guard status == noErr else {
			throw AudioIOError.errorStatus(status: status)
		}
		self.audioUnitStarted = false
		receiveAudioHandler = nil
		produceAudioHandler = nil
	}

	func updateAudioUnit() throws
	{
		if nil == self.audioUnit {
			try setupAudioUnit()
		}

		if (self.audioUnitInitialized) {
			let status = AudioUnitUninitialize(self.audioUnit!)
			guard status == noErr else {
				throw AudioIOError.errorStatus(status: status)
			}
			self.audioUnitInitialized = false
		}

		var speakerFlag: UInt32 = (self.produceAudioHandler != nil) ? 1 : 0
		var status = AudioUnitSetProperty(self.audioUnit!,
			kAudioOutputUnitProperty_EnableIO,
			kAudioUnitScope_Output,
			kOutputBus,
			&speakerFlag,
			UInt32(MemoryLayout.size(ofValue: speakerFlag))
		)
		guard status == noErr else {
			throw AudioIOError.errorStatus(status: status)
		}

		var micFlag: UInt32 = (self.receiveAudioHandler != nil) ? 1 : 0
		status = AudioUnitSetProperty(audioUnit!,
			kAudioOutputUnitProperty_EnableIO,
			kAudioUnitScope_Input,
			kInputBus,
			&micFlag,
			UInt32(MemoryLayout.size(ofValue: micFlag))
		)
		guard status == noErr else {
			throw AudioIOError.errorStatus(status: status)
		}
	}
	
	func setupAudioUnit() throws {
		var componentDesc = AudioComponentDescription(
			componentType: kAudioUnitType_Output,
			componentSubType: kAudioUnitSubType_VoiceProcessingIO,
			componentManufacturer: kAudioUnitManufacturer_Apple,
			componentFlags: 0,
			componentFlagsMask: 0
		)
		
		guard let component = AudioComponentFindNext(nil, &componentDesc) else {
			throw AudioIOError.deviceNotFound
		}
		
		var audioUnitOpt: AudioUnit? = nil
		var status = AudioComponentInstanceNew(component, &audioUnitOpt)
		guard status == noErr else {
			throw AudioIOError.errorStatus(status: status)
		}
		guard let audioUnit = audioUnitOpt else {
			throw AudioIOError.auInstantiateError
		}
				
		// Set stream format
		var streamFormat = self.getFormat()
		
		status = AudioUnitSetProperty(audioUnit,
			kAudioUnitProperty_StreamFormat,
			kAudioUnitScope_Output,
			kInputBus,
			&streamFormat,
			UInt32(MemoryLayout.size(ofValue: streamFormat))
		)
		guard status == noErr else {
			AudioComponentInstanceDispose(audioUnit)
			throw AudioIOError.errorStatus(status: status)
		}
		
		status = AudioUnitSetProperty(audioUnit,
			kAudioUnitProperty_StreamFormat,
			kAudioUnitScope_Input,
			kOutputBus,
			&streamFormat,
			UInt32(MemoryLayout.size(ofValue: streamFormat))
		)
		guard status == noErr else {
			AudioComponentInstanceDispose(audioUnit)
			throw AudioIOError.errorStatus(status: status)
		}
		
		// Set up render callback
		var renderCallback = AURenderCallbackStruct(
			inputProc: renderCallback,
			inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
		)
		
		status = AudioUnitSetProperty(audioUnit,
									 kAudioUnitProperty_SetRenderCallback,
									 kAudioUnitScope_Input,
									 kOutputBus,
									 &renderCallback,
									 UInt32(MemoryLayout.size(ofValue: renderCallback))
		)
		guard status == noErr else {
			AudioComponentInstanceDispose(audioUnit)
			throw AudioIOError.errorStatus(status: status)
		}
		
		var micCallback = AURenderCallbackStruct(
			inputProc: microphoneCallback,
			inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
		)		
		status = AudioUnitSetProperty(audioUnit,
								kAudioOutputUnitProperty_SetInputCallback,
								kAudioUnitScope_Global,
								kInputBus,
								&micCallback,
								UInt32(MemoryLayout.size(ofValue: micCallback))
		)
		
		guard status == noErr else {
			AudioComponentInstanceDispose(audioUnit)
			throw AudioIOError.errorStatus(status: status)
		}

		self.audioUnit = audioUnit
	}

	func getFormat() -> AudioStreamBasicDescription
	{
		let sampleType: AudioFormatFlags = self.floatPCM ? 
			kLinearPCMFormatFlagIsFloat : kLinearPCMFormatFlagIsSignedInteger
		let formatFlags: AudioFormatFlags = sampleType | kLinearPCMFormatFlagIsPacked
		let bytesPerSample: UInt32 = self.floatPCM ? 4 : 2

		return AudioStreamBasicDescription(
			mSampleRate: Float64(self.sampleRate),
			mFormatID: kAudioFormatLinearPCM,
			mFormatFlags: formatFlags,
			mBytesPerPacket: bytesPerSample,
			mFramesPerPacket: 1,
			mBytesPerFrame: bytesPerSample,
			mChannelsPerFrame: 1,
			mBitsPerChannel: 8 * bytesPerSample,
			mReserved: 0
		)
	}

	func disposeAudioUnit() {
		guard self.audioUnit != nil else {
			return;
		}
		
		if (self.audioUnitStarted) {
			AudioOutputUnitStop(self.audioUnit!)
		}
		if (self.audioUnitInitialized) {
			AudioUnitUninitialize(self.audioUnit!)
		}
		AudioComponentInstanceDispose(self.audioUnit!)
		self.audioUnit = nil
	}
	
	let renderCallback: AURenderCallback = { (
		inRefCon,
		ioActionFlags,
		inTimeStamp,
		inBusNumber,
		inNumberFrames,
		ioData) -> OSStatus in
		
		let this = Unmanaged<AudioIODevice>.fromOpaque(inRefCon).takeUnretainedValue()
		var status = noErr
		
		guard let output = UnsafeMutableAudioBufferListPointer(ioData) else {
			return status
		}
		
		if output.count > 0, let outputBuffer = output[0].mData {
			this.produceAudioHandler?(outputBuffer,  inNumberFrames)
		}
		
		return status
	}
	
	let microphoneCallback: AURenderCallback = { (
		inRefCon,
		ioActionFlags,
		inTimeStamp,
		inBusNumber,
		inNumberFrames,
		ioData) -> OSStatus in
		
		let this = Unmanaged<AudioIODevice>.fromOpaque(inRefCon).takeUnretainedValue()
		var status = noErr
		
		var bufferList = AudioBufferList(
			mNumberBuffers: 1,
			mBuffers: AudioBuffer(
				mNumberChannels: 1,
				mDataByteSize: inNumberFrames * 4,
				mData: nil))
		
		status = AudioUnitRender(
			this.audioUnit!,
			ioActionFlags,
			inTimeStamp,
			kInputBus,
			inNumberFrames,
			&bufferList
		)
		guard let buffer = bufferList.mBuffers.mData else {
			return status;
		}
		let framePtr = UnsafeMutableRawPointer(OpaquePointer(buffer))
		this.receiveAudioHandler?(framePtr,  inNumberFrames)
		
		return status
	}
}

