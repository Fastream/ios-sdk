#import <UIKit/UIKit.h>

#ifndef FastreamLogger_h
#define FastreamLogger_h

static inline void FastreamLog(NSString *format, ...) {
    __block va_list arg_list;
    va_start (arg_list, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
    va_end(arg_list);
    NSLog(@"[Fastream] %@", formattedString);
}

#ifdef FASTREAM_ERROR
#define FastreamError(...) FastreamLog(__VA_ARGS__)
#else
#define FastreamError(...)
#endif

#ifdef FASTREAM_DEBUG
#define FastreamDebug(...) FastreamLog(__VA_ARGS__)
#else
#define FastreamDebug(...)
#endif

#ifdef FASTREAM_MESSAGING_DEBUG
#define FastreamMessagingDebug(...) FastreamLog(__VA_ARGS__)
#else
#define FastreamMessagingDebug(...)
#endif

#endif
