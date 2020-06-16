#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Either turn on ARC for the project or use -fobjc-arc flag on this file.
#endif

#import "NSData+FastreamBase64.h"

static unsigned char base64EncodeLookup[65] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

#define xx 65

static unsigned char base64DecodeLookup[256] =
{
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, 62, xx, xx, xx, 63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, xx, xx, xx, xx, xx, xx,
    xx,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, xx, xx, xx, xx, xx,
    xx, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx,
};

#define BINARY_UNIT_SIZE 3
#define BASE64_UNIT_SIZE 4

void *Fastream_NewBase64Decode(
	const char *inputBuffer,
	size_t length,
	size_t *outputLength)
{
	if (length == 0) {
		length = strlen(inputBuffer);
	}

	size_t outputBufferSize = (length / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE;
	unsigned char *outputBuffer = (unsigned char *)malloc(outputBufferSize);

	size_t i = 0;
	size_t j = 0;
	while (i < length)
	{
		//
		// Accumulate 4 valid characters (ignore everything else)
		//
		unsigned char accumulated[BASE64_UNIT_SIZE] = {0, 0, 0, 0};
		size_t accumulateIndex = 0;
		while (i < length)
		{
			unsigned char decode = base64DecodeLookup[inputBuffer[i++]];
			if (decode != xx) {
				accumulated[accumulateIndex] = decode;
				accumulateIndex++;

				if (accumulateIndex == BASE64_UNIT_SIZE) {
					break;
				}
			}
		}

		outputBuffer[j] = (unsigned char)(accumulated[0] << 2) | (accumulated[1] >> 4);
		outputBuffer[j + 1] = (unsigned char)(accumulated[1] << 4) | (accumulated[2] >> 2);
		outputBuffer[j + 2] = (unsigned char)(accumulated[2] << 6) | accumulated[3];
		j += accumulateIndex - 1;
	}

	if (outputLength) {
		*outputLength = j;
	}
	return outputBuffer;
}

char *Fastream_NewBase64Encode(
	const void *buffer,
	size_t length,
	bool separateLines,
	size_t *outputLength)
{
	const unsigned char *inputBuffer = (const unsigned char *)buffer;

	#define MAX_NUM_PADDING_CHARS 2
	#define OUTPUT_LINE_LENGTH 64
	#define INPUT_LINE_LENGTH ((OUTPUT_LINE_LENGTH / BASE64_UNIT_SIZE) * BINARY_UNIT_SIZE)
	#define CR_LF_SIZE 2

	size_t outputBufferSize =
			((length / BINARY_UNIT_SIZE)
				+ ((length % BINARY_UNIT_SIZE) ? 1 : 0))
					* BASE64_UNIT_SIZE;
	if (separateLines) {
		outputBufferSize +=
			(outputBufferSize / OUTPUT_LINE_LENGTH) * CR_LF_SIZE;
	}

	outputBufferSize += 1;

	char *outputBuffer = (char *)malloc(outputBufferSize);
	if (!outputBuffer) {
		return NULL;
	}

	size_t i = 0;
	size_t j = 0;
	const size_t lineLength = separateLines ? INPUT_LINE_LENGTH : length;
	size_t lineEnd = lineLength;

	while (true)
	{
		if (lineEnd > length) {
			lineEnd = length;
		}

		for (; i + BINARY_UNIT_SIZE - 1 < lineEnd; i += BINARY_UNIT_SIZE) {
			//
			// Inner loop: turn 48 bytes into 64 base64 characters
			//
			outputBuffer[j++] = (char)base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
			outputBuffer[j++] = (char)base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
				| ((inputBuffer[i + 1] & 0xF0) >> 4)];
			outputBuffer[j++] = (char)base64EncodeLookup[((inputBuffer[i + 1] & 0x0F) << 2)
				| ((inputBuffer[i + 2] & 0xC0) >> 6)];
			outputBuffer[j++] = (char)base64EncodeLookup[inputBuffer[i + 2] & 0x3F];
		}

		if (lineEnd == length) {
			break;
		}

		outputBuffer[j++] = '\r';
		outputBuffer[j++] = '\n';
		lineEnd += lineLength;
	}

	if (i + 1 < length) {

		outputBuffer[j++] = (char)base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = (char)base64EncodeLookup[((inputBuffer[i] & 0x03) << 4)
			| ((inputBuffer[i + 1] & 0xF0) >> 4)];
		outputBuffer[j++] = (char)base64EncodeLookup[(inputBuffer[i + 1] & 0x0F) << 2];
		outputBuffer[j++] =	'=';
	}
	else if (i < length) {
		//
		// Handle the double '=' case
		//
		outputBuffer[j++] = (char)base64EncodeLookup[(inputBuffer[i] & 0xFC) >> 2];
		outputBuffer[j++] = (char)base64EncodeLookup[(inputBuffer[i] & 0x03) << 4];
		outputBuffer[j++] = '=';
		outputBuffer[j++] = '=';
	}
	outputBuffer[j] = 0;

	if (outputLength) {
		*outputLength = j;
	}
	return outputBuffer;
}

@implementation NSData (FastreamBase64)

+ (NSData *)mp_dataFromBase64String:(NSString *)aString
{
	NSData *data = [aString dataUsingEncoding:NSASCIIStringEncoding];
	size_t outputLength;
	void *outputBuffer = Fastream_NewBase64Decode([data bytes], [data length], &outputLength);
	NSData *result = [NSData dataWithBytes:outputBuffer length:outputLength];
	free(outputBuffer);
	return result;
}

- (NSString *)mp_base64EncodedString
{
	size_t outputLength = 0;
	char *outputBuffer =
		Fastream_NewBase64Encode([self bytes], [self length], false, &outputLength);

	NSString *result =
		[[NSString alloc]
			initWithBytes:outputBuffer
			length:outputLength
			encoding:NSASCIIStringEncoding];
	free(outputBuffer);
	return result;
}

@end
