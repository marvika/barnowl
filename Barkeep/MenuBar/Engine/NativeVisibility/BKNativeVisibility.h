// Bridge to macOS 27's private menu bar visibility restriction.
//
// The approach (MenuBarClientCore's assessment-mode assertion) was found by
// Hidden Bar (MIT, Copyright (c) 2019 Dwarves Foundation); see
// THIRD_PARTY_NOTICES.md.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Whether the private API exists on the running macOS.
BOOL BKNativeVisibilityIsAvailable(void);

/// Keeps only the given system items and apps visible in the menu bar. The
/// completion runs on the main queue with the assertion to hold, or an error.
/// macOS drops the restriction when the assertion is invalidated or this
/// process exits.
void BKNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError *_Nullable error));

void BKNativeVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
