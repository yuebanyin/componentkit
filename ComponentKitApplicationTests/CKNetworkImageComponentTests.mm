/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <ComponentSnapshotTestCase/CKComponentSnapshotTestCase.h>

#import <ComponentKit/CKComponentLayout.h>
#import <ComponentKit/CKNetworkImageComponent.h>

#pragma mark - Helpers

static UIImage *ck_fakeImage(UIColor *imageBackgroundColor, CGSize size)
{
  size_t bytesPerRow = ((((size_t)size.width * 4)+31)&~0x1f);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(NULL,
                                               size.width,
                                               size.height,
                                               8,
                                               bytesPerRow,
                                               colorSpace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(colorSpace);

  CGContextSetAllowsAntialiasing(context, YES);
  CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
  CGContextSetFillColorWithColor(context, [imageBackgroundColor CGColor]);
  CGContextFillRect(context, {{0,0}, size});
  CGImageRef imageRef = CGBitmapContextCreateImage(context);
  CGContextRelease(context);
  UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
  CGImageRelease(imageRef);

  return image;
}

typedef id (^CKTestImageDownloaderDownloadImageBlock)(NSURL *url,
                                                      id caller,
                                                      dispatch_queue_t callbackQueue,
                                                      void (^downloadProgressBlock)(CGFloat),
                                                      void (^completion)(CGImageRef, NSError *));

@interface CKTestImageDownloader : NSObject <CKNetworkImageDownloading>
@end

@implementation CKTestImageDownloader
{
  CKTestImageDownloaderDownloadImageBlock _downloadImageBlock;
}

- (instancetype)initWithDownloadImageBlock:(CKTestImageDownloaderDownloadImageBlock)downloadImageBlock
{
  self = [super init];
  if (self) {
    _downloadImageBlock = [downloadImageBlock copy];
  }
  return self;
}

- (id)downloadImageWithURL:(NSURL *)URL
                    caller:(id)caller
             callbackQueue:(dispatch_queue_t)callbackQueue
     downloadProgressBlock:(void (^)(CGFloat))downloadProgressBlock
                completion:(void (^)(CGImageRef, NSError *))completion
{
  return _downloadImageBlock(URL, caller, callbackQueue, downloadProgressBlock, completion);
}

- (void)cancelImageDownload:(id)download { /* no-op */ }

@end

@interface CKControlledImageDownload : NSObject
- (instancetype)initWithURL:(NSURL *)URL
                     caller:(id)caller
              callbackQueue:(dispatch_queue_t)callbackQueue
                 completion:(void (^)(CGImageRef, NSError *))completion;
@property (nonatomic, copy, readonly) NSURL *URL;
@property (nonatomic, weak, readonly) id caller;
@property (nonatomic, retain, readonly) dispatch_queue_t callbackQueue;
@property (nonatomic, assign, readonly) NSUInteger cancellationCount;
@end

@interface CKControlledImageDownload ()
@property (nonatomic, copy) void (^completion)(CGImageRef, NSError *);
@property (nonatomic, assign, readwrite) NSUInteger cancellationCount;
@property (nonatomic, assign) BOOL completedDuringCancellation;
@end

@implementation CKControlledImageDownload

- (instancetype)initWithURL:(NSURL *)URL
                     caller:(id)caller
              callbackQueue:(dispatch_queue_t)callbackQueue
                 completion:(void (^)(CGImageRef, NSError *))completion
{
  self = [super init];
  if (self) {
    _URL = [URL copy];
    _caller = caller;
    _callbackQueue = callbackQueue;
    _completion = [completion copy];
  }
  return self;
}

@end

@interface CKControlledImageDownloader : NSObject <CKNetworkImageDownloading>
@property (nonatomic, copy, readonly) NSArray<CKControlledImageDownload *> *downloads;
@property (nonatomic, copy, readonly) NSArray<CKControlledImageDownload *> *canceledDownloads;
@property (nonatomic, strong) UIImage *imageToCompleteSynchronously;
@property (nonatomic, strong) UIImage *imageToCompleteDuringCancellation;
- (void)completeDownload:(CKControlledImageDownload *)download withImage:(UIImage *)image;
@end

@implementation CKControlledImageDownloader
{
  NSMutableArray<CKControlledImageDownload *> *_downloads;
  NSMutableArray<CKControlledImageDownload *> *_canceledDownloads;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _downloads = [NSMutableArray array];
    _canceledDownloads = [NSMutableArray array];
  }
  return self;
}

