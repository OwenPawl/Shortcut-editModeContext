#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>

static void SetError(char **out, NSString *message) {
    if (out) *out = strdup(message.UTF8String ?: "Unknown native error");
}

static id Send0(id object, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static id Send1Error(id object, SEL selector, NSError **error) {
    return ((id (*)(id, SEL, NSError **))objc_msgSend)(object, selector, error);
}

static id Send3Error(id object, SEL selector, id first, id second, NSError **error) {
    return ((id (*)(id, SEL, id, id, NSError **))objc_msgSend)(object, selector,
                                                                  first, second, error);
}

static id Send4Error(id object, SEL selector, id first, id second, id third,
                     NSError **error) {
    return ((id (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(object, selector,
                                                                      first, second, third, error);
}

void *ShortcutLoadWorkflow(const char *path, char **errorText) {
    @autoreleasepool {
        @try {
            const char *frameworks[] = {
                     "/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",
                     "/System/Library/PrivateFrameworks/ShortcutsLanguage.framework/ShortcutsLanguage",
                     "/System/Library/PrivateFrameworks/ShortcutsAgent.framework/ShortcutsAgent",
                     NULL};
            for (unsigned i = 0; frameworks[i]; i++) {
                const char *framework = frameworks[i];
                if (!dlopen(framework, RTLD_NOW)) {
                    SetError(errorText, [NSString stringWithFormat:@"Cannot load %s: %s",
                                         framework, dlerror()]);
                    return NULL;
                }
            }
            NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:path]];
            if (!data) {
                SetError(errorText, @"Could not read input plist");
                return NULL;
            }
            if (data.length >= 4 && memcmp(data.bytes, "AEA1", 4) == 0) {
                SetError(errorText, @"Signed AEA1 .shortcut files are not workflow plists");
                return NULL;
            }
            NSError *error = nil;
            id plist = [NSPropertyListSerialization propertyListWithData:data options:0
                                                                   format:NULL error:&error];
            if (![plist isKindOfClass:NSDictionary.class] ||
                ![plist[@"WFWorkflowActions"] isKindOfClass:NSArray.class]) {
                SetError(errorText, error.localizedDescription ?: @"Input is not a Shortcut workflow plist");
                return NULL;
            }
            Class registryClass = NSClassFromString(@"WFActionRegistry");
            id registry = registryClass ? Send0(registryClass, @selector(sharedRegistry)) : nil;
            if (!registry) {
                SetError(errorText, @"WFActionRegistry is unavailable");
                return NULL;
            }
            ((void (*)(id, SEL))objc_msgSend)(registry, @selector(fill));
            NSUInteger (*state)(id, SEL) = (NSUInteger (*)(id, SEL))objc_msgSend;
            for (unsigned attempt = 0;
                 attempt < 1000 && state(registry, @selector(state)) != 2;
                 attempt++) usleep(10000);
            if (state(registry, @selector(state)) != 2) {
                SetError(errorText, @"Timed out filling WFActionRegistry");
                return NULL;
            }
            Class fileClass = NSClassFromString(@"WFWorkflowFile");
            Class workflowClass = NSClassFromString(@"WFWorkflow");
            if (!fileClass || !workflowClass) {
                SetError(errorText, @"WorkflowKit file or workflow class is unavailable");
                return NULL;
            }
            NSString *name = [[NSString stringWithUTF8String:path].lastPathComponent
                              stringByDeletingPathExtension];
            id file = Send3Error(Send0(fileClass, @selector(alloc)),
                                 @selector(initWithFileData:name:error:), data, name, &error);
            if (!file) {
                SetError(errorText, error.localizedDescription ?: @"WFWorkflowFile rejected input");
                return NULL;
            }
            id record = Send1Error(file, @selector(recordRepresentationWithError:), &error);
            if (!record) {
                SetError(errorText, error.localizedDescription ?: @"Record conversion failed");
                return NULL;
            }
            id workflow = Send4Error(Send0(workflowClass, @selector(alloc)),
                                     @selector(initWithRecord:reference:storageProvider:error:),
                                     record, nil, nil, &error);
            if (!workflow) {
                SetError(errorText, error.localizedDescription ?: @"WFWorkflow initialization failed");
                return NULL;
            }
            return (__bridge_retained void *)workflow;
        } @catch (NSException *exception) {
            SetError(errorText, [NSString stringWithFormat:@"%@: %@", exception.name,
                                 exception.reason ?: @"native exception"]);
            return NULL;
        }
    }
}
