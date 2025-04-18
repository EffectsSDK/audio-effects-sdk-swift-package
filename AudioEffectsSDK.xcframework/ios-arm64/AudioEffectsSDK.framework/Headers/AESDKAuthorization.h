#ifndef AUDIO_EFFECTS_SDK_FRAMEWORK_AUTHORIZATION_H
#define AUDIO_EFFECTS_SDK_FRAMEWORK_AUTHORIZATION_H

#import <Foundation/Foundation.h>

/// Describes result of authorization process.
typedef NS_ENUM(NSInteger, AESDKAuthStatus)
{
	/// Authrization finished with error, example missing internet connection.
	AESDKAuthStatusError = 0,
	
	/// Authorization finished sucessfully, the SDK can be used.
	AESDKAuthStatusActive = 1,
	
	/// Such customer has no license or the license revoked.
	AESDKAuthStatusInactive = 2,
	
	/// The license is expired.
    AESDKAuthStatusExpired = 3
} NS_SWIFT_NAME(AuthStatus);

/// Keeps results of authorization process.
NS_SWIFT_NAME(AuthResult)
@protocol AESDKAuthResult<NSObject>

/// The status of authorization process.
@property(nonatomic, readonly) AESDKAuthStatus status;

@end

#endif
