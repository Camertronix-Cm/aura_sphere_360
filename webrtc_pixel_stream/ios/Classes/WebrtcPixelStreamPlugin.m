#import "WebrtcPixelStreamPlugin.h"
#import "FlutterRTCStreamingSink.h"

// Import the FlutterWebRTCPlugin header from the flutter_webrtc pod.
// This gives us access to +sharedSingleton and -trackForId:peerConnectionId:.
#import <flutter_webrtc/FlutterWebRTCPlugin.h>

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
  NSString *peerConnectionId = args[@"peerConnectionId"];

  if (!trackId || trackId.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_ARGS"
                               message:@"trackId is required"
                               details:nil]);
    return;
  }

  // Look up the video track via flutter_webrtc's shared singleton.
  // This works because flutter_webrtc is always registered first (it's a
  // dependency of the consumer app) and exposes +sharedSingleton.
  FlutterWebRTCPlugin *webrtcPlugin = [FlutterWebRTCPlugin sharedSingleton];
  if (!webrtcPlugin) {
    result([FlutterError errorWithCode:@"NOT_READY"
                               message:@"FlutterWebRTCPlugin singleton is nil. "
                                         "Ensure flutter_webrtc is initialized first."
                               details:nil]);
    return;
  }

  RTCMediaStreamTrack *track = [webrtcPlugin trackForId:trackId
                                       peerConnectionId:peerConnectionId];
  if (!track || ![track isKindOfClass:[RTCVideoTrack class]]) {
    NSLog(@"[WebrtcPixelStream] Track not found or not video: trackId=%@, pcId=%@", 
          trackId, peerConnectionId);
    result([FlutterError errorWithCode:@"TRACK_NOT_FOUND"
                               message:[NSString stringWithFormat:
                                   @"Video track '%@' not found (pcId=%@)",
                                   trackId, peerConnectionId ?: @"nil"]
                               details:nil]);
    return;
  }

  RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
  NSLog(@"[WebrtcPixelStream] Found video track: %@, readyState=%ld", 
        trackId, (long)videoTrack.readyState);

  // Create the streaming sink and attach it as a second renderer.
  FlutterRTCStreamingSink *sink =
      [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId
                                             messenger:_messenger];
  [videoTrack addRenderer:sink];
  NSLog(@"[WebrtcPixelStream] Renderer attached to track: %@", trackId);

  _sinks[trackId] = sink;
  _tracks[trackId] = videoTrack;

  NSString *channelName =
      [NSString stringWithFormat:@"webrtc_pixel_stream/frames/%@", trackId];
  result(@{@"channelName" : channelName});
}

- (void)handleDisposePixelStream:(NSDictionary *)args result:(FlutterResult)result {
  NSString *trackId = args[@"trackId"];

  FlutterRTCStreamingSink *sink = _sinks[trackId];
  RTCVideoTrack *videoTrack = _tracks[trackId];

  if (sink && videoTrack) {
    [videoTrack removeRenderer:sink];
    [sink dispose];
  }

  [_sinks removeObjectForKey:trackId];
  [_tracks removeObjectForKey:trackId];
  result(nil);
}

@end
