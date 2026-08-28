/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKNetworkImageComponent.h"

#import <Availability.h>

@interface CKNetworkImageSpecifier : NSObject
- (instancetype)initWithURL:(NSURL *)url
               defaultImage:(UIImage *)defaultImage
            imageDownloader:(id<CKNetworkImageDownloading>)imageDownloader
                   cropRect:(CGRect)cropRect;
@property (nonatomic, copy, readonly) NSURL *url;
@property (nonatomic, strong, readonly) UIImage *defaultImage;
@property (nonatomic, strong, readonly) id<CKNetworkImageDownloading> imageDownloader;
@property (nonatomic, assign, readonly) CGRect cropRect;
@end

@interface CKNetworkImageComponentView : UIImageView
@property (nonatomic, strong) CKNetworkImageSpecifier *specifier;
- (void)didEnterReusePool;
- (void)willLeaveReusePool;
@end

@implementation CKNetworkImageComponent

+ (instancetype)newWithURL:(NSURL *)url
           imageDownloader:(id<CKNetworkImageDownloading>)imageDownloader
                      size:(const RCComponentSize &)size
                   options:(const CKNetworkImageComponentOptions &)options
                attributes:(const CKViewComponentAttributeValueMap &)passedAttributes
{
  CGRect cropRect = options.cropRect;
  if (CGRectIsEmpty(cropRect)) {
    cropRect = CGRectMake(0, 0, 1, 1);
  }
  CKViewComponentAttributeValueMap attributes(passedAttributes);
  attributes.insert({
    {@selector(setSpecifier:), [[CKNetworkImageSpecifier alloc] initWithURL:url
                                                               defaultImage:options.defaultImage
                                                            imageDownloader:imageDownloader
                                                                   cropRect:cropRect]},

  });
#if defined(__IPHONE_11_0) && (__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_11_0)
  if (@available(iOS 11.0, tvOS 11.0, *)) {
    attributes.insert({@selector(setAccessibilityIgnoresInvertColors:), @YES});
  }
#endif
  return [super newWithView:{
    {[CKNetworkImageComponentView class], @selector(didEnterReusePool), @selector(willLeaveReusePool)},
    std::move(attributes)
  } size:size];
}

@end

@implementation CKNetworkImageSpecifier

- (instancetype)initWithURL:(NSURL *)url
               defaultImage:(UIImage *)defaultImage
            imageDownloader:(id<CKNetworkImageDownloading>)imageDownloader
                   cropRect:(CGRect)cropRect
{
  if (self = [super init]) {
    _url = [url copy];
    _defaultImage = defaultImage;
    _imageDownloader = imageDownloader;
    _cropRect = cropRect;
  }
  return self;
}

- (NSUInteger)hash
{
  return [_url hash];
}

- (BOOL)isEqual:(id)object
{
  if (self == object) {
    return YES;
  } else if ([object isKindOfClass:[self class]]) {
    CKNetworkImageSpecifier *other = object;
    return RCObjectIsEqual(_url, other->_url)
    && RCObjectIsEqual(_defaultImage, other->_defaultImage)
    && _imageDownloader == other->_imageDownloader
    && CGRectEqualToRect(_cropRect, other->_cropRect);
  }
  return NO;
}

@end

@implementation CKNetworkImageComponentView
{
  BOOL _inReusePool;
  id _download;
  id<CKNetworkImageDownloading> _downloadDownloader;
  NSObject *_requestIdentifier;
}

- (void)dealloc
{
  [self _cancelCurrentDownload];
}

- (void)didDownloadImage:(CGImageRef)image
                   error:(NSError *)error
       requestIdentifier:(NSObject *)requestIdentifier
{
  if (_requestIdentifier != requestIdentifier) {
    return;
  }

  _requestIdentifier = nil;
  _download = nil;
  _downloadDownloader = nil;

  if (image) {
    self.image = [UIImage imageWithCGImage:image];
    [self updateContentsRect];
  }
}

- (void)setSpecifier:(CKNetworkImageSpecifier *)specifier
{
  if (RCObjectIsEqual(specifier, _specifier)) {
    return;
  }

  if (!CGRectEqualToRect(_specifier.cropRect, specifier.cropRect)) {
    [self setNeedsLayout];
  }

  const BOOL urlIsDifferent = !RCObjectIsEqual(_specifier.url, specifier.url);
  const BOOL downloaderIsDifferent = _specifier.imageDownloader != specifier.imageDownloader;
  const BOOL requestIsDifferent = urlIsDifferent || downloaderIsDifferent;
  const BOOL isShowingCurrentDefaultImage = RCObjectIsEqual(self.image, _specifier.defaultImage);
  if (urlIsDifferent || isShowingCurrentDefaultImage) {
    self.image = specifier.defaultImage;
  }

  if (requestIsDifferent) {
    [self _cancelCurrentDownload];
  }

  _specifier = specifier;

  if (requestIsDifferent) {
    [self _startDownloadIfNotInReusePool];
  }
}

- (void)didEnterReusePool
{
  _inReusePool = YES;
  [self _cancelCurrentDownload];

  // Release the downloaded image that we're holding to lower memory usage.
  self.image = _specifier.defaultImage;
  [self updateContentsRect];
}

- (void)willLeaveReusePool
{
  if (!_inReusePool) {
    return;
  }

  _inReusePool = NO;
  [self _startDownloadIfNotInReusePool];
}

- (void)_cancelCurrentDownload
{
  id download = _download;
  id<CKNetworkImageDownloading> downloader = _downloadDownloader;

  // Invalidate the callback before canceling. Some downloaders invoke their
  // completion synchronously from cancelImageDownload:.
  _requestIdentifier = nil;
  _download = nil;
  _downloadDownloader = nil;

  if (download) {
    [downloader cancelImageDownload:download];
  }
}

- (void)_startDownloadIfNotInReusePool
{
  if (_inReusePool || _specifier.url == nil || _specifier.imageDownloader == nil) {
    return;
  }

  NSObject *requestIdentifier = [NSObject new];
  id<CKNetworkImageDownloading> downloader = _specifier.imageDownloader;
  _requestIdentifier = requestIdentifier;
  _downloadDownloader = downloader;

  __weak CKNetworkImageComponentView *weakSelf = self;
  id download = [downloader downloadImageWithURL:_specifier.url
                                          caller:self
                                   callbackQueue:dispatch_get_main_queue()
                           downloadProgressBlock:nil
                                      completion:^(CGImageRef image, NSError *error) {
    [weakSelf didDownloadImage:image error:error requestIdentifier:requestIdentifier];
  }];

  // A downloader is permitted to call its completion before returning. Only
  // retain the token if this request is still outstanding.
  if (_requestIdentifier == requestIdentifier) {
    _download = download;
  }
}

- (void)updateContentsRect
{
  if (CGRectIsEmpty(self.bounds)) {
    return;
  }

  // If we're about to crop the width or height, make sure the cropped version won't be upscaled.
  const CGFloat croppedWidth = self.image.size.width * _specifier.cropRect.size.width;
  const CGFloat croppedHeight = self.image.size.height * _specifier.cropRect.size.height;
  const BOOL canUseCropRect =
    (_specifier.cropRect.size.width == 1 || croppedWidth >= self.bounds.size.width) &&
    (_specifier.cropRect.size.height == 1 || croppedHeight >= self.bounds.size.height);
  self.layer.contentsRect = canUseCropRect ? _specifier.cropRect : CGRectMake(0, 0, 1, 1);
}

#pragma mark - UIView

- (void)layoutSubviews
{
  [super layoutSubviews];

  [self updateContentsRect];
}

@end
