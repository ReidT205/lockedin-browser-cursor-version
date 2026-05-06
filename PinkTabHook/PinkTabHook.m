#import <AppKit/AppKit.h>
#import <math.h>
#import <objc/runtime.h>

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
