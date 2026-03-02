#import <WebRTC/WebRTC.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// An RTCVideoRenderer that converts I420 frames to BGRA and forwards
/// raw pixel bytes over a FlutterEventChannel.
///
/// Runs entirely on WebRTC's internal render thread. The EventSink
/// is dispatched to the main queue for thread safety.
@interface FlutterRTCStreamingSink : NSObject <RTCVideoRenderer>

- (instancetype)initWithTrackId:(NSString *)trackId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END
