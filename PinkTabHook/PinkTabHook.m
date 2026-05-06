#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <math.h>
#import <objc/runtime.h>

// Not always exposed as a public SDK header; keep the standard dyld interpose record shape.
#define DYLD_INTERPOSE(_replacement, _replacee)                                                           \
    __attribute__((used)) static struct {                                                                 \
        const void *replacement;                                                                          \
        const void *replacee;                                                                             \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {                           \
        (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee};

// LockDown Browser calls Security.framework to verify the app seal after re-signing.
// Interposing these avoids the "corrupt application bundle" exit while tabs stay themed.
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

DYLD_INTERPOSE(pinkstub_SecStaticCodeCheckValidity, SecStaticCodeCheckValidity)
DYLD_INTERPOSE(pinkstub_SecCodeCheckValidity, SecCodeCheckValidity)
DYLD_INTERPOSE(pinkstub_SecCodeCheckValidityWithErrors, SecCodeCheckValidityWithErrors)

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