- (NSArray<CKControlledImageDownload *> *)downloads
{
  return [_downloads copy];
}

- (NSArray<CKControlledImageDownload *> *)canceledDownloads
{
  return [_canceledDownloads copy];
}

- (id)downloadImageWithURL:(NSURL *)URL
                    caller:(id)caller
             callbackQueue:(dispatch_queue_t)callbackQueue
     downloadProgressBlock:(void (^)(CGFloat))downloadProgressBlock
                completion:(void (^)(CGImageRef, NSError *))completion
{
  CKControlledImageDownload *download =
    [[CKControlledImageDownload alloc] initWithURL:URL
                                           caller:caller
                                    callbackQueue:callbackQueue
                                       completion:completion];
  [_downloads addObject:download];
  if (_imageToCompleteSynchronously) {
    completion(_imageToCompleteSynchronously.CGImage, nil);
  }
  return download;
}

- (void)cancelImageDownload:(id)download
{
  CKControlledImageDownload *controlledDownload = download;
  controlledDownload.cancellationCount++;
  [_canceledDownloads addObject:controlledDownload];

  if (_imageToCompleteDuringCancellation && !controlledDownload.completedDuringCancellation) {
    controlledDownload.completedDuringCancellation = YES;
    controlledDownload.completion(_imageToCompleteDuringCancellation.CGImage, nil);
  }
}

- (void)completeDownload:(CKControlledImageDownload *)download withImage:(UIImage *)image
{
  if (download.completion) {
    download.completion(image.CGImage, nil);
  }
}

@end

/** Different instances compare equal to verify that downloader identity, not object equality, owns a request. */
@interface CKEqualControlledImageDownloader : CKControlledImageDownloader
@end

@implementation CKEqualControlledImageDownloader

- (BOOL)isEqual:(id)object
{
  return [object isKindOfClass:[CKEqualControlledImageDownloader class]];
}

- (NSUInteger)hash
{
  return 1;
}

@end

static CKNetworkImageComponent *ck_networkImageComponent(NSURL *URL,
                                                         id<CKNetworkImageDownloading> downloader,
                                                         UIImage *defaultImage,
                                                         CGRect cropRect)
{
  return [CKNetworkImageComponent
          newWithURL:URL
          imageDownloader:downloader
          size:{}
          options:{
            .defaultImage = defaultImage,
            .cropRect = cropRect,
          }
          attributes:{}];
}

static NSSet<id<CKMountable>> *ck_mountComponent(CKComponent *component,
                                                 UIView *container,
                                                 NSSet<id<CKMountable>> *previouslyMountedComponents)
{
  const RCLayout layout = [component layoutThatFits:{{50, 50}, {50, 50}} parentSize:{50, 50}];
  return CKMountComponentLayout(layout, container, previouslyMountedComponents, nil);
}

static CKComponent *ck_placeholderComponent()
{
  return [CKComponent newWithView:{[UIView class]} size:{}];
}

#pragma mark - Tests

@interface CKNetworkImageComponentTests : CKComponentSnapshotTestCase
@end

@implementation CKNetworkImageComponentTests

- (void)setUp
{
  [super setUp];
  self.recordMode = NO;
}

- (void)testWhenNoDefaultImageIsGivenImageViewImageIsNotSetToDefaultImage
{
  CKNetworkImageComponent *c =
  [CKNetworkImageComponent
   newWithURL:nil
   imageDownloader:nil
   size:{}
   options:{}
   attributes:{
     {{@selector(setBackgroundColor:), [UIColor redColor]}},
   }];

  static CKSizeRange kSize = {{50, 50}, {50, 50}};
  CKSnapshotVerifyComponent(c, kSize, nil);
}

- (void)testWhenDefaultImageIsGivenImageViewImageIsSetToDefaultImage
{
  CKNetworkImageComponent *c =
  [CKNetworkImageComponent
   newWithURL:nil
   imageDownloader:nil
   size:{}
   options:{
     .defaultImage = ck_fakeImage([UIColor greenColor], CGSizeMake(50, 50)),
   }
   attributes:{
     {{@selector(setBackgroundColor:), [UIColor redColor]}},
   }];

  static CKSizeRange kSize = {{50, 50}, {50, 50}};
  CKSnapshotVerifyComponent(c, kSize, nil);
}

