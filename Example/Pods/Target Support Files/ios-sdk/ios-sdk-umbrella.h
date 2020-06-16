#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "Fastream.h"
#import "FastreamLogger.h"
#import "NSData+FastreamBase64.h"

FOUNDATION_EXPORT double ios_sdkVersionNumber;
FOUNDATION_EXPORT const unsigned char ios_sdkVersionString[];

