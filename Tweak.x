#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>

#pragma mark - Toast Helper

static void VSToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width - 40, 80)];
        win.windowLevel = UIWindowLevelAlert + 500;
        win.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
        win.layer.cornerRadius = 14;
        win.center = CGPointMake(UIScreen.mainScreen.bounds.size.width/2,
                                 UIScreen.mainScreen.bounds.size.height - 140);

        UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(win.bounds, 12, 8)];
        l.text = msg;
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.numberOfLines = 0;
        l.font = [UIFont boldSystemFontOfSize:14];
        l.adjustsFontSizeToFitWidth = YES;
        [win addSubview:l];
        win.hidden = NO;
        win.rootViewController = [UIViewController new];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ win.hidden = YES; });
    });
}

#pragma mark - Runtime Selector Scanner

@interface VSRuntimeScanner : NSObject
+ (UIViewController *)topVC;
+ (UIViewController *)findEditorVC;
+ (id)callFirstResponderSelector:(NSArray<NSString *> *)names
                        onObject:(id)obj
                       withArg1:(id)arg1
                       withArg2:(id)arg2
                        returns:(BOOL *)ok;

// Tìm property/method chứa keyword
+ (NSArray<NSString *> *)methodsOf:(id)obj matching:(NSString *)keyword;
+ (NSArray<NSString *> *)propertiesOf:(id)obj matching:(NSString *)keyword;
@end

@implementation VSRuntimeScanner

+ (UIViewController *)topVC {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *vc = keyWin.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (UIViewController *)findEditorVC {
    UIViewController *root = [self topVC];
    return [self findVCIn:root matching:^BOOL(UIViewController *vc) {
        NSString *n = NSStringFromClass(vc.class);
        return [n containsString:@"Editor"] || [n containsString:@"Timeline"]
            || [n containsString:@"Project"] || [n containsString:@"Compose"]
            || [n containsString:@"Main"];
    }];
}

+ (UIViewController *)findVCIn:(UIViewController *)vc matching:(BOOL(^)(UIViewController *))match {
    if (!vc) return nil;
    if (match(vc)) return vc;
    for (UIViewController *c in vc.childViewControllers) {
        UIViewController *r = [self findVCIn:c matching:match];
        if (r) return r;
    }
    if (vc.presentedViewController) {
        UIViewController *r = [self findVCIn:vc.presentedViewController matching:match];
        if (r) return r;
    }
    return nil;
}

+ (NSArray<NSString *> *)methodsOf:(id)obj matching:(NSString *)keyword {
    NSMutableArray *out = [NSMutableArray array];
    Class cls = object_getClass(obj);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *sel = NSStringFromSelector(method_getName(methods[i]));
        if ([sel.lowercaseString containsString:keyword.lowercaseString]) {
            [out addObject:sel];
        }
    }
    free(methods);
    // Duyệt superclass nữa
    Class super = class_getSuperclass(cls);
    while (super && super != [NSObject class]) {
        methods = class_copyMethodList(super, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *sel = NSStringFromSelector(method_getName(methods[i]));
            if ([sel.lowercaseString containsString:keyword.lowercaseString]) {
                [out addObject:sel];
            }
        }
        free(methods);
        super = class_getSuperclass(super);
    }
    return out;
}

+ (NSArray<NSString *> *)propertiesOf:(id)obj matching:(NSString *)keyword {
    NSMutableArray *out = [NSMutableArray array];
    Class cls = object_getClass(obj);
    while (cls && cls != [NSObject class]) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
            if ([name.lowercaseString containsString:keyword.lowercaseString]) {
                [out addObject:name];
            }
        }
        free(props);
        cls = class_getSuperclass(cls);
    }
    return out;
}

+ (id)callFirstResponderSelector:(NSArray<NSString *> *)names
                        onObject:(id)obj
                       withArg1:(id)arg1
                       withArg2:(id)arg2
                        returns:(BOOL *)ok {
    if (ok) *ok = NO;
    if (!obj) return nil;
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if (![obj respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
        NSUInteger nargs = sig.numberOfArguments;
        if (nargs == 2 && !arg1) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id r = [obj performSelector:sel];
            #pragma clang diagnostic pop
            if (ok) *ok = YES;
            return r;
        } else if (nargs == 3 && arg1 && !arg2) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id r = [obj performSelector:sel withObject:arg1];
            #pragma clang diagnostic pop
            if (ok) *ok = YES;
            return r;
        } else if (nargs == 4 && arg1 && arg2) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:obj];
            [inv setSelector:sel];
            [inv setArgument:&arg1 atIndex:2];
            [inv setArgument:&arg2 atIndex:3];
            [inv invoke];
            __unsafe_unretained id r = nil;
            [inv getReturnValue:&r];
            if (ok) *ok = YES;
            return r;
        }
    }
    return nil;
}

