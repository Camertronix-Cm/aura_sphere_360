#import "FlutterRTCStreamingSink.h"
#import <WebRTC/RTCYUVHelper.h>
#import <WebRTC/RTCYUVPlanarBuffer.h>

@interface FlutterRTCStreamingSink () <FlutterStreamHandler>
@end

@implementation FlutterRTCStreamingSink {
  FlutterEventChannel *_channel;
  FlutterEventSink     _eventSink;
  CVPixelBufferRef     _pixelBuffer;
  CGSize               _bufferSize;
}

- (instancetype)initWithTrackId:(NSString *)trackId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  self = [super init];
  if (!self) return nil;

  NSString *name = [NSString stringWithFormat:
      @"webrtc_pixel_stream/frames/%@", trackId];
  _channel = [FlutterEventChannel eventChannelWithName:name
                                      binaryMessenger:messenger];
  [_channel setStreamHandler:self];
  _bufferSize = CGSizeZero;
  return self;
}

// ── FlutterStreamHandler ──────────────────────────────────────────────────

- (FlutterError *_Nullable)onListenWithArguments:(id)arguments
                                       eventSink:(FlutterEventSink)events {
  _eventSink = events;
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id)arguments {
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
  if (!_eventSink || !frame) return;

  // Lazy allocation if setSize was not called first
  if (!_pixelBuffer ||
      (size_t)_bufferSize.width  != (size_t)frame.width ||
      (size_t)_bufferSize.height != (size_t)frame.height) {
    [self setSize:CGSizeMake(frame.width, frame.height)];
  }
  if (!_pixelBuffer) return;

  // Convert I420 → BGRA (kCVPixelFormatType_32BGRA = libyuv ARGB)
  id<RTCI420Buffer> i420 = [frame.buffer toI420];
  CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
  uint8_t *dst = CVPixelBufferGetBaseAddress(_pixelBuffer);
  const size_t stride = CVPixelBufferGetBytesPerRow(_pixelBuffer);

  [RTCYUVHelper I420ToARGB:i420.dataY
              srcStrideY:i420.strideY
                   srcU:i420.dataU
              srcStrideU:i420.strideU
                   srcV:i420.dataV
              srcStrideV:i420.strideV
               dstARGB:dst
         dstStrideARGB:(int)stride
                 width:frame.width
                height:frame.height];

  NSData *bytes = [NSData dataWithBytes:dst length:stride * frame.height];
  CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

  // FlutterEventSink is NOT thread-safe — dispatch to main queue.
  FlutterEventSink sink = _eventSink;
  if (!sink) return;
  NSDictionary *event = @{
    @"width"  : @(frame.width),
    @"height" : @(frame.height),
    @"stride" : @(stride),
    @"bytes"  : [FlutterStandardTypedData typedDataWithBytes:bytes],
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    sink(event);
  });
}

- (void)dispose {
  _eventSink = nil;
  [_channel setStreamHandler:nil];
  if (_pixelBuffer) {
    CVBufferRelease(_pixelBuffer);
    _pixelBuffer = nil;
  }
}

@end
