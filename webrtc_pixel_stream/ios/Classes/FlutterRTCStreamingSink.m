#import "FlutterRTCStreamingSink.h"
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCVideoFrameBuffer.h>
#import <WebRTC/RTCCVPixelBuffer.h>
#import <WebRTC/RTCYUVHelper.h>    // Phase 1: I420ToBGRA for software-decoded frames
#import <Accelerate/Accelerate.h>

@interface FlutterRTCStreamingSink () <FlutterStreamHandler>
@end

@implementation FlutterRTCStreamingSink {
  FlutterEventChannel *_channel;
  FlutterEventSink     _eventSink;
  CVPixelBufferRef     _pixelBuffer;
  CGSize               _bufferSize;

  // Phase 2: FFI double-buffering
  uint8_t             *_sharedBufferA;
  uint8_t             *_sharedBufferB;
  size_t               _sharedBufferSize;
  int                  _writeIndex;   // 0 = write to A next, 1 = write to B next
}

- (instancetype)initWithSinkId:(NSString *)sinkId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                  sharedBufferA:(uint8_t *)bufferA
                  sharedBufferB:(uint8_t *)bufferB
                     bufferSize:(size_t)bufferSize {
  self = [super init];
  if (!self) return nil;

  _sharedBufferA    = bufferA;
  _sharedBufferB    = bufferB;
  _sharedBufferSize = bufferSize;
  _writeIndex       = 0;
  _bufferSize       = CGSizeZero;

  NSString *name = [NSString stringWithFormat:
      @"webrtc_pixel_stream/frames/%@", sinkId];
  _channel = [FlutterEventChannel eventChannelWithName:name
                                      binaryMessenger:messenger];
  [_channel setStreamHandler:self];
  return self;
}

// ── FlutterStreamHandler ──────────────────────────────────────────────────

- (FlutterError *_Nullable)onListenWithArguments:(id)arguments
                                       eventSink:(FlutterEventSink)events {
  NSLog(@"[FlutterRTCStreamingSink] onListen called, setting up eventSink");
  _eventSink = events;
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id)arguments {
  NSLog(@"[FlutterRTCStreamingSink] onCancel called, removing eventSink");
  _eventSink = nil;
  return nil;
}

// ── RTCVideoRenderer ──────────────────────────────────────────────────────

- (void)setSize:(CGSize)size {
  if (CGSizeEqualToSize(size, _bufferSize)) return;
  if (_pixelBuffer) {
    CVBufferRelease(_pixelBuffer);
    _pixelBuffer = nil;
  }

  NSDictionary *attrs = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}
  };
  CVPixelBufferCreate(kCFAllocatorDefault,
                      (size_t)size.width, (size_t)size.height,
                      kCVPixelFormatType_32BGRA,
                      (__bridge CFDictionaryRef)attrs,
                      &_pixelBuffer);
  _bufferSize = size;
}