- (void)testWhenURLIsNilImageDownloaderIsNotCalled
{
  CKTestImageDownloader *imageDownloader =
    [[CKTestImageDownloader alloc] initWithDownloadImageBlock:^id(NSURL *url,
                                                                  id caller,
                                                                  dispatch_queue_t callbackQueue,
                                                                  void (^downloadProgressBlock)(CGFloat),
                                                                  void (^completion)(CGImageRef, NSError *)) {
      // Fake image downloader immediately returns a blue image, but since component
      // URL is nil, this image will never be used.
      completion(ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50)).CGImage, nil);
      return nil;
  }];

  CKNetworkImageComponent *c =
  [CKNetworkImageComponent
   newWithURL:nil
   imageDownloader:imageDownloader
   size:{}
   options:{}
   attributes:{
     // Snapshot will show a red image, not the purple image provided by the image downloader.
     {{@selector(setBackgroundColor:), [UIColor redColor]}},
   }];

  static CKSizeRange kSize = {{50, 50}, {50, 50}};
  CKSnapshotVerifyComponent(c, kSize, nil);
}

- (void)testWhenURLIsNotNilAndImageDownloaderCallsCompletionBlockWithImageThatImageIsSetAsTheImageViewImageInsteadOfTheDefaultImage
{
  CKTestImageDownloader *imageDownloader =
    [[CKTestImageDownloader alloc] initWithDownloadImageBlock:^id(NSURL *url,
                                                                  id caller,
                                                                  dispatch_queue_t callbackQueue,
                                                                  void (^downloadProgressBlock)(CGFloat),
                                                                  void (^completion)(CGImageRef, NSError *)) {
      // This half-transparent blue image will be overlaid on top of the red background image.
      UIImage *blueImage = ck_fakeImage([UIColor colorWithRed:0 green:0 blue:1 alpha:.5],
                                        CGSizeMake(50, 50));
      completion(blueImage.CGImage, nil);
      return nil;
  }];

  CKNetworkImageComponent *c =
  [CKNetworkImageComponent
   newWithURL:[NSURL URLWithString:@"http://literally-any-non-nil-url-can-be-used-here.com"]
   imageDownloader:imageDownloader
   size:{}
   options:{
     // This opaque green default image will be replaced in favor of the image provided by the image downloader.
     .defaultImage = ck_fakeImage([UIColor greenColor], CGSizeMake(50, 50)),
   }
   attributes:{
     {{@selector(setBackgroundColor:), [UIColor redColor]}},
   }];

  static CKSizeRange kSize = {{50, 50}, {50, 50}};
  CKSnapshotVerifyComponent(c, kSize, nil);
}

- (void)testCropRectLimitsTheSizeOfTheImageToTheSpecifiedRect
{
  CKNetworkImageComponent *c =
  [CKNetworkImageComponent
   newWithURL:nil
   imageDownloader:nil
   size:{}
   options:{
     .cropRect = CGRectMake(0, 0, 40, 40),
     .defaultImage = ck_fakeImage([UIColor greenColor], CGSizeMake(50, 50)),
   }
   attributes:{
     {{@selector(setBackgroundColor:), [UIColor redColor]}},
   }];

  static CKSizeRange kSize = {{50, 50}, {50, 50}};
  CKSnapshotVerifyComponent(c, kSize, nil);
}


- (void)testChangingURLAndDownloaderCancelsExactlyOnceThroughTheOriginatingDownloader
{
  NSURL *URLA = [NSURL URLWithString:@"https://example.com/a.png"];
  NSURL *URLB = [NSURL URLWithString:@"https://example.com/b.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloaderA = [CKControlledImageDownloader new];
  CKControlledImageDownloader *downloaderB = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URLA, downloaderA, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  CKControlledImageDownload *downloadA = downloaderA.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URLB, downloaderB, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);

  XCTAssertEqual(componentB.mountedView, imageView);
  XCTAssertEqual(downloaderA.downloads.count, 1u);
  XCTAssertEqual(downloaderB.downloads.count, 1u);
  XCTAssertEqualObjects(downloaderA.canceledDownloads, (@[downloadA]));
  XCTAssertEqual(downloaderB.canceledDownloads.count, 0u);
  XCTAssertEqual(downloadA.cancellationCount, 1u);
  XCTAssertEqual(downloaderA.downloads.firstObject.callbackQueue, dispatch_get_main_queue());
  XCTAssertEqual(downloaderB.downloads.firstObject.callbackQueue, dispatch_get_main_queue());

  CKUnmountComponents(mountedComponents);
}

