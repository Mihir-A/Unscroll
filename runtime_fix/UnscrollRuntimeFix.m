/*
 * Sideload persistence fix for Instagram.
 *
 * Based on opa334/IGSideloadFix, Copyright (c) 2022 Lars Fröder.
 * Used under the MIT License; see LICENSE.
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>

static NSString *UnscrollKeychainAccessGroup;
static NSURL *UnscrollFakeGroupContainerURL;
static NSURL *(*UnscrollOriginalAppStoreReceiptURL)(id, SEL);

static void UnscrollCreateDirectory(NSURL *url)
{
    [[NSFileManager defaultManager] createDirectoryAtURL:url
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
}

static NSURL *UnscrollGroupContainer(
    __unused NSFileManager *self,
    __unused SEL selector,
    NSString *groupIdentifier)
{
    NSURL *url = [UnscrollFakeGroupContainerURL
        URLByAppendingPathComponent:groupIdentifier
        isDirectory:YES];
    UnscrollCreateDirectory(url);
    UnscrollCreateDirectory([url URLByAppendingPathComponent:@"Library"
                                                  isDirectory:YES]);
    UnscrollCreateDirectory([url URLByAppendingPathComponent:@"Library/Caches"
                                                  isDirectory:YES]);
    return url;
}

static NSString *UnscrollAccessGroup(__unused id self, __unused SEL selector)
{
    return UnscrollKeychainAccessGroup;
}

static NSURL *UnscrollAppStoreReceiptURL(NSBundle *bundle, SEL selector)
{
    NSURL *url = UnscrollOriginalAppStoreReceiptURL(bundle, selector);
    if (bundle == [NSBundle mainBundle]
        && [url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
        return [[url URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}

static NSString *UnscrollLoadKeychainAccessGroup(void)
{
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : @"UnscrollAccessGroupProbe",
        (__bridge id)kSecAttrService : @"UnscrollRuntimeFix",
        (__bridge id)kSecReturnAttributes : @YES,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(
        (__bridge CFDictionaryRef)query,
        &result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, &result);
    }
    if (status != errSecSuccess || result == NULL) {
        if (result != NULL) {
            CFRelease(result);
        }
        NSLog(@"[Unscroll] Could not discover keychain access group: %d",
              (int)status);
        return nil;
    }

    NSDictionary *attributes = CFBridgingRelease(result);
    NSString *group = attributes[(__bridge id)kSecAttrAccessGroup];
    NSLog(@"[Unscroll] Using keychain access group: %@", group);
    return group;
}

static IMP UnscrollReplaceMethod(
    Class targetClass,
    SEL selector,
    IMP replacement)
{
    if (targetClass == Nil) {
        NSLog(@"[Unscroll] Class for %@ is unavailable",
              NSStringFromSelector(selector));
        return NULL;
    }

    Method method = class_getInstanceMethod(targetClass, selector);
    if (method == NULL) {
        NSLog(@"[Unscroll] %@ does not implement %@",
              NSStringFromClass(targetClass),
              NSStringFromSelector(selector));
        return NULL;
    }
    return method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void UnscrollInitializeRuntimeFix(void)
{
    @autoreleasepool {
        UnscrollFakeGroupContainerURL = [NSURL
            fileURLWithPath:[NSHomeDirectory()
                stringByAppendingPathComponent:@"Documents/FakeGroupContainers"]
            isDirectory:YES];
        UnscrollCreateDirectory(UnscrollFakeGroupContainerURL);

        UnscrollKeychainAccessGroup = UnscrollLoadKeychainAccessGroup();
        if (UnscrollKeychainAccessGroup != nil) {
            SEL accessGroupSelector = @selector(accessGroup);
            UnscrollReplaceMethod(
                objc_getClass("FBSDKKeychainStore"),
                accessGroupSelector,
                (IMP)UnscrollAccessGroup);
            UnscrollReplaceMethod(
                objc_getClass("FBKeychainItemController"),
                accessGroupSelector,
                (IMP)UnscrollAccessGroup);
            UnscrollReplaceMethod(
                objc_getClass("UICKeyChainStore"),
                accessGroupSelector,
                (IMP)UnscrollAccessGroup);
        }

        UnscrollReplaceMethod(
            [NSFileManager class],
            @selector(containerURLForSecurityApplicationGroupIdentifier:),
            (IMP)UnscrollGroupContainer);

        UnscrollOriginalAppStoreReceiptURL =
            (NSURL *(*)(id, SEL))UnscrollReplaceMethod(
                [NSBundle class],
                @selector(appStoreReceiptURL),
                (IMP)UnscrollAppStoreReceiptURL);
    }
}