@end

#pragma mark - Core

@interface VSToolCore : NSObject
+ (void)autoSplitBeat;
+ (void)batchImportQR;
+ (void)batchImportImages;
+ (NSArray *)collectBeatsFrom:(id)editor;
+ (NSArray *)collectSelectedSegmentsFrom:(id)editor;
@end

@implementation VSToolCore

#pragma mark - AUTO CHIA BEAT

+ (NSArray *)collectBeatsFrom:(id)editor {
    // Thử property chứa "beat"
    NSArray *props = [VSRuntimeScanner propertiesOf:editor matching:@"beat"];
    for (NSString *p in props) {
        @try {
            id v = [editor valueForKey:p];
            if ([v isKindOfClass:[NSArray class]] && [v count] > 0) return v;
        } @catch (NSException *e) {}
    }
    // Thử property chứa "split" hoặc "marker"
    for (NSString *kw in @[@"split", @"marker", @"cut"]) {
        for (NSString *p in [VSRuntimeScanner propertiesOf:editor matching:kw]) {
            @try {
                id v = [editor valueForKey:p];
                if ([v isKindOfClass:[NSArray class]] && [v count] > 0) return v;
            } @catch (NSException *e) {}
        }
    }
    return nil;
}

+ (void)autoSplitBeat {
    id editor = [VSRuntimeScanner findEditorVC];
    if (!editor) { VSToast(@"❌ Chưa mở project"); return; }

    // 1. Thử gọi method auto-detect beat nếu có
    NSArray *detectMethods = [VSRuntimeScanner methodsOf:editor matching:@"detectbeat"];
    if (detectMethods.count == 0) {
        detectMethods = @[@"detectBeats", @"autoDetectBeats", @"analyzeBeats",
                          @"detectBeatPoints", @"findBeats"];
    }
    BOOL ok = NO;
    [VSRuntimeScanner callFirstResponderSelector:detectMethods
                                        onObject:editor
                                       withArg1:nil
                                       withArg2:nil
                                        returns:&ok];

    // 2. Sau khi detect, đợi 0.5s rồi lấy beats
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSArray *beats = [self collectBeatsFrom:editor];
        if (!beats || beats.count == 0) {
            VSToast(@"⚠️ Không tìm thấy beat. Hãy bấm Detect Beat trong app trước");
            return;
        }

        // 3. Gọi split
        NSArray *splitSels = @[@"splitSegmentsAtBeatPoints:",
                               @"splitAtBeatPoints:",
                               @"splitSegmentsWithBeats:",
                               @"applyBeatSplit:",
                               @"splitSegmentsAtBeats:"];
        BOOL did = NO;
        [VSRuntimeScanner callFirstResponderSelector:splitSels
                                            onObject:editor
                                           withArg1:beats
                                           withArg2:nil
                                            returns:&did];

        // Fallback: gọi split từng beat
        if (!did) {
            NSArray *singleSels = @[@"splitSegmentAtTime:", @"splitAtTime:", @"addSplitAt:"];
            for (id beat in beats) {
                [VSRuntimeScanner callFirstResponderSelector:singleSels
                                                    onObject:editor
                                                   withArg1:beat
                                                   withArg2:nil
                                                    returns:&did];
            }
        }

        if (did) {
            VSToast([NSString stringWithFormat:@"✅ Đã chia %lu beat", (unsigned long)beats.count]);
        } else {
            VSToast(@"❌ Không tìm thấy hàm split. Xem log");
            NSLog(@"[VSTool] Split methods: %@", [VSRuntimeScanner methodsOf:editor matching:@"split"]);
        }
    });
}

#pragma mark - BATCH QR

+ (void)batchImportQR {
    [VSToolCore presentPickerWithTag:1];
}

#pragma mark - BATCH IMAGES

+ (void)batchImportImages {
    [VSToolCore presentPickerWithTag:2];
}

+ (void)presentPickerWithTag:(NSInteger)tag {
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.selectionLimit = 0;
    cfg.filter = [PHPickerFilter imagesFilter];

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    picker.view.tag = tag;
    objc_setAssociatedObject(picker, "VSTag", @(tag), OBJC_ASSOCIATION_RETAIN);

    // Delegate dùng class để không cần giữ instance
    picker.delegate = (id<PHPickerViewControllerDelegate>)[VSPickerDelegate shared];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[VSRuntimeScanner topVC] presentViewController:picker animated:YES completion:nil];
    });
}