- (void)testReplacingEqualDownloaderInstanceForSameURLRestartsWhilePreservingViewIdentity
{
  NSURL *URL = [NSURL URLWithString:@"https://example.com/image.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  CKEqualControlledImageDownloader *downloaderA = [CKEqualControlledImageDownloader new];
  CKEqualControlledImageDownloader *downloaderB = [CKEqualControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URL, downloaderA, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  CKControlledImageDownload *downloadA = downloaderA.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URL, downloaderB, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);

  XCTAssertEqual(componentB.mountedView, imageView);
  XCTAssertEqualObjects(downloaderA.canceledDownloads, (@[downloadA]));
  XCTAssertEqual(downloadA.cancellationCount, 1u);
  XCTAssertEqual(downloaderB.downloads.count, 1u);
  XCTAssertEqual(downloaderB.canceledDownloads.count, 0u);
  XCTAssertEqual(downloaderB.downloads.firstObject.callbackQueue, dispatch_get_main_queue());

  CKUnmountComponents(mountedComponents);
}

- (void)testDownloaderReplacementCanRetainLoadedImageUntilReplacementCompletes
{
  NSURL *URL = [NSURL URLWithString:@"https://example.com/image.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *imageA = ck_fakeImage([UIColor redColor], CGSizeMake(50, 50));
  UIImage *imageB = ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloaderA = [CKControlledImageDownloader new];
  CKControlledImageDownloader *downloaderB = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URL, downloaderA, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  [downloaderA completeDownload:downloaderA.downloads.firstObject withImage:imageA];
  XCTAssertEqual(imageView.image.CGImage, imageA.CGImage);

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URL, downloaderB, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);

  XCTAssertEqual(componentB.mountedView, imageView);
  XCTAssertEqual(downloaderA.canceledDownloads.count, 0u);
  XCTAssertEqual(downloaderB.downloads.count, 1u);
  XCTAssertEqual(imageView.image.CGImage, imageA.CGImage);

  [downloaderB completeDownload:downloaderB.downloads.firstObject withImage:imageB];
  XCTAssertEqual(imageView.image.CGImage, imageB.CGImage);

  CKUnmountComponents(mountedComponents);
}

- (void)testOutOfOrderCompletionCannotReplaceNewerImage
{
  NSURL *URLA = [NSURL URLWithString:@"https://example.com/a.png"];
  NSURL *URLB = [NSURL URLWithString:@"https://example.com/b.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *imageA = ck_fakeImage([UIColor redColor], CGSizeMake(50, 50));
  UIImage *imageB = ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URLA, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  CKControlledImageDownload *downloadA = downloader.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URLB, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);
  CKControlledImageDownload *downloadB = downloader.downloads.lastObject;

  [downloader completeDownload:downloadB withImage:imageB];
  XCTAssertEqual(imageView.image.CGImage, imageB.CGImage);
  [downloader completeDownload:downloadA withImage:imageA];
  XCTAssertEqual(imageView.image.CGImage, imageB.CGImage);
  XCTAssertEqual(downloadA.cancellationCount, 1u);
  XCTAssertEqual(downloadB.cancellationCount, 0u);

  CKUnmountComponents(mountedComponents);
}

- (void)testStaleCompletionCannotPreventNewerRequestCancellation
{
  NSURL *URLA = [NSURL URLWithString:@"https://example.com/a.png"];
  NSURL *URLB = [NSURL URLWithString:@"https://example.com/b.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *staleImage = ck_fakeImage([UIColor redColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URLA, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  CKControlledImageDownload *downloadA = downloader.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URLB, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);
  CKControlledImageDownload *downloadB = downloader.downloads.lastObject;
  [downloader completeDownload:downloadA withImage:staleImage];

  mountedComponents = ck_mountComponent(ck_placeholderComponent(), container, mountedComponents);

  XCTAssertEqual(downloadA.cancellationCount, 1u);
  XCTAssertEqual(downloadB.cancellationCount, 1u);
  XCTAssertEqualObjects(downloader.canceledDownloads, (@[downloadA, downloadB]));

  CKUnmountComponents(mountedComponents);
}

- (void)testSynchronousCompletionDisplaysImageWithoutLeavingCancelableWork
{
  NSURL *URL = [NSURL URLWithString:@"https://example.com/image.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *synchronousImage = ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  downloader.imageToCompleteSynchronously = synchronousImage;
  UIView *container = [UIView new];

  CKNetworkImageComponent *component =
    ck_networkImageComponent(URL, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(component, container, nil);
  UIImageView *imageView = (UIImageView *)component.mountedView;
  CKControlledImageDownload *download = downloader.downloads.firstObject;

  XCTAssertEqual(imageView.image.CGImage, synchronousImage.CGImage);
  XCTAssertEqual(download.callbackQueue, dispatch_get_main_queue());

  mountedComponents = ck_mountComponent(ck_placeholderComponent(), container, mountedComponents);

  XCTAssertEqual(download.cancellationCount, 0u);
  XCTAssertEqual(downloader.canceledDownloads.count, 0u);

  CKUnmountComponents(mountedComponents);
}

- (void)testCompletionInvokedDuringCancellationIsIgnored
{
  NSURL *URLA = [NSURL URLWithString:@"https://example.com/a.png"];
  NSURL *URLB = [NSURL URLWithString:@"https://example.com/b.png"];
  UIImage *defaultImageA = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *defaultImageB = ck_fakeImage([UIColor greenColor], CGSizeMake(50, 50));
  UIImage *cancellationImage = ck_fakeImage([UIColor redColor], CGSizeMake(50, 50));
  UIImage *imageB = ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  downloader.imageToCompleteDuringCancellation = cancellationImage;
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URLA, downloader, defaultImageA, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  CKControlledImageDownload *downloadA = downloader.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URLB, downloader, defaultImageB, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);
  CKControlledImageDownload *downloadB = downloader.downloads.lastObject;

  XCTAssertEqual(downloadA.cancellationCount, 1u);
  XCTAssertEqualObjects(imageView.image, defaultImageB);
  XCTAssertEqual(downloader.downloads.count, 2u);

  [downloader completeDownload:downloadB withImage:imageB];
  XCTAssertEqual(imageView.image.CGImage, imageB.CGImage);

  CKUnmountComponents(mountedComponents);
}

- (void)testReusePoolEntryCancelsAndInvalidatesAndLeavingStartsOneFreshRequest
{
  NSURL *URL = [NSURL URLWithString:@"https://example.com/image.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  UIImage *lateImage = ck_fakeImage([UIColor redColor], CGSizeMake(50, 50));
  UIImage *freshImage = ck_fakeImage([UIColor blueColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *component =
    ck_networkImageComponent(URL, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(component, container, nil);
  UIImageView *imageView = (UIImageView *)component.mountedView;
  CKControlledImageDownload *firstDownload = downloader.downloads.firstObject;

  mountedComponents = ck_mountComponent(ck_placeholderComponent(), container, mountedComponents);

  XCTAssertTrue(imageView.hidden);
  XCTAssertEqualObjects(imageView.image, defaultImage);
  XCTAssertEqual(firstDownload.cancellationCount, 1u);
  [downloader completeDownload:firstDownload withImage:lateImage];
  XCTAssertEqualObjects(imageView.image, defaultImage);

  CKNetworkImageComponent *reusedComponent =
    ck_networkImageComponent(URL, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(reusedComponent, container, mountedComponents);
  CKControlledImageDownload *freshDownload = downloader.downloads.lastObject;

  XCTAssertEqual(reusedComponent.mountedView, imageView);
  XCTAssertFalse(imageView.hidden);
  XCTAssertEqual(downloader.downloads.count, 2u);
  XCTAssertEqual(freshDownload.callbackQueue, dispatch_get_main_queue());

  [downloader completeDownload:firstDownload withImage:lateImage];
  XCTAssertEqualObjects(imageView.image, defaultImage);
  [downloader completeDownload:freshDownload withImage:freshImage];
  XCTAssertEqual(imageView.image.CGImage, freshImage.CGImage);

  CKUnmountComponents(mountedComponents);
}

- (void)testDefaultAndCropOnlyUpdatesDoNotRestartOrInvalidateRequest
{
  NSURL *URL = [NSURL URLWithString:@"https://example.com/image.png"];
  UIImage *defaultImageA = ck_fakeImage([UIColor grayColor], CGSizeMake(100, 50));
  UIImage *defaultImageB = ck_fakeImage([UIColor greenColor], CGSizeMake(100, 50));
  UIImage *downloadedImage = ck_fakeImage([UIColor blueColor], CGSizeMake(100, 50));
  CGRect fullCropRect = CGRectMake(0, 0, 1, 1);
  CGRect validCropRect = CGRectMake(0, 0, 0.5, 1);
  CGRect invalidCropRect = CGRectMake(0, 0, 0.1, 1);
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URL, downloader, defaultImageA, fullCropRect);
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;
  CKControlledImageDownload *download = downloader.downloads.firstObject;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URL, downloader, defaultImageB, fullCropRect);
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);
  XCTAssertEqual(componentB.mountedView, imageView);
  XCTAssertEqualObjects(imageView.image, defaultImageB);
  XCTAssertEqual(downloader.downloads.count, 1u);
  XCTAssertEqual(downloader.canceledDownloads.count, 0u);

  CKNetworkImageComponent *componentC =
    ck_networkImageComponent(URL, downloader, defaultImageB, validCropRect);
  mountedComponents = ck_mountComponent(componentC, container, mountedComponents);
  XCTAssertEqual(componentC.mountedView, imageView);
  XCTAssertEqual(downloader.downloads.count, 1u);
  XCTAssertEqual(downloader.canceledDownloads.count, 0u);

  [downloader completeDownload:download withImage:downloadedImage];
  XCTAssertEqual(imageView.image.CGImage, downloadedImage.CGImage);
  XCTAssertTrue(CGRectEqualToRect(imageView.layer.contentsRect, validCropRect));

  CKNetworkImageComponent *componentD =
    ck_networkImageComponent(URL, downloader, defaultImageB, invalidCropRect);
  mountedComponents = ck_mountComponent(componentD, container, mountedComponents);
  [imageView layoutIfNeeded];

  XCTAssertEqual(componentD.mountedView, imageView);
  XCTAssertEqual(imageView.image.CGImage, downloadedImage.CGImage);
  XCTAssertTrue(CGRectEqualToRect(imageView.layer.contentsRect, fullCropRect));
  XCTAssertEqual(downloader.downloads.count, 1u);
  XCTAssertEqual(downloader.canceledDownloads.count, 0u);

  CKUnmountComponents(mountedComponents);
}

- (void)testInitialReplacementAndReuseRequestsUseMainCallbackQueue
{
  NSURL *URLA = [NSURL URLWithString:@"https://example.com/a.png"];
  NSURL *URLB = [NSURL URLWithString:@"https://example.com/b.png"];
  UIImage *defaultImage = ck_fakeImage([UIColor grayColor], CGSizeMake(50, 50));
  CKControlledImageDownloader *downloader = [CKControlledImageDownloader new];
  UIView *container = [UIView new];

  CKNetworkImageComponent *componentA =
    ck_networkImageComponent(URLA, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  NSSet<id<CKMountable>> *mountedComponents = ck_mountComponent(componentA, container, nil);
  UIImageView *imageView = (UIImageView *)componentA.mountedView;

  CKNetworkImageComponent *componentB =
    ck_networkImageComponent(URLB, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentB, container, mountedComponents);
  mountedComponents = ck_mountComponent(ck_placeholderComponent(), container, mountedComponents);

  CKNetworkImageComponent *componentC =
    ck_networkImageComponent(URLB, downloader, defaultImage, CGRectMake(0, 0, 1, 1));
  mountedComponents = ck_mountComponent(componentC, container, mountedComponents);

  XCTAssertEqual(componentC.mountedView, imageView);
  XCTAssertEqual(downloader.downloads.count, 3u);
  for (CKControlledImageDownload *download in downloader.downloads) {
    XCTAssertEqual(download.callbackQueue, dispatch_get_main_queue());
  }

  CKUnmountComponents(mountedComponents);
}

@end
