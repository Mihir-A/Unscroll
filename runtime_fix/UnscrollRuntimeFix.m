/*
 * Client-side Reels limiter and sideload compatibility fixes for Instagram.
 *
 * Based on opa334/IGSideloadFix, Copyright (c) 2022 Lars Fröder.
 * Used under the MIT License; see LICENSE.
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *UnscrollKeychainAccessGroup;
static NSString *UnscrollTeamIdentifier;
static NSURL *UnscrollFakeGroupContainerURL;
static NSURL *(*UnscrollOriginalAppStoreReceiptURL)(id, SEL);
static NSURL *(*UnscrollOriginalGroupContainer)(id, SEL, NSString *);
static id (*UnscrollOriginalReelsObjects)(id, SEL, id);
static id (*UnscrollOriginalHomeFeedObjects)(id, SEL, id);
static BOOL (*UnscrollOriginalOpenURL)(id, SEL, UIApplication *, NSURL *, NSDictionary *);
static char UnscrollFirstReelKey;

static id UnscrollLimitReelsObjects(id self, SEL selector, id adapter)
{
    id objects = UnscrollOriginalReelsObjects(self, selector, adapter);
    if (![objects isKindOfClass:[NSArray class]] || [objects count] == 0) {
        return objects;
    }

    id firstReel = objc_getAssociatedObject(self, &UnscrollFirstReelKey);
    if (firstReel == nil) {
        firstReel = [objects firstObject];
        objc_setAssociatedObject(
            self,
            &UnscrollFirstReelKey,
            firstReel,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return @[firstReel];
}

static id UnscrollFilterHomeFeedObjects(id self, SEL selector, id adapter)
{
    id objects = UnscrollOriginalHomeFeedObjects(self, selector, adapter);
    Class clipsModelClass = objc_getClass("IGFeedScrollableClipsModel");
    if (![objects isKindOfClass:[NSArray class]] || clipsModelClass == Nil) {
        return objects;
    }

    NSMutableArray *filteredObjects =
        [NSMutableArray arrayWithCapacity:[objects count]];
    for (id object in objects) {
        if (![object isKindOfClass:clipsModelClass]) {
            [filteredObjects addObject:object];
        }
    }
    return filteredObjects.count == [objects count]
        ? objects
        : [filteredObjects copy];
}

static void UnscrollCreateDirectory(NSURL *url)
{
    [[NSFileManager defaultManager] createDirectoryAtURL:url
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
}

static NSURL *UnscrollGroupContainer(
    NSFileManager *self,
    SEL selector,
    NSString *groupIdentifier)
{
    if (groupIdentifier.length == 0) {
        return nil;
    }

    if (UnscrollOriginalGroupContainer != NULL) {
        NSURL *url = UnscrollOriginalGroupContainer(
            self, selector, groupIdentifier);
        if (url != nil) {
            return url;
        }

        if (UnscrollTeamIdentifier.length > 0
            && ![groupIdentifier hasSuffix:UnscrollTeamIdentifier]) {
            NSString *signedIdentifier = [groupIdentifier
                stringByAppendingFormat:@".%@", UnscrollTeamIdentifier];
            url = UnscrollOriginalGroupContainer(
                self, selector, signedIdentifier);
            if (url != nil) {
                return url;
            }
        }
    }

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

static BOOL UnscrollIsExtensionProcess(void)
{
    return [[NSBundle mainBundle].bundlePath.pathExtension
        isEqualToString:@"appex"];
}

static NSURL *UnscrollWrappedInstagramURL(NSURL *url)
{
    if (![url.scheme.lowercaseString isEqualToString:@"unscroll"]
        || ![url.host.lowercaseString isEqualToString:@"open"]) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents
        componentsWithURL:url
        resolvingAgainstBaseURL:NO];
    NSString *wrappedURLString = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"url"]) {
            wrappedURLString = item.value;
            break;
        }
    }
    if (wrappedURLString.length == 0) {
        return nil;
    }
    NSURL *wrappedURL = [NSURL URLWithString:wrappedURLString];
    NSString *scheme = wrappedURL.scheme.lowercaseString;
    NSString *host = wrappedURL.host.lowercaseString;
    BOOL validHost = [host isEqualToString:@"instagram.com"]
        || [host hasSuffix:@".instagram.com"]
        || [host isEqualToString:@"instagr.am"]
        || [host hasSuffix:@".instagr.am"];
    if (![scheme isEqualToString:@"https"] || !validHost) {
        return nil;
    }
    return wrappedURL;
}

static BOOL UnscrollOpenURL(
    id self,
    SEL selector,
    UIApplication *application,
    NSURL *url,
    NSDictionary *options)
{
    NSURL *wrappedURL = UnscrollWrappedInstagramURL(url);
    if (wrappedURL != nil) {
        SEL continueSelector =
            @selector(application:continueUserActivity:restorationHandler:);
        id activityHandler = [self respondsToSelector:continueSelector]
            ? self
            : application.delegate;
        if ([activityHandler respondsToSelector:continueSelector]) {
            NSUserActivity *activity = [[NSUserActivity alloc]
                initWithActivityType:NSUserActivityTypeBrowsingWeb];
            activity.webpageURL = wrappedURL;
            return ((BOOL (*)(id, SEL, UIApplication *, NSUserActivity *, id))
                objc_msgSend)(activityHandler,
                              continueSelector,
                              application,
                              activity,
                              ^(__unused NSArray *restorableObjects) {});
        }
        url = wrappedURL;
    }

    return UnscrollOriginalOpenURL == NULL
        ? NO
        : UnscrollOriginalOpenURL(self, selector, application, url, options);
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
            UnscrollTeamIdentifier =
                [UnscrollKeychainAccessGroup componentsSeparatedByString:@"."]
                    .firstObject;
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

        UnscrollOriginalGroupContainer =
            (NSURL *(*)(id, SEL, NSString *))UnscrollReplaceMethod(
                [NSFileManager class],
                @selector(containerURLForSecurityApplicationGroupIdentifier:),
                (IMP)UnscrollGroupContainer);

        if (UnscrollIsExtensionProcess()) {
            return;
        }

        UnscrollOriginalAppStoreReceiptURL =
            (NSURL *(*)(id, SEL))UnscrollReplaceMethod(
                [NSBundle class],
                @selector(appStoreReceiptURL),
                (IMP)UnscrollAppStoreReceiptURL);

        UnscrollOriginalReelsObjects =
            (id (*)(id, SEL, id))UnscrollReplaceMethod(
                objc_getClass("_TtC23IGSundialFeedDataSource23IGSundialFeedDataSource"),
                @selector(objectsForListAdapter:),
                (IMP)UnscrollLimitReelsObjects);

        UnscrollOriginalHomeFeedObjects =
            (id (*)(id, SEL, id))UnscrollReplaceMethod(
                objc_getClass("IGMainFeedListAdapterDataSource"),
                @selector(objectsForListAdapter:),
                (IMP)UnscrollFilterHomeFeedObjects);

        UnscrollOriginalOpenURL =
            (BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))
                UnscrollReplaceMethod(
                    objc_getClass("IGAppCoordinator"),
                    @selector(application:openURL:options:),
                    (IMP)UnscrollOpenURL);
    }
}
