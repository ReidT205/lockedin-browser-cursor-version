#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <objc/runtime.h>

// Not always exposed as a public SDK header; keep the standard dyld interpose record shape.
#define DYLD_INTERPOSE(_replacement, _replacee)                                                           \
    __attribute__((used)) static struct {                                                                 \
        const void *replacement;                                                                          \
        const void *replacee;                                                                             \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {                           \
        (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee};

// Respondus production Team ID (from the stock Info.plist / code signature).
static const char kVendorTeamID[] = "8CA6NAN723";

// --- Code signing: validity hooks (some paths only consult these) ---
static OSStatus pinkstub_SecStaticCodeCheckValidity(SecStaticCodeRef code, SecCSFlags flags, SecRequirementRef requirement) {
    (void)code;
    (void)flags;
    (void)requirement;
    return errSecSuccess;
}

static OSStatus pinkstub_SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement) {
    (void)code;
    (void)flags;
    (void)requirement;
    return errSecSuccess;
}

static OSStatus pinkstub_SecCodeCheckValidityWithErrors(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement,
                                                        CFErrorRef *errors) {
    (void)code;
    (void)flags;
    (void)requirement;
    if (errors) {
        *errors = NULL;
    }
    return errSecSuccess;
}

// --- Signing metadata: many apps read kSecCodeInfoTeamIdentifier after CopySigningInformation ---
typedef OSStatus (*SecCodeCopySigningInformation_fn)(SecCodeRef, SecCSFlags, CFDictionaryRef *_Nonnull);

static OSStatus pinkstub_SecCodeCopySigningInformation(SecCodeRef code, SecCSFlags flags, CFDictionaryRef *information) {
    static SecCodeCopySigningInformation_fn orig_fn;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        orig_fn = (SecCodeCopySigningInformation_fn)dlsym(RTLD_NEXT, "SecCodeCopySigningInformation");
    });
    if (!orig_fn || !information) {
        return errSecParam;
    }
    OSStatus st = orig_fn(code, flags, information);
    if (st != errSecSuccess || !*information) {
        return st;
    }
    CFMutableDictionaryRef m = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, *information);
    if (!m) {
        return st;
    }
    CFRelease(*information);
    *information = m;
    CFStringRef team =
        CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, kVendorTeamID, kCFStringEncodingUTF8, kCFAllocatorNull);
    if (team) {
        CFDictionarySetValue(m, kSecCodeInfoTeamIdentifier, team);
        CFRelease(team);
    }
    return errSecSuccess;
}

DYLD_INTERPOSE(pinkstub_SecStaticCodeCheckValidity, SecStaticCodeCheckValidity)
DYLD_INTERPOSE(pinkstub_SecCodeCheckValidity, SecCodeCheckValidity)
DYLD_INTERPOSE(pinkstub_SecCodeCheckValidityWithErrors, SecCodeCheckValidityWithErrors)
DYLD_INTERPOSE(pinkstub_SecCodeCopySigningInformation, SecCodeCopySigningInformation)

// ChromiumTabs inactive tabs use NSColor colorWithCalibratedWhite: 247/255 alpha: 1
static const CGFloat kInactiveTabWhite = 247.0 / 255.0;

// __mkGradient seeds a dark strip color with white 0.2, alpha 1
static const CGFloat kTabStripDarkWhite = 0.2;

static id (*orig_colorWithCalibratedWhite_alpha_)(id self, SEL _cmd, CGFloat white, CGFloat alpha);

static id swizzled_colorWithCalibratedWhite_alpha_(id self, SEL _cmd, CGFloat white, CGFloat alpha) {
    if (fabs(white - kInactiveTabWhite) < 1.0e-4 && alpha > 0.5) {
        return [NSColor colorWithCalibratedRed:1.0
                                         green:(CGFloat)(105.0 / 255.0)
                                          blue:(CGFloat)(180.0 / 255.0)
                                         alpha:alpha];
    }
    if (fabs(white - kTabStripDarkWhite) < 1.0e-4 && alpha > 0.9) {
        return [NSColor colorWithCalibratedRed:0.58
                                         green:0.08
                                          blue:0.32
                                         alpha:alpha];
    }
    return orig_colorWithCalibratedWhite_alpha_(self, _cmd, white, alpha);
}

__attribute__((constructor)) static void lockedin_pink_tabs_init(void) {
    Class cls = [NSColor class];
    SEL sel = @selector(colorWithCalibratedWhite:alpha:);
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        return;
    }
    orig_colorWithCalibratedWhite_alpha_ = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)swizzled_colorWithCalibratedWhite_alpha_);
}
