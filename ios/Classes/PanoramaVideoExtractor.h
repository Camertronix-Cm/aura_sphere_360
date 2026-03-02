#import <AVFoundation/AVFoundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// Extracts raw BGRA frames from an AVAsset URL via AVPlayerItemVideoOutput.
/// Sends frames as Uint8List (width + height in the event map) via EventChannel.
/// Frame extraction runs on a background dispatch queue — never touches the main thread.
@interface PanoramaVideoExtractor : NSObject

- (instancetype)initWithURL:(NSURL *)url
              eventChannel:(FlutterEventChannel *)channel;

- (void)play;
- (void)pause;
- (void)seekTo:(Float64)seconds;
- (void)setLooping:(BOOL)looping;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