+ (void)processQRImages:(NSArray<UIImage *> *)images {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        CIDetector *det = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                             context:nil
                                             options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        for (UIImage *img in images) {
            CIImage *ci = [[CIImage alloc] initWithImage:img];
            NSArray *feats = [det featuresInImage:ci];
            for (CIQRCodeFeature *f in feats) {
                if (f.messageString.length) [texts addObject:f.messageString];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleQRTexts:texts];
        });
    });
}

+ (void)handleQRTexts:(NSArray<NSString *> *)texts {
    if (texts.count == 0) { VSToast(@"⚠️ Không thấy QR nào"); return; }

    id editor = [VSRuntimeScanner findEditorVC];
    BOOL did = NO;

    // Thử gọi method import hàng loạt
    NSArray *sels = @[@"importQRTextsToSelectedSegments:",
                      @"importQRTexts:",
                      @"setQRTextsToSegments:",
                      @"importQRCodeTexts:",
                      @"applyQRTexts:"];
    [VSRuntimeScanner callFirstResponderSelector:sels
                                        onObject:editor
                                       withArg1:texts
                                       withArg2:nil
                                        returns:&did];

    // Fallback: gán từng text vào từng segment đã chọn
    if (!did) {
        NSArray *segs = [self collectSelectedSegmentsFrom:editor];
        NSArray *oneSels = @[@"setQRText:forSegment:", @"setQRCodeText:forSegment:"];
        NSUInteger n = MIN(texts.count, segs.count);
        for (NSUInteger i = 0; i < n; i++) {
            [VSRuntimeScanner callFirstResponderSelector:oneSels
                                                onObject:editor
                                               withArg1:texts[i]
                                               withArg2:segs[i]
                                                returns:&did];
        }
    }

    // Cuối cùng: copy clipboard để dán tay
    UIPasteboard.generalPasteboard.string = [texts componentsJoinedByString:@"\n"];

    NSString *preview = [[texts subarrayWithRange:NSMakeRange(0, MIN(3, texts.count))]
                         componentsJoinedByString:@"\n"];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"📷 Đã quét %lu QR", (unsigned long)texts.count]
        message:[NSString stringWithFormat:@"%@%@\n\n(Đã copy clipboard)", preview,
                 texts.count > 3 ? @"\n..." : @""]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[VSRuntimeScanner topVC] presentViewController:a animated:YES completion:nil];
}

#pragma mark - Selected segments

+ (NSArray *)collectSelectedSegmentsFrom:(id)editor {
    NSArray *props = [VSRuntimeScanner propertiesOf:editor matching:@"select"];
    for (NSString *p in props) {
        @try {
            id v = [editor valueForKey:p];
            if ([v isKindOfClass:[NSArray class]] && [v count] > 0) return v;
        } @catch (NSException *e) {}
    }
    // Fallback property tên "segments"
    for (NSString *p in [VSRuntimeScanner propertiesOf:editor matching:@"segment"]) {
        @try {
            id v = [editor valueForKey:p];
            if ([v isKindOfClass:[NSArray class]] && [v count] > 0) return v;
        } @catch (NSException *e) {}
    }
    return nil;
}

+ (void)processBatchImages:(NSArray<UIImage *> *)images {
    id editor = [VSRuntimeScanner findEditorVC];
    if (!editor) { VSToast(@"❌ Chưa mở project"); return; }

    NSArray *segs = [self collectSelectedSegmentsFrom:editor];
    if (!segs || segs.count == 0) {
        VSToast(@"⚠️ Chưa chọn phân đoạn nào");
        return;
    }

    BOOL did = NO;
    // 1. Cố gọi method 2-arg import
    NSArray *bulkSels = @[@"importImages:toSegments:",
                          @"setImages:forSegments:",
                          @"applyImages:toSegments:"];
    [VSRuntimeScanner callFirstResponderSelector:bulkSels
                                        onObject:editor
                                       withArg1:images
                                       withArg2:segs
                                        returns:&did];

    // 2. Fallback loop từng ảnh
    if (!did) {
        NSArray *oneSels = @[@"setImage:forSegment:",
                             @"importImage:forSegment:",
                             @"applyImage:toSegment:"];
        NSUInteger n = MIN(images.count, segs.count);
        for (NSUInteger i = 0; i < n; i++) {
            [VSRuntimeScanner callFirstResponderSelector:oneSels
                                                onObject:editor
                                               withArg1:images[i]
                                               withArg2:segs[i]
                                                returns:&did];
        }
    }

    if (did) {
        VSToast([NSString stringWithFormat:@"✅ Đã nhập %lu ảnh", (unsigned long)images.count]);
    } else {
        VSToast(@"⚠️ Không tìm được hàm import, xem Console log");
        NSLog(@"[VSTool] Import methods: %@", [VSRuntimeScanner methodsOf:editor matching:@"image"]);
    }
}