- (void)renderFrame:(nullable RTCVideoFrame *)frame {
  if (!_eventSink) {
    NSLog(@"[FlutterRTCStreamingSink] renderFrame: eventSink is nil");
    return;
  }
  if (!frame) {
    NSLog(@"[FlutterRTCStreamingSink] renderFrame: frame is nil");
    return;
  }

  static dispatch_once_t onceToken;
  static int frameCount = 0;
  dispatch_once(&onceToken, ^{
    NSLog(@"[FlutterRTCStreamingSink] First frame received: %dx%d", (int)frame.width, (int)frame.height);
  });

  frameCount++;
  if (frameCount % 30 == 0) {
    NSLog(@"[FlutterRTCStreamingSink] Frame %d received: %dx%d", frameCount, (int)frame.width, (int)frame.height);
  }

  // Lazy allocation if setSize was not called first
  if (!_pixelBuffer ||
      (size_t)_bufferSize.width  != (size_t)frame.width ||
      (size_t)_bufferSize.height != (size_t)frame.height) {
    [self setSize:CGSizeMake(frame.width, frame.height)];
  }
  if (!_pixelBuffer) {
    NSLog(@"[FlutterRTCStreamingSink] pixelBuffer allocation failed");
    return;
  }

  CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
  uint8_t *dstBGRA = CVPixelBufferGetBaseAddress(_pixelBuffer);
  const size_t dstStride = CVPixelBufferGetBytesPerRow(_pixelBuffer);

  // ── Frame conversion (Phase 1) ─────────────────────────────────────────
  id<RTCVideoFrameBuffer> buffer = frame.buffer;
  if ([buffer isKindOfClass:[RTCCVPixelBuffer class]]) {
    // Hardware-decoded — direct CVPixelBuffer access
    RTCCVPixelBuffer *cvBuffer = (RTCCVPixelBuffer *)buffer;
    CVPixelBufferRef srcPixelBuffer = cvBuffer.pixelBuffer;

    OSType pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer);
    CVPixelBufferLockBaseAddress(srcPixelBuffer, kCVPixelBufferLock_ReadOnly);

    if (pixelFormat == kCVPixelFormatType_32BGRA) {
      // Already BGRA — direct row copy
      uint8_t *srcBGRA = CVPixelBufferGetBaseAddress(srcPixelBuffer);
      size_t srcStride = CVPixelBufferGetBytesPerRow(srcPixelBuffer);
      size_t height = CVPixelBufferGetHeight(srcPixelBuffer);
      for (size_t row = 0; row < height; row++) {
        memcpy(dstBGRA + row * dstStride, srcBGRA + row * srcStride, MIN(srcStride, dstStride));
      }
    } else if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
               pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
      // NV12 — convert to BGRA using vImage (fast hardware path)
      vImage_Buffer src_y = {
        .data     = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, 0),
        .width    = CVPixelBufferGetWidthOfPlane(srcPixelBuffer, 0),
        .height   = CVPixelBufferGetHeightOfPlane(srcPixelBuffer, 0),
        .rowBytes = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, 0)
      };
      vImage_Buffer src_uv = {
        .data     = CVPixelBufferGetBaseAddressOfPlane(srcPixelBuffer, 1),
        .width    = CVPixelBufferGetWidthOfPlane(srcPixelBuffer, 1),
        .height   = CVPixelBufferGetHeightOfPlane(srcPixelBuffer, 1),
        .rowBytes = CVPixelBufferGetBytesPerRowOfPlane(srcPixelBuffer, 1)
      };
      vImage_Buffer dst = {
        .data     = dstBGRA,
        .width    = frame.width,
        .height   = frame.height,
        .rowBytes = dstStride
      };
      vImage_YpCbCrToARGB info;
      vImage_YpCbCrPixelRange pixelRange = {0, 128, 255, 255, 255, 1, 255, 0};
      // Map to BGRA8888 directly since our memory layout relies on BGRA!
      vImageConvert_YpCbCrToARGB_GenerateConversion(
        kvImage_YpCbCrToARGBMatrix_ITU_R_709_2,
        &pixelRange, &info,
        kvImage420Yp8_CbCr8, kvImageARGB8888, kvImageNoFlags
      );
      // We must map it specifically as BGRA (B G R A = 3 2 1 0 from ARGB)
      uint8_t permuteMap[4] = {3, 2, 1, 0}; 
      vImageConvert_420Yp8_CbCr8ToARGB8888(&src_y, &src_uv, &dst, &info, permuteMap, 255, kvImageNoFlags);
    } else {
      NSLog(@"[FlutterRTCStreamingSink] Unsupported pixel format: %d", (int)pixelFormat);
    }

    CVPixelBufferUnlockBaseAddress(srcPixelBuffer, kCVPixelBufferLock_ReadOnly);

  } else if ([buffer conformsToProtocol:@protocol(RTCI420Buffer)]) {
    // Phase 1: Software-decoded I420 frame — convert to BGRA using libyuv
    id<RTCI420Buffer> i420Buffer = (id<RTCI420Buffer>)buffer;

    int convResult = [RTCYUVHelper I420ToBGRA:i420Buffer.dataY
                                   srcStrideY:i420Buffer.strideY
                                        srcU:i420Buffer.dataU
                                  srcStrideU:i420Buffer.strideU
                                        srcV:i420Buffer.dataV
                                  srcStrideV:i420Buffer.strideV
                                     dstBGRA:dstBGRA
                               dstStrideBGRA:(int)dstStride
                                       width:(int)frame.width
                                      height:(int)frame.height];
    if (convResult != 0) {
      NSLog(@"[FlutterRTCStreamingSink] I420ToBGRA conversion failed with code %d", convResult);
    }

  } else {
    // Last resort: toI420 for any other buffer type
    id<RTCI420Buffer> i420Buffer = [buffer toI420];
    if (i420Buffer) {
      [RTCYUVHelper I420ToBGRA:i420Buffer.dataY
                     srcStrideY:i420Buffer.strideY
                          srcU:i420Buffer.dataU
                    srcStrideU:i420Buffer.strideU
                          srcV:i420Buffer.dataV
                    srcStrideV:i420Buffer.strideV
                       dstBGRA:dstBGRA
                 dstStrideBGRA:(int)dstStride
                         width:(int)frame.width
                        height:(int)frame.height];
    } else {
      NSLog(@"[FlutterRTCStreamingSink] Warning: Unhandled buffer type, skipping frame");
    }
  }

  // ── Phase 2: Write to FFI double-buffer ────────────────────────────────
  // Select write target, capture index for the event notification.
  uint8_t *writeTarget = (_writeIndex == 0) ? _sharedBufferA : _sharedBufferB;
  int currentBufferIndex = _writeIndex;

  size_t bytesToCopy = dstStride * frame.height;
  if (writeTarget != NULL && bytesToCopy <= _sharedBufferSize) {
    memcpy(writeTarget, dstBGRA, bytesToCopy);
  } else {
    NSLog(@"[FlutterRTCStreamingSink] FFI buffer too small or null — skipping write (%zu > %zu)",
          bytesToCopy, _sharedBufferSize);
  }

  CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

  // Flip write index for next frame
  _writeIndex = 1 - _writeIndex;

  // ── Fire tiny metadata-only event to Dart ─────────────────────────────
  FlutterEventSink sink = _eventSink;
  if (!sink) return;

  NSDictionary *event = @{
    @"frameReady"  : @(YES),
    @"bufferIndex" : @(currentBufferIndex),
    @"width"       : @(frame.width),
    @"height"      : @(frame.height),
    @"stride"      : @(dstStride),
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    sink(event);  // Zero pixel data — just metadata
  });
}

- (void)dispose {
  _eventSink = nil;
  [_channel setStreamHandler:nil];
  if (_pixelBuffer) {
    CVBufferRelease(_pixelBuffer);
    _pixelBuffer = nil;
  }
  // FFI buffers are owned by Dart — do NOT free them here
}

@end
