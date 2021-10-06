#import <XCTest/XCTest.h>
@import Fastream;

@interface FastreamTests : XCTestCase

@end

@implementation FastreamTests

- (void)testExample {
    NSString *apiToken = @"secret_token_value";
    NSString *serverURLString = @"https://www.example.com";

    Fastream *sampleInstance = [[Fastream alloc] initWithToken: apiToken serverURL:serverURLString andFlushInterval:1000];
    [sampleInstance track:@"eventName" properties:@{
        @"key1": @"value1",
        @"key2": @"value2",
    }];

    FastreamLog(@"eventName");
}

@end