@end

#pragma mark - Picker Delegate

@interface VSPickerDelegate : NSObject <PHPickerViewControllerDelegate>
+ (instancetype)shared;
@end

@implementation VSPickerDelegate
+ (instancetype)shared {
    static VSPickerDelegate *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [VSPickerDelegate new]; });
    return d;
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSNumber *tagN = objc_getAssociatedObject(picker, "VSTag");
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSMutableArray<UIImage *> *imgs = [NSMutableArray array];
    dispatch_group_t g = dispatch_group_create();
    for (PHPickerResult *r in results) {
        dispatch_group_enter(g);
        [r.itemProvider loadObjectOfClass:[UIImage class]
                        completionHandler:^(UIImage *img, NSError *err){
            @synchronized (imgs) { if (img) [imgs addObject:img]; }
            dispatch_group_leave(g);
        }];
    }
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        if (tagN.integerValue == 1) [VSToolCore processQRImages:imgs];
        else if (tagN.integerValue == 2) [VSToolCore processBatchImages:imgs];
    });
}
@end

#pragma mark - Floating Button

@interface VSFloatingButton : UIButton
@property (nonatomic, strong) UIWindow *overlay;
@end

@implementation VSFloatingButton

+ (instancetype)shared {
    static VSFloatingButton *btn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        btn = [VSFloatingButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, 0, 56, 56);
        btn.layer.cornerRadius = 28;
        btn.backgroundColor = [UIColor colorWithRed:0.58 green:0.18 blue:0.92 alpha:0.95];
        btn.layer.shadowColor = UIColor.blackColor.CGColor;
        btn.layer.shadowOpacity = 0.5;
        btn.layer.shadowRadius = 6;
        btn.layer.shadowOffset = CGSizeMake(0, 2);
        [btn setTitle:@"🎬" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:26];
        [btn addTarget:btn action:@selector(btnTap:) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(pan:)];
        [btn addGestureRecognizer:pan];

        UIWindow *win = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        win.windowLevel = UIWindowLevelAlert + 100;
        win.backgroundColor = UIColor.clearColor;
        win.rootViewController = [UIViewController new];
        win.rootViewController.view.backgroundColor = UIColor.clearColor;

        btn.center = CGPointMake(70, UIScreen.mainScreen.bounds.size.height * 0.35);
        [win addSubview:btn];
        win.hidden = NO;
        btn.overlay = win;
    });
    return btn;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + p.x, self.center.y + p.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)btnTap:(id)s {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"🎬 VideoStar Tool"
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self;
        sheet.popoverPresentationController.sourceRect = self.bounds;
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"🥁 Auto chia beat"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [VSToolCore autoSplitBeat]; }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📷 Auto nhập QR hàng loạt"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [VSToolCore batchImportQR]; }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🖼️ Auto nhập ảnh vào phân đoạn đã chọn"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [VSToolCore batchImportImages]; }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔍 Debug selector (xem log)"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            id ed = [VSRuntimeScanner findEditorVC];
            NSLog(@"[VSTool] Editor class: %@", NSStringFromClass([ed class]));
            NSLog(@"[VSTool] split methods: %@", [VSRuntimeScanner methodsOf:ed matching:@"split"]);
            NSLog(@"[VSTool] beat methods: %@", [VSRuntimeScanner methodsOf:ed matching:@"beat"]);
            NSLog(@"[VSTool] image methods: %@", [VSRuntimeScanner methodsOf:ed matching:@"image"]);
            NSLog(@"[VSTool] qr methods: %@", [VSRuntimeScanner methodsOf:ed matching:@"qr"]);
            NSLog(@"[VSTool] select methods: %@", [VSRuntimeScanner methodsOf:ed matching:@"select"]);
            VSToast(@"Đã in selector ra Console (Xcode/Syslog)");
        }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"✖️ Đóng" style:UIAlertActionStyleCancel handler:nil]];

    [[VSRuntimeScanner topVC] presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Hook

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [VSFloatingButton shared];
    });
}
%end

%ctor {
    NSLog(@"[VSTool] Loaded on %@", [NSBundle mainBundle].bundleIdentifier);
}
