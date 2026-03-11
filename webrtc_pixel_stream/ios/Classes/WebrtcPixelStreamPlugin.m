#import "WebrtcPixelStreamPlugin.h"
#import "FlutterRTCStreamingSink.h"

// Import the FlutterWebRTCPlugin header from the flutter_webrtc pod.
// This gives us access to +sharedSingleton and -trackForId:peerConnectionId:.
#import <flutter_webrtc/FlutterWebRTCPlugin.h>

// How many times to retry trackForId: before giving up (100ms apart)
static const int kMaxTrackLookupRetries = 20;

@implementation WebrtcPixelStreamPlugin {
  NSObject<FlutterBinaryMessenger> *_messenger;
  NSMutableDictionary<NSString *, FlutterRTCStreamingSink *> *_sinks;
  NSMutableDictionary<NSString *, RTCVideoTrack *> *_tracks;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"webrtc_pixel_stream/control"
                                  binaryMessenger:[registrar messenger]];
  WebrtcPixelStreamPlugin *instance = [[WebrtcPixelStreamPlugin alloc] init];
  instance->_messenger = [registrar messenger];
  instance->_sinks = [NSMutableDictionary new];
  instance->_tracks = [NSMutableDictionary new];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"createPixelStream" isEqualToString:call.method]) {
    [self handleCreatePixelStream:call.arguments result:result];
  } else if ([@"disposePixelStream" isEqualToString:call.method]) {
    [self handleDisposePixelStream:call.arguments result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)handleCreatePixelStream:(NSDictionary *)args result:(FlutterResult)result {
  NSString *trackId = args[@"trackId"];
  id rawPcId = args[@"peerConnectionId"];

  if (!trackId || [trackId isKindOfClass:[NSNull class]] || trackId.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_ARGS"
                               message:@"trackId is required"
                               details:nil]);
    return;
  }

  // Idempotency check
  if (_sinks[trackId]) {
    NSLog(@"[WebrtcPixelStream] Stream already exists for track: %@", trackId);
    NSString *channelName = [NSString stringWithFormat:@"webrtc_pixel_stream/frames/%@", trackId];
    result(@{@"channelName" : channelName});
    return;
  }

  // Sanitize peerConnectionId — treat NSNull as nil
  NSString *peerConnectionId = nil;
  if ([rawPcId isKindOfClass:[NSString class]] && [(NSString *)rawPcId length] > 0) {
    peerConnectionId = (NSString *)rawPcId;
  }

  FlutterWebRTCPlugin *webrtcPlugin = [FlutterWebRTCPlugin sharedSingleton];
  if (!webrtcPlugin) {
    result([FlutterError errorWithCode:@"NOT_READY"
                               message:@"FlutterWebRTCPlugin singleton is nil."
                               details:nil]);
    return;
  }

  NSLog(@"[WebrtcPixelStream] Creating sink for track: %@", trackId);

  // Phase 2: Extract Dart-allocated FFI buffer addresses
  NSNumber *addressA   = args[@"memoryAddressA"];
  NSNumber *addressB   = args[@"memoryAddressB"];
  NSNumber *sizeNumber = args[@"memorySize"];

  if (!addressA || !addressB || !sizeNumber ||
      [addressA isKindOfClass:[NSNull class]] ||
      [addressB isKindOfClass:[NSNull class]]) {
    result([FlutterError errorWithCode:@"INVALID_ARGS"
                               message:@"memoryAddressA, memoryAddressB and memorySize are required"
                               details:nil]);
    return;
  }

  uint8_t *sharedBufferA = (uint8_t *)[addressA unsignedLongLongValue];
  uint8_t *sharedBufferB = (uint8_t *)[addressB unsignedLongLongValue];
  size_t   bufferSize    = (size_t)[sizeNumber unsignedIntegerValue];

  NSLog(@"[WebrtcPixelStream] FFI buffers — A: %p  B: %p  size: %zu",
        sharedBufferA, sharedBufferB, bufferSize);

  FlutterRTCStreamingSink *sink =
      [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId
                                             messenger:_messenger
                                         sharedBufferA:sharedBufferA
                                         sharedBufferB:sharedBufferB
                                            bufferSize:bufferSize];

  _sinks[trackId] = sink;

  // Return the channel name immediately so Dart can start listening.
  // The actual track attachment happens asynchronously with retries below.
  NSString *channelName = [NSString stringWithFormat:@"webrtc_pixel_stream/frames/%@", trackId];
  result(@{@"channelName" : channelName});

  // Delay the first lookup slightly — flutter_webrtc registers remote tracks
  // asynchronously and the track may not be visible to trackForId: yet.
  NSLog(@"[WebrtcPixelStream] Delaying renderer attachment for track: %@", trackId);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)),
                 dispatch_get_main_queue(), ^{
    [self attachRenderer:sink
                 trackId:trackId
      peerConnectionId:peerConnectionId
           webrtcPlugin:webrtcPlugin
            retryCount:0];
  });
}

