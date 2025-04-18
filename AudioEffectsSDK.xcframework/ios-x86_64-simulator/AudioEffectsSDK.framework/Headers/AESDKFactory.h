#ifndef AUDIO_EFFECTS_SDK_FRAMEWORK_FACTORY_H
#define AUDIO_EFFECTS_SDK_FRAMEWORK_FACTORY_H

#import "AESDKAudioFormat.h"

@protocol AESDKAuthResult;
@protocol AESDKPipeline;

/// Holds Pipeline initialization parameters
NS_SWIFT_NAME(PipelineConfig)
@interface AESDKPipelineConfig: NSObject

-(instancetype _Null_unspecified)init NS_UNAVAILABLE;

/// Creates a pipeline config with specified input format. The output format is the same as input.
-(nonnull instancetype)initWithInputFormat:(nonnull AESDKAudioFormat*)format;

/// Creates a pipeline config with specified audio format type and sample rate.
///
/// This is a convenience method for ``AESDKPipelineConfig/initWithInputFormat:``
-(nonnull instancetype)initWithType:(enum AESDKAudioFormatType)type sampleRate:(uint32_t)sampleRate;

@property(nonatomic, copy) AESDKAudioFormat* _Nonnull inputFormat;

/// Defines the lower bound for valid PCM float values.
///
/// See ``pcmFloatMaxValue``
@property(nonatomic) float pcmFloatMinValue;

/// Defines the upper bound for valid PCM float values.
///
/// The minimum and maximum values must be equidistant from zero. ``pcmFloatMaxValue`` == abs( ``pcmFloatMinValue`` ).
/// The default values are -1 (minimum) and 1 (maximum).
/// - note: Only works with ``AESDKAudioFormatType/AESDKAudioFormatTypePCMFloat32``. Ignored for all other formats.
@property(nonatomic) float pcmFloatMaxValue;

@end

/// Callback triggered when the authorization process is complete.
///
/// > Tip: For swift use async/await syntax. See ``AESDKFactory``.
///
/// - parameter result: The result of authorization process.
/// - parameter error: An error occurred during the authorization process.
typedef void (^AESDKAuthCompletionHandler) (id<AESDKAuthResult>_Nullable result, NSError*_Nullable error);

/// This is the entry point of the SDK. It is required to create an audio pipeline and perform authorization.
///
/// An instance of ``AESDKFactory`` is lightweight when no ``AESDKPipeline`` instances exist and can be used to create multiple ``AESDKPipeline`` instances.
NS_SWIFT_NAME(Factory)
@interface AESDKFactory: NSObject

/// Authenticates SDK instance online.
///
/// Initiates the authorization process. During this process, the SDK checks the license status and returns the result. Upon completion, the  `completionHandler` is triggered.
///
/// If authorization completes successfully, ``AESDKAuthResult/status`` is set to ``AESDKAuthStatus/AESDKAuthStatusActive``.
///  Otherwise, the SDK cannot be used.
/// - note: Internet connection is required.
/// - parameter customerID: Unique client identifier.
/// - parameter completionHandler: Callback to be called on completion.
-(void)authWithCustomerID:(nonnull NSString*)customerID completionHandler:(nonnull AESDKAuthCompletionHandler)completionHandler
	NS_SWIFT_NAME(auth(customerID:completionHandler:));

/// Authenticates SDK instance online with a custom server.
///
/// Equivalent to ``AESDKFactory/authWithCustomerID:completionHandler:`` with added support for a custom authentication server URL.
/// - note: Internet connection is required.
/// - parameter customerID: Unique client identifier.
/// - parameter apiUrl: URL of custom server.
/// - parameter completionHandler: Callback to be called on completion.
-(void)authWithCustomerID:(nonnull NSString*)customerID apiUrl:(nonnull NSURL*)apiUrl completionHandler:(nonnull AESDKAuthCompletionHandler)completionHandler
	NS_SWIFT_NAME(auth(customerID:apiUrl:completionHandler:));

/// Offline authorization with a secret key.
///
/// - Parameter key: Unique client's secret key. DO NOT reveal it.
-(nonnull id<AESDKAuthResult>)authWithKey:(nonnull NSString*)key NS_SWIFT_NAME(auth(key:));

/// Creates an audio processing pipeline.
///
/// - Note: Before creating a first instance of ``AESDKPipeline``  authorization is needed. For authorization see ``AESDKFactory/authWithCustomerID:completionHandler:``, ``AESDKFactory/authWithKey`` or ``AESDKFactory/authWithCustomerID:apiUrl:completionHandler:``
///
-(nullable id<AESDKPipeline>)newPipelineWithConfig:(nonnull AESDKPipelineConfig*)config error:(NSError* _Nullable *_Nullable)error
	NS_SWIFT_NAME(newPipeline(_:));

@end

#endif
