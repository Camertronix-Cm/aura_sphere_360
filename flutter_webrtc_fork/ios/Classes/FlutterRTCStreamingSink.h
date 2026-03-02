#import <WebRTC/WebRTC.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// A second RTCVideoRenderer that forwards raw BGRA frame bytes
/// to a FlutterEventChannel, running entirely on the WebRTC render thread.
///
/// Add as a renderer alongside the existing FlutterRTCVideoRenderer so that
/// panorama_viewer can receive raw pixel data without GPU readback.
///
/// Usage:
///   FlutterRTCStreamingSink *sink =
///       [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId
///                                              messenger:self.messenger];
///   [videoTrack addRenderer:sink];
///
@interface FlutterRTCStreamingSink : NSObject <RTCVideoRenderer>

/// Creates a streaming sink that sends BGRA frame data over an EventChannel
/// named "FlutterWebRTC/PixelStream/{trackId}".
- (instancetype)initWithTrackId:(NSString *)trackId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger;

/// Stop streaming and release resources. Must be called before dealloc.
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
