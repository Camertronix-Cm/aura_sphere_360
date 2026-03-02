#import "PanoramaVideoExtractor.h"

@interface PanoramaVideoExtractor () <FlutterStreamHandler>
@end

@implementation PanoramaVideoExtractor {
  AVPlayer               *_player;
  AVPlayerItemVideoOutput *_videoOutput;
  dispatch_source_t       _frameTimer;
  FlutterEventSink        _eventSink;
  dispatch_queue_t        _extractionQueue;
  BOOL                    _looping;
  id                      _loopObserver;
}

- (instancetype)initWithURL:(NSURL *)url
              eventChannel:(FlutterEventChannel *)channel {
  self = [super init];
  if (!self) return nil;

  _extractionQueue = dispatch_queue_create(
      "com.panorama.video_extraction",
      dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                              QOS_CLASS_USER_INITIATED, 0));
  _looping = NO;

  // ── Output configuration ─────────────────────────────────────────────────
  // BGRA because decodeImageFromPixels accepts bgra8888 directly.
  NSDictionary *outputSettings = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}  // required for Metal compat
  };
  _videoOutput = [[AVPlayerItemVideoOutput alloc]
      initWithPixelBufferAttributes:outputSettings];

  // ── Player setup ─────────────────────────────────────────────────────────
  AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
  [item addOutput:_videoOutput];

  _player = [AVPlayer playerWithPlayerItem:item];
  _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

  // ── Looping support ──────────────────────────────────────────────────────
  __weak typeof(self) weakSelf = self;
  _loopObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                  object:item
                   queue:nil
              usingBlock:^(NSNotification *note) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf && strongSelf->_looping) {
      [strongSelf->_player seekToTime:kCMTimeZero
                      toleranceBefore:kCMTimeZero
                       toleranceAfter:kCMTimeZero];
      [strongSelf->_player play];
    }
  }];

  // ── Frame polling timer on background queue ──────────────────────────────
  // We use dispatch_source_timer instead of CADisplayLink because
  // CADisplayLink on a background RunLoop is undocumented and unreliable
  // on some iOS versions. dispatch_source_timer is GCD-native and guaranteed
  // to fire on our background queue.
  _frameTimer = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _extractionQueue);
  dispatch_source_set_timer(_frameTimer,
      dispatch_time(DISPATCH_TIME_NOW, 0),
      33 * NSEC_PER_MSEC,   // ~30 fps
      5  * NSEC_PER_MSEC);  // 5ms leeway for power efficiency

  dispatch_source_set_event_handler(_frameTimer, ^{
    [weakSelf _pollForFrame];
  });
  dispatch_resume(_frameTimer);

  [channel setStreamHandler:self];
  return self;
}

// ── FlutterStreamHandler ───────────────────────────────────────────────────

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(FlutterEventSink)eventSink {
  _eventSink = eventSink;
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  _eventSink = nil;
  return nil;
}

// ── Frame extraction ──────────────────────────────────────────────────────

- (void)_pollForFrame {
  // Already on _extractionQueue. Check if a new frame is ready.
  CMTime itemTime = [_videoOutput itemTimeForHostTime:CACurrentMediaTime()];
  if (![_videoOutput hasNewPixelBufferForItemTime:itemTime]) return;

  CVPixelBufferRef pixelBuffer =
      [_videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:nil];
  if (!pixelBuffer) return;

  [self _sendPixelBuffer:pixelBuffer];
  CVBufferRelease(pixelBuffer);
}

- (void)_sendPixelBuffer:(CVPixelBufferRef)buffer {
  if (!_eventSink) return;

  CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);

  size_t width  = CVPixelBufferGetWidth(buffer);
  size_t height = CVPixelBufferGetHeight(buffer);
  size_t stride = CVPixelBufferGetBytesPerRow(buffer);
  void  *base   = CVPixelBufferGetBaseAddress(buffer);

  // Copy bytes — buffer must be unlocked before we can release it
  NSData *data = [NSData dataWithBytes:base length:stride * height];

  CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);

  // Stride may be wider than width*4 (hardware alignment). Pass both.
  NSDictionary *event = @{
    @"width"  : @(width),
    @"height" : @(height),
    @"stride" : @(stride),  // bytes per row, NOT width*4
    @"bytes"  : [FlutterStandardTypedData typedDataWithBytes:data],
  };

  // FlutterEventSink is NOT documented as thread-safe.
  // Always dispatch to main to avoid undefined behaviour.
  FlutterEventSink sink = _eventSink;
  if (!sink) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    sink(event);
  });
}

// ── Playback control ──────────────────────────────────────────────────────

- (void)play  { [_player play]; }
- (void)pause { [_player pause]; }

- (void)seekTo:(Float64)seconds {
  CMTime t = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
  [_player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)setLooping:(BOOL)looping {
  _looping = looping;
}

- (void)dispose {
  _eventSink = nil;
  if (_frameTimer) {
    dispatch_source_cancel(_frameTimer);
    _frameTimer = nil;
  }
  if (_loopObserver) {
    [[NSNotificationCenter defaultCenter] removeObserver:_loopObserver];
    _loopObserver = nil;
  }
  [_player pause];
  _player = nil;
}

@end
