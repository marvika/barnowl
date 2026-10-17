#import "BKNativeVisibility.h"

#import <dlfcn.h>
#import <objc/message.h>

static NSString *const BKFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const BKConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const BKAssertionClass = @"MBAssessmentModeAssertion";

// The selectors belong to a private framework, so no header declares them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
static SEL BKConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL BKActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL BKInvalidate(void) { return @selector(invalidate); }
#pragma clang diagnostic pop

static NSError *BKError(NSString *reason) {
    return [NSError errorWithDomain:@"BKNativeVisibility" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

BOOL BKNativeVisibilityIsAvailable(void) {
    // Resolved at runtime so a macOS that changes or removes the framework
    // reports "unavailable" instead of failing to launch.
    if (!dlopen(BKFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(BKConfigurationClass);
    Class assertion = NSClassFromString(BKAssertionClass);
    return configuration && assertion
        && [configuration instancesRespondToSelector:BKConfigurationInit()]
        && [assertion instancesRespondToSelector:BKActivate()]
        && [assertion instancesRespondToSelector:BKInvalidate()];
}

void BKNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable, NSError *_Nullable)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!BKNativeVisibilityIsAvailable()) {
        finish(nil, BKError(@"MenuBarClientCore is not available on this macOS"));
        return;
    }
    @try {
        // The framework indexes into both lists, so they must be NSArrays.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(BKConfigurationClass) alloc], BKConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(BKAssertionClass) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, BKError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, BKActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, BKError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void BKNativeVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:BKInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, BKInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"BKNativeVisibility: invalidate raised %@: %@", exception.name, exception.reason);
    }
}
