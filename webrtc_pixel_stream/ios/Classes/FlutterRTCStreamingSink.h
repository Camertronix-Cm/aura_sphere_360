#import <WebRTC/WebRTC.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// An RTCVideoRenderer that converts WebRTC frames to BGRA and writes them
/// directly into a Dart-allocated FFI double-buffer.
///
/// Native side writes pixel data into one of two pre-allocated C buffers
/// (provided by Dart via FFI pointer addresses), then fires a tiny
/// EventChannel message with only metadata so Dart knows which buffer to read.
///
/// This eliminates all EventChannel pixel serialisation overhead.
@interface FlutterRTCStreamingSink : NSObject <RTCVideoRenderer>

/// Phase 2+: double-buffered FFI init.
/// @param trackId       The WebRTC track ID (used for EventChannel naming).
/// @param messenger     Flutter binary messenger for the EventChannel.
/// @param bufferA       Pointer to Dart-allocated FFI buffer A.
/// @param bufferB       Pointer to Dart-allocated FFI buffer B.
/// @param bufferSize    Size in bytes of each buffer (both must be equal).
- (instancetype)initWithSinkId:(NSString *)sinkId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                  sharedBufferA:(uint8_t *)bufferA
                  sharedBufferB:(uint8_t *)bufferB
                     bufferSize:(size_t)bufferSize;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END
