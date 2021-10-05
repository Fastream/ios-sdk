#import <Foundation/Foundation.h>

void *Fastream_NewBase64Decode(
	const char *inputBuffer,
	size_t length,
	size_t *outputLength);

char *Fastream_NewBase64Encode(
	const void *inputBuffer,
	size_t length,
	bool separateLines,
	size_t *outputLength);

@interface NSData (FastreamBase64)

+ (NSData *)mp_dataFromBase64String:(NSString *)aString;
- (NSString *)mp_base64EncodedString;

@end
