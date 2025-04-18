#ifndef AUDIO_EFFECTS_SDK_FRAMEWORK_AUDIO_FORMAT_H
#define AUDIO_EFFECTS_SDK_FRAMEWORK_AUDIO_FORMAT_H

#import<Foundation/Foundation.h>

/// Format of audio frames that the SDK work with.
typedef NS_ENUM(NSInteger, AESDKAudioFormatType)
{
	/// A raw format where each frame is sequence native-endian floats
	AESDKAudioFormatTypePCMFloat32 = 1,
	
	/// A raw format where each frame is sequence native-endian signed 16-bit integers.
	AESDKAudioFormatTypePCMSignedInt16 = 2,
} NS_SWIFT_NAME(AudioFormatType);

/// Description of audio stream format.
///
/// - note: Currently supports only single-channel audio.
NS_SWIFT_NAME(AudioFormat)
@interface AESDKAudioFormat: NSObject<NSCopying>

-(_Null_unspecified instancetype)init NS_UNAVAILABLE;
-(nonnull instancetype)initWithType:(enum AESDKAudioFormatType)type sampleRate:(uint32_t)sampleRate;

@property(nonatomic) enum AESDKAudioFormatType type;
@property(nonatomic) uint32_t sampleRate;

@end

#endif
