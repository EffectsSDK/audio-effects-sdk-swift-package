#ifndef AUDIO_EFFECTS_SDK_FRAMEWORK_PIPELINE_H
#define AUDIO_EFFECTS_SDK_FRAMEWORK_PIPELINE_H

#import<Foundation/Foundation.h>

/// Latency mode indicates to the SDK how to handle delay based on different scenarios.
///
/// Determines how many audio frames should be buffered before returning audio output.
typedef NS_ENUM(NSInteger, AESDKLatencyMode)
{
	/// Audio file processing scenario.
	///
	/// Recommended when no real-time audio consumer. Introduces no additional delay or buffering time.
	/// - Note: A small delay may occur if sample rate conversion is required during processing.
	AESDKLatencyModeFile = 0,
	
	/// Default mode for balanced real-time audio I/O processing. (Default mode).
	///
	/// Optimized for audio streaming scenarios (e.g., WebRTC). Introduces minimal buffering and additional latency.
	AESDKLatencyModeStreaming = 1,
	
	/// Optimized for intermittent audio processing or loopback playing scenarios.
	///
	/// This mode has the substantial buffering and higher delay.
	AESDKLatencyModePlayback = 2,
} NS_SWIFT_NAME(LatencyMode);

/// Core audio processing protocol that applies noise suppression.
NS_SWIFT_NAME(Pipeline)
@protocol AESDKPipeline<NSObject>

/// When enabled, the pipeline applies noise suppression. Otherwise, it returns unmodified audio frames.
///
/// This property is thread-safe. If modified during audio processing, changes may take effect after a short delay.
@property bool noiseSuppressionEnabled;

/// Controls the intensity of noise suppression applied to the audio stream. Range: 0 to 1 (inclusive).
///
/// Higher number - stronger filtering.
@property float noiseSuppressionPower;

/// Latency mode
///
/// Must be set prior to the first call to ``AESDKPipeline/processInput:inputFrameNum:output:outputFrameNum:``.
/// If changed afterward, the new setting will only take effect after pipeline reset (following the next flush operation).
///
/// This property is thread-safe,
@property enum AESDKLatencyMode latencyMode;

/// Performs audio processing and applies enabled audio effects.
///
/// Supports three usage modes:
/// - **Push (write)** - audio frames (`input` is not null and `output` is null)
/// - **Pull (read)** -  audio frames (`input` is null and `output` is not null)
/// - Simultaneous **Push/Pull** operations (both are not null).
///
/// Can process audio in place (same buffer for `input` and `output`), but with some requirements:
///   - Full overlap (`input == output`) is supported
///   - Partial overlap is prohibited and may cause audio artifacts
///
/// Thread-safe for concurrent push/pull operations when:
///   - One thread exclusively pushes audio
///   - Another thread exclusively pulls audio
///
/// - Note: The pipeline maintains an internal buffer to handle imbalances between frame production and consumption.
/// While short-term imbalances are tolerated, sustained imbalance will cause frame drops when buffer limits are exceeded.
///
/// - Parameter input: Pointer to input audio buffer (may aliasing output buffer).
/// - Parameter inputFrameNum: Number of audio frames available in input buffer.
/// - Parameter output: Pointer to output audio buffer (may aliasing input buffer)
/// - Parameter outputFrameNum: Maximum capacity of output buffer (in frames)
/// - Returns: Actual number of frames written to output buffer (can be less than outputFrameNum).
-(uint32_t)processInput:(nullable const void*)input inputFrameNum:(uint32_t)inputFrameNum output:(nullable void*)output outputFrameNum:(uint32_t)outputFrameNum
    NS_SWIFT_NAME(process(input:inputFrameNum:output:outputFrameNum:));

/// Flushes residual audio frames from the pipeline and resets its internal state.
///
/// During processing, the pipeline buffers audio frames internally. This method:
/// - Retrieves any remaining frames (if output buffer provided)
/// - Resets the pipeline's internal state
///
/// Subsequent calls to ``AESDKPipeline/processInput:inputFrameNum:output:outputFrameNum:``
/// will process audio from a fresh state after flushing.
///
/// - Parameter output: Pointer to output audio buffer (pass `nil` to reset without frame retrieval)
/// - Parameter frameNum: Maximum writable capacity of output buffer (in frames)
/// - Returns: Actual number of frames written to output buffer (can be less `frameNum`).  A return value less than `frameNum` indicates all buffered audio has been drained.
-(uint32_t)flushToOutput:(nullable void*)output frameNum:(uint32_t)frameNum
    NS_SWIFT_NAME(flush(toOutput:frameNum:));

@end

#endif
