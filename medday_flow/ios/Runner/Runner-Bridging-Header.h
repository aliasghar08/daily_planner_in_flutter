#import "GeneratedPluginRegistrant.h"
#import <Foundation/Foundation.h>

static inline NSException * _Nullable CatchObjCException(void (NS_NOESCAPE ^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        return exception;
    }
}
