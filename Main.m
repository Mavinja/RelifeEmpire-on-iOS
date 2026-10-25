// Copyright (c) 2025 Project Nova LLC

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#define API_URL @"http://projectrelifeog.duckdns.org:3551"
#define EPIC_GAMES_URL @"epicgames.com"

// =======================================================
// 1. SAFARI OPENURL HOOK (BLOCKIERT DAS ÖFFNEN VON SAFARI)
// =======================================================

typedef BOOL (*OpenURLImp)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL));
static OpenURLImp orig_openURL = NULL;

BOOL my_openURL(id self, SEL _cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
    NSString *urlString = [url absoluteString];
    
    // Wenn Fortnite versucht, eine Webview / Safari-Seite für den Login zu öffnen
    if (urlString && ([urlString containsString:@"epicgames.com"] || [urlString containsString:@"/id/login"] || [urlString containsString:@"/id/authorize"])) {
        NSLog(@"[Relife] External Safari launch blocked: %@", urlString);
        
        // Bricht den Browser-Start ab
        if (completion) {
            completion(NO);
        }
        return NO;
    }
    
    return orig_openURL(self, _cmd, url, options, completion);
}

// =======================================================
// 2. NETWORK REDIRECT (LEITET NETWORK TRAFFIC ZUM BACKEND)
// =======================================================

@interface CustomURLProtocol : NSURLProtocol
@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request 
{  
    NSString *absoluteURLString = [[request URL] absoluteString];
    if (absoluteURLString && [absoluteURLString containsString:EPIC_GAMES_URL] && ![absoluteURLString containsString:@"/CloudDir/"]) {
        if ([NSURLProtocol propertyForKey:@"Handled" inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    NSMutableURLRequest *modifiedRequest = [[self request] mutableCopy];
    NSString *urlString = [modifiedRequest.URL absoluteString];

    if ([urlString containsString:@"/id/login"] || [urlString containsString:@"/id/authorize"]) {
        NSString *redirectURL = [NSString stringWithFormat:@"%@/account/api/oauth/authorize", API_URL];
        [modifiedRequest setURL:[NSURL URLWithString:redirectURL]];
    } else {
        NSString *originalPath = [modifiedRequest.URL path];
        NSURLComponents *components = [NSURLComponents componentsWithString:API_URL];
        components.path = originalPath;

        NSURLComponents *originalComponents = [NSURLComponents componentsWithURL:modifiedRequest.URL resolvingAgainstBaseURL:NO];
        if (originalComponents.queryItems.count > 0) {
            NSMutableArray<NSURLQueryItem *> *cleanItems = [NSMutableArray array];
            for (NSURLQueryItem *item in originalComponents.queryItems) {
                NSString *decodedValue = item.value ? [item.value stringByRemovingPercentEncoding] : @"";
                [cleanItems addObject:[NSURLQueryItem queryItemWithName:item.name value:decodedValue]];
            }
            components.queryItems = cleanItems;
        }
        [modifiedRequest setURL:components.URL];
    }

    [NSURLProtocol setProperty:@YES forKey:@"Handled" inRequest:modifiedRequest];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [[self client] URLProtocol:self
        wasRedirectedToRequest:modifiedRequest
              redirectResponse:nil];
#pragma clang diagnostic pop
}

- (void)stopLoading
{
}

@end

// =======================================================
// 3. CONSTRUCTOR ENTRY POINT
// =======================================================

__attribute__((constructor))
static void entry(void)
{
    @autoreleasepool {
        // ATS deaktivieren
        void *handle = dlopen(NULL, RTLD_NOW);
        if (handle) {
            typedef void (*DisableATSFunc)(BOOL);
            DisableATSFunc disableATS = (DisableATSFunc)dlsym(handle, "_CFNetworkHTTPConnectionDisableAppTransportSecurity");
            if (disableATS) {
                disableATS(YES);
                NSLog(@"[Relife] ATS disabled.");
            }
            dlclose(handle);
        }

        // openURL Hook für UIApplication registrieren
        Method origMethod = class_getInstanceMethod([UIApplication class], @selector(openURL:options:completionHandler:));
        if (origMethod) {
            orig_openURL = (OpenURLImp)method_getImplementation(origMethod);
            method_setImplementation(origMethod, (IMP)my_openURL);
            NSLog(@"[Relife] UIApplication openURL Hook successfully active!");
        }

        // CustomURLProtocol registrieren
        [NSURLProtocol registerClass:[CustomURLProtocol class]];
        NSLog(@"[Relife] CustomURLProtocol registered!");
    }
}