/// Attempt to look up the video track and attach the renderer.
/// Retries up to kMaxTrackLookupRetries times (100ms apart) to handle
/// the race between our call and flutter_webrtc registering the remote track.
- (void)attachRenderer:(FlutterRTCStreamingSink *)sink
               trackId:(NSString *)trackId
    peerConnectionId:(NSString * _Nullable)peerConnectionId
         webrtcPlugin:(FlutterWebRTCPlugin *)webrtcPlugin
          retryCount:(int)retryCount {

  // If the sink was disposed while we were waiting, bail out.
  if (!self->_sinks[trackId]) {
    NSLog(@"[WebrtcPixelStream] Sink removed before attachment, aborting for track: %@", trackId);
    return;
  }

  RTCMediaStreamTrack *track = nil;

  // Guard the call inside @try/@catch. flutter_webrtc's trackForId:
  // can crash with -[NSNull stdString] if its internal peer-connection
  // dictionary contains NSNull placeholder entries (a known flutter_webrtc
  // bug when a connection is being negotiated).
  @try {
    track = [webrtcPlugin trackForId:trackId peerConnectionId:peerConnectionId];
  } @catch (NSException *exception) {
    NSLog(@"[WebrtcPixelStream] ⚠️ Exception in trackForId: (attempt %d): %@ – %@",
          retryCount + 1, exception.name, exception.reason);
    track = nil; // will retry below
  }

  if (track && [track isKindOfClass:[RTCVideoTrack class]]) {
    RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;

    NSLog(@"[WebrtcPixelStream] Found video track: %@, readyState=%ld",
          trackId, (long)videoTrack.readyState);

    // CRITICAL: Only call addRenderer: when the track is live (readyState == 1).
    // Calling addRenderer: on a track with readyState=0 triggers abort() inside
    // WebRTC's C++ layer (via RTC_DCHECK) — this CANNOT be caught by @try/@catch
    // and will kill the process immediately.
    // RTCMediaStreamTrackStateLive = 1, RTCMediaStreamTrackStateEnded = 0
    if (videoTrack.readyState != RTCMediaStreamTrackStateLive) {
      NSLog(@"[WebrtcPixelStream] ⏳ Track not yet live (state=%ld), retrying (attempt %d/%d)...",
            (long)videoTrack.readyState, retryCount + 1, kMaxTrackLookupRetries);
      // Fall through to the retry block below
    } else {
      self->_tracks[trackId] = videoTrack;
      @try {
        [videoTrack addRenderer:sink];
        NSLog(@"[WebrtcPixelStream] ✅ Renderer attached to track: %@", trackId);
      } @catch (NSException *exception) {
        NSLog(@"[WebrtcPixelStream] ❌ Exception attaching renderer: %@ – %@",
              exception.name, exception.reason);
        [self->_tracks removeObjectForKey:trackId];
        [self->_sinks removeObjectForKey:trackId];
      }
      return;
    }
  }

  // Track not found yet — retry if we have attempts remaining
  if (retryCount < kMaxTrackLookupRetries) {
    NSLog(@"[WebrtcPixelStream] Track not found (attempt %d/%d), retrying in 100ms...",
          retryCount + 1, kMaxTrackLookupRetries);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
      [self attachRenderer:sink
                   trackId:trackId
        peerConnectionId:peerConnectionId
             webrtcPlugin:webrtcPlugin
              retryCount:retryCount + 1];
    });
  } else {
    NSLog(@"[WebrtcPixelStream] ❌ Gave up waiting for track: %@ after %d attempts",
          trackId, kMaxTrackLookupRetries);
    [self->_sinks removeObjectForKey:trackId];
  }
}

- (void)handleDisposePixelStream:(NSDictionary *)args result:(FlutterResult)result {
  id rawTrackId = args[@"trackId"];
  if (!rawTrackId || [rawTrackId isKindOfClass:[NSNull class]]) {
    result(nil);
    return;
  }
  NSString *trackId = (NSString *)rawTrackId;

  FlutterRTCStreamingSink *sink = _sinks[trackId];
  RTCVideoTrack *videoTrack = _tracks[trackId];

  if (sink && videoTrack) {
    @try {
      [videoTrack removeRenderer:sink];
    } @catch (NSException *e) {
      NSLog(@"[WebrtcPixelStream] Exception during removeRenderer: %@", e.reason);
    }
    [sink dispose];
  }

  [_sinks removeObjectForKey:trackId];
  [_tracks removeObjectForKey:trackId];
  result(nil);
}

@end