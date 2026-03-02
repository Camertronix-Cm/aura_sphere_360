# Path A: Native Pixel Delivery — Implementation Guide

## The Root Problem, Precisely Stated

`RenderRepaintBoundary.toImage()` issues a Metal snapshot of the already-composited
layer, blocking while the GPU flushes and reads back into CPU memory. This is a
GPU→CPU roundtrip happening 30 times per second, on the main thread.

The fix is to tap **earlier** in the pipeline, before the frame ever leaves CPU memory.

```
Current (bad):
  AVDecoder → CVPixelBuffer (CPU) → Metal texture upload (GPU)
  → Flutter composite layer (GPU) → boundary.toImage() READBACK (GPU→CPU)
  → ui.Image → flutter_cube ImageShader → Metal upload again (CPU→GPU)

Target (Path A):
  AVDecoder → CVPixelBuffer (CPU) ─── copy bytes on background thread ──→
  ui.decodeImageFromPixels() (engine IO thread) → ui.Image
  → flutter_cube ImageShader → Metal upload (CPU→GPU, once)
```

Both `AVPlayerItemVideoOutput` (video) and the WebRTC `RTCVideoFrame` pipeline
work entirely in CPU-accessible `CVPixelBuffer` memory. No GPU readback is needed.
The `boundary.toImage()` roundtrip is eliminated, not moved to a background thread.

---

## File Map

```
ios/
  Classes/
    PanoramaVideoExtractor.h          ← new
    PanoramaVideoExtractor.m          ← new
    PanoramaRTCStreamingSink.h        ← new (minimal flutter_webrtc fork only)
    PanoramaRTCStreamingSink.m        ← new (minimal flutter_webrtc fork only)
    PanoramaViewerPlugin.h            ← new
    PanoramaViewerPlugin.m            ← new

lib/
  src/
    native_video_texture_provider.dart    ← replaces video_texture_provider.dart
    native_webrtc_texture_provider.dart   ← replaces webrtc_texture_provider.dart

flutter_webrtc/                  ← local fork (dependency_overrides)
  ios/Classes/
    FlutterRTCStreamingSink.h    ← ~40 lines (new file)
    FlutterRTCStreamingSink.m    ← ~80 lines (new file)
    FlutterWebRTCPlugin.m        ← +15 lines (register one new method call)
```

---

## Part 1 — Video: AVPlayerItemVideoOutput

### How it works

`AVPlayerItemVideoOutput` is an Apple-provided tap on `AVPlayerItem` that gives you
`CVPixelBuffer` objects from the decoded video frames on demand, with zero GPU
involvement. It was designed exactly for this use case.

We create a **single** `AVPlayer` (background thread) that replaces
`VideoPlayerController` entirely. This avoids decoding the video twice on the
hardware decoder.

> **Why not keep VideoPlayerController?** Running two `AVPlayer` instances on the
> same video doubles the hardware decoder load. For 4K 360 content this can
> exhaust the decoder pool. Instead, the native extractor handles both pixel
> extraction AND playback control (play/pause/seek/loop) via method channel
> calls. If you need a Flutter-side `VideoPlayerController` for UI widgets
> (seek bar, duration display), consider driving it as audio-only or replacing
> those widgets with custom controls backed by method channel state.

### iOS: `PanoramaVideoExtractor`

```objc
// PanoramaVideoExtractor.h
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
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
```

```objc
// PanoramaVideoExtractor.m
#import "PanoramaVideoExtractor.h"

@interface PanoramaVideoExtractor () <FlutterStreamHandler>
@end

@implementation PanoramaVideoExtractor {
  AVPlayer               *_player;
  AVPlayerItemVideoOutput *_videoOutput;
  dispatch_source_t       _frameTimer;
  FlutterEventSink        _eventSink;
  dispatch_queue_t        _extractionQueue;
  BOOL                    _extracting;
}

- (instancetype)initWithURL:(NSURL *)url
              eventChannel:(FlutterEventChannel *)channel {
  self = [super init];
  if (!self) return nil;

  _extractionQueue = dispatch_queue_create(
      "com.panorama.video_extraction",
      dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                              QOS_CLASS_USER_INITIATED, 0));
  _extracting = NO;

  // ── Output configuration ─────────────────────────────────────────────────
  // BGRA because flutter_cube's ImageShader expects RGBA; BGRA is the same
  // byte order on little-endian ARM with the R/B swap handled at ImageShader
  // upload. Alternatively use kCVPixelFormatType_32RGBA directly.
  NSDictionary *outputSettings = @{
    (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferIOSurfacePropertiesKey : @{}  // required for Metal compat
  };
  _videoOutput = [[AVPlayerItemVideoOutput alloc]
      initWithPixelBufferAttributes:outputSettings];

  // ── Player setup: audio muted, background thread RunLoop ─────────────────
  AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
  [item addOutput:_videoOutput];

  _player = [AVPlayer playerWithPlayerItem:item];
  _player.actionAtItemEnd = AVPlayerActionAtItemEndNone; // handle looping in Dart

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
  __weak typeof(self) weakSelf = self;
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

- (void)dispose {
  _eventSink = nil;
  if (_frameTimer) {
    dispatch_source_cancel(_frameTimer);
    _frameTimer = nil;
  }
  [_player pause];
  _player = nil;
}

@end
```

### iOS: Plugin registration for video

```objc
// In PanoramaViewerPlugin.m (registerWithRegistrar:)

// Called from Dart as: _methodChannel.invokeMethod('createVideoExtractor', url)
case @"createVideoExtractor": {
  NSString *urlString = call.arguments[@"url"];
  NSURL    *url       = [NSURL URLWithString:urlString];
  NSString *channelName =
      [NSString stringWithFormat:@"panorama_viewer/video_frames/%@",
                                 urlString.lastPathComponent];

  FlutterEventChannel *channel =
      [FlutterEventChannel eventChannelWithName:channelName
                              binaryMessenger:registrar.messenger];

  PanoramaVideoExtractor *extractor =
      [[PanoramaVideoExtractor alloc] initWithURL:url eventChannel:channel];

  // Store extractor keyed by channel name so Dart can dispose it later
  self.extractors[channelName] = extractor;
  result(channelName);
  break;
}

case @"videoPlay":   { [self.extractors[call.arguments[@"id"]] play];   result(nil); break; }
case @"videoPause":  { [self.extractors[call.arguments[@"id"]] pause];  result(nil); break; }
case @"videoSeek":   {
  [self.extractors[call.arguments[@"id"]]
   seekTo:[call.arguments[@"seconds"] floatValue]];
  result(nil);
  break;
}
case @"disposeVideoExtractor": {
  PanoramaVideoExtractor *ex = self.extractors[call.arguments[@"id"]];
  [ex dispose];
  [self.extractors removeObjectForKey:call.arguments[@"id"]];
  result(nil);
  break;
}
```

---

## Part 2 — WebRTC: Minimal flutter_webrtc Fork

### Why a fork is needed

`RTCVideoRenderer` is flutter_webrtc's internal pixel pipeline. The only way to
receive raw `RTCVideoFrame` callbacks without the RepaintBoundary is to add a
second `RTCVideoRenderer` to the `RTCVideoTrack`. This requires calling
`[videoTrack addRenderer:ourSink]` — the `RTCVideoTrack` object lives inside
flutter_webrtc's internal state and is not publicly accessible.

The fork is minimal: **two new files, ~15 lines added to one existing file.**
No existing behaviour changes.

### Fork setup

```yaml
# pubspec.yaml — add to dependency_overrides:
dependency_overrides:
  flutter_webrtc:
    path: ../flutter_webrtc_fork   # local copy of the 0.11.7 source
```

### New file: `FlutterRTCStreamingSink.h`

```objc
#import <WebRTC/WebRTC.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// A second RTCVideoRenderer that forwards raw BGRA frame bytes
/// to a FlutterEventChannel, running entirely on the WebRTC render thread.
/// Add as a renderer alongside the existing FlutterRTCVideoRenderer.
@interface FlutterRTCStreamingSink : NSObject <RTCVideoRenderer>

/// eventChannelName will be "FlutterWebRTC/PixelStream/{trackId}"
- (instancetype)initWithTrackId:(NSString *)trackId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END
```

### New file: `FlutterRTCStreamingSink.m`

```objc
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
      @"FlutterWebRTC/PixelStream/%@", trackId];
  _channel = [FlutterEventChannel eventChannelWithName:name
                                      binaryMessenger:messenger];
  [_channel setStreamHandler:self];
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
  // Reallocate pixel buffer when video dimensions change
  if (CGSizeEqualToSize(size, _bufferSize)) return;
  if (_pixelBuffer) CVBufferRelease(_pixelBuffer);

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
  // Called on WebRTC's internal render thread — NOT the main thread.
  if (!_eventSink || !frame || !_pixelBuffer) return;

  // Lazy allocation if setSize was not called first
  if (!_pixelBuffer) {
    [self setSize:CGSizeMake(frame.width, frame.height)];
  }

  // Convert I420 → BGRA into our CVPixelBuffer (identical to what
  // FlutterRTCVideoRenderer already does internally)
  id<RTCI420Buffer> i420 = [frame.buffer toI420];
  CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
  uint8_t *dst = CVPixelBufferGetBaseAddress(_pixelBuffer);
  const size_t stride = CVPixelBufferGetBytesPerRow(_pixelBuffer);

  [RTCYUVHelper I420ToBGRA:i420.dataY
              srcStrideY:i420.strideY
                   srcU:i420.dataU
              srcStrideU:i420.strideU
                   srcV:i420.dataV
              srcStrideV:i420.strideV
               dstBGRA:dst
         dstStrideBGRA:(int)stride
                   width:frame.width
                  height:frame.height];

  // Copy before unlocking so Dart receives consistent data
  NSData *bytes = [NSData dataWithBytes:dst length:stride * frame.height];
  CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

  // FlutterEventSink is NOT documented as thread-safe — dispatch to main.
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
```

### Patch to `FlutterWebRTCPlugin.m` (+15 lines)

Find the block that handles `captureFrame` and add alongside it:

```objc
} else if ([@"createPixelStream" isEqualToString:call.method]) {
  // Arguments: {"trackId": String, "peerConnectionId": String (optional)}
  NSString *trackId = call.arguments[@"trackId"];
  NSString *peerConnectionId = call.arguments[@"peerConnectionId"];

  // Use the existing trackForId:peerConnectionId: method which correctly
  // searches localTracks, then iterates _peerConnections to check each
  // peerConnection.remoteTracks and transceiver.receiver.track.
  RTCMediaStreamTrack *track = [self trackForId:trackId
                               peerConnectionId:peerConnectionId];
  if (!track || ![track isKindOfClass:[RTCVideoTrack class]]) {
    result([FlutterError errorWithCode:@"TRACK_NOT_FOUND"
                               message:@"Video track not found"
                               details:nil]);
    return;
  }

  RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
  FlutterRTCStreamingSink *sink =
      [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId
                                             messenger:self.messenger];
  [videoTrack addRenderer:sink];

  // Store sink and track reference for cleanup
  // Add to header: @property(nonatomic, strong) NSMutableDictionary *pixelStreams;
  // Add to header: @property(nonatomic, strong) NSMutableDictionary *pixelStreamTracks;
  self.pixelStreams[trackId] = sink;
  self.pixelStreamTracks[trackId] = videoTrack;

  result([NSString stringWithFormat:@"FlutterWebRTC/PixelStream/%@", trackId]);

} else if ([@"disposePixelStream" isEqualToString:call.method]) {
  NSString *trackId = call.arguments[@"trackId"];
  FlutterRTCStreamingSink *sink = self.pixelStreams[trackId];
  if (!sink) { result(nil); return; }

  // Remove renderer from the stored track reference
  RTCVideoTrack *videoTrack = self.pixelStreamTracks[trackId];
  if (videoTrack) [videoTrack removeRenderer:sink];

  [sink dispose];
  [self.pixelStreams removeObjectForKey:trackId];
  [self.pixelStreamTracks removeObjectForKey:trackId];
  result(nil);
}
```

> **Note on track lookup**: flutter_webrtc 0.11.7 has an existing method
> `- (RTCMediaStreamTrack*)trackForId:(NSString*)trackId peerConnectionId:(NSString*)peerConnectionId`
> that correctly searches `_localTracks`, then iterates all `_peerConnections`
> checking `peerConnection.remoteTracks` and `transceiver.receiver.track`.
> The code above reuses this method exactly as the existing `captureFrame`
> handler does. `remoteTracks` is NOT a property on `FlutterWebRTCPlugin` —
> it lives on individual `RTCPeerConnection` objects via associated objects.

---

## Part 3 — Dart Layer

### Shared: frame decoding utility

Both providers share the same pixel→`ui.Image` conversion. Add this to a new
`lib/src/native_frame_decoder.dart`:

```dart
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

/// Converts a raw BGRA event map (from the EventChannel) to a ui.Image.
///
/// `decodeImageFromPixels` copies bytes into an ImmutableBuffer on the main
/// isolate (fast memcpy), then hands off to Flutter's engine IO thread for
/// GPU texture upload. The callback fires back on the main isolate.
Future<ui.Image?> decodeFrameEvent(Map<dynamic, dynamic> event) async {
  final int width  = event['width']  as int;
  final int height = event['height'] as int;
  final int stride = event['stride'] as int; // bytes per row
  // FlutterStandardTypedData bytes arrive as Uint8List on the Dart side.
  final Uint8List bytes = event['bytes'] as Uint8List;

  // If stride == width * 4, bytes is already tightly packed.
  // If stride > width * 4 (hardware row-alignment padding), strip the padding.
  final Uint8List pixels = _stripPadding(bytes, width, height, stride);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,  // BGRA from AVFoundation / WebRTC
    (ui.Image img) => completer.complete(img),
  );
  return completer.future;
}

Uint8List _stripPadding(Uint8List src, int width, int height, int stride) {
  final int rowBytes = width * 4;
  if (stride == rowBytes) return src; // fast path — no padding

  final Uint8List dst = Uint8List(rowBytes * height);
  for (int y = 0; y < height; y++) {
    dst.setRange(y * rowBytes, (y + 1) * rowBytes, src, y * stride);
  }
  return dst;
}
```

### `NativeVideoTextureProvider`

Replaces `VideoTextureProvider`. No `GlobalKey`, no `RepaintBoundary`, no 0.01
opacity widget, no Timer.

```dart
// lib/src/native_video_texture_provider.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'texture_provider.dart';
import 'native_frame_decoder.dart';

class NativeVideoTextureProvider extends PanoramaTextureProvider {
  static const MethodChannel _method =
      MethodChannel('panorama_viewer/control');

  final String videoUrl;
  String? _extractorId;       // channel name returned by native
  EventChannel? _eventChannel;
  StreamSubscription? _sub;
  ui.Image? _currentFrame;
  bool _ready = false;

  NativeVideoTextureProvider(this.videoUrl);

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.video;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    _extractorId = await _method.invokeMethod<String>(
        'createVideoExtractor', {'url': videoUrl});
    _eventChannel = EventChannel(_extractorId!);

    // Use a latest-frame-wins strategy to avoid unbounded queueing.
    // If a decode is in-flight when a new frame arrives, we skip to the
    // newest frame rather than queuing all intermediate frames.
    _sub = _eventChannel!
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>()
        .listen(_onNativeEvent, onError: _onError);

    await _method.invokeMethod('videoPlay', {'id': _extractorId});
  }

  bool _decoding = false;
  Map<dynamic, dynamic>? _pendingEvent;

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    _pendingEvent = event;
    if (!_decoding) _processNext();
  }

  Future<void> _processNext() async {
    if (_pendingEvent == null) return;
    _decoding = true;
    final event = _pendingEvent!;
    _pendingEvent = null; // drop any older frames
    final img = await decodeFrameEvent(event);
    if (img != null) {
      _currentFrame?.dispose();
      _currentFrame = img;
      _ready = true;
      notifyListeners();
    }
    _decoding = false;
    if (_pendingEvent != null) _processNext(); // process latest, skip intermediate
  }

  void _onError(Object err) {
    debugPrint('[NativeVideoTextureProvider] stream error: $err');
  }

  Future<void> play()  => _method.invokeMethod('videoPlay',  {'id': _extractorId});
  Future<void> pause() => _method.invokeMethod('videoPause', {'id': _extractorId});
  Future<void> seek(Duration position) => _method.invokeMethod('videoSeek', {
    'id': _extractorId,
    'seconds': position.inMicroseconds / 1e6,
  });

  @override
  Future<ui.Image?> getCurrentFrame() async => _currentFrame;

  @override
  void dispose() {
    _sub?.cancel();
    _currentFrame?.dispose();
    _method.invokeMethod('disposeVideoExtractor', {'id': _extractorId});
    super.dispose();
  }
}
```

### `NativeWebRTCTextureProvider`

```dart
// lib/src/native_webrtc_texture_provider.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'texture_provider.dart';
import 'native_frame_decoder.dart';

class NativeWebRTCTextureProvider extends PanoramaTextureProvider {
  // The new method added to the flutter_webrtc fork
  static const MethodChannel _webrtcMethod =
      MethodChannel('FlutterWebRTC.Method');

  final RTCVideoRenderer renderer;
  final String trackId;              // the MediaStreamTrack.id being rendered
  final String? peerConnectionId;    // needed for remote track lookup

  EventChannel? _eventChannel;
  StreamSubscription? _sub;
  ui.Image? _currentFrame;
  bool _ready = false;

  NativeWebRTCTextureProvider(this.renderer, {
    required this.trackId,
    this.peerConnectionId,
  });

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.webrtc;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async {
    // peerConnectionId is needed to find remote tracks.
    // Pass null for local tracks (e.g., local camera demo).
    final String channelName = await _webrtcMethod.invokeMethod<String>(
        'createPixelStream', {
      'trackId': trackId,
      'peerConnectionId': peerConnectionId,
    }) ?? '';

    _eventChannel = EventChannel(channelName);
    // Latest-frame-wins strategy (same as NativeVideoTextureProvider).
    _sub = _eventChannel!
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>()
        .listen(_onNativeEvent, onError: _onError);
  }

  bool _decoding = false;
  Map<dynamic, dynamic>? _pendingEvent;

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    _pendingEvent = event;
    if (!_decoding) _processNext();
  }

  Future<void> _processNext() async {
    if (_pendingEvent == null) return;
    _decoding = true;
    final event = _pendingEvent!;
    _pendingEvent = null;
    final img = await decodeFrameEvent(event);
    if (img != null) {
      _currentFrame?.dispose();
      _currentFrame = img;
      _ready = true;
      notifyListeners();
    }
    _decoding = false;
    if (_pendingEvent != null) _processNext();
  }

  void _onError(Object err) {
    debugPrint('[NativeWebRTCTextureProvider] stream error: $err');
  }

  @override
  Future<ui.Image?> getCurrentFrame() async => _currentFrame;

  @override
  void dispose() {
    _sub?.cancel();
    _currentFrame?.dispose();
    _webrtcMethod.invokeMethod('disposePixelStream', {'trackId': trackId});
    super.dispose();
  }
}
```

### Update `PanoramaViewer` widget

In `panorama_viewer.dart`, `_initializeTextureProvider()`:

```dart
// Replace:
if (widget.videoPlayerController != null) {
  textureProvider = VideoTextureProvider(widget.videoPlayerController!);
  ...

// With:
if (widget.videoPlayerController != null) {
  // NativeVideoTextureProvider takes the URL directly.
  // Expose a `videoUrl` parameter on PanoramaViewer, or extract from
  // controller via a helper (see note below).
  textureProvider = NativeVideoTextureProvider(widget.videoUrl!);
  textureProvider!.addListener(_updateTextureFromProvider);
  await textureProvider!.initialize();
}

// Replace:
if (widget.webrtcRenderer != null) {
  textureProvider = WebRTCTextureProvider(widget.webrtcRenderer!);
  ...

// With:
if (widget.webrtcRenderer != null) {
  textureProvider = NativeWebRTCTextureProvider(
    widget.webrtcRenderer!,
    trackId: widget.webrtcTrackId!,  // new required param when webrtcRenderer is set
  );
  textureProvider!.addListener(_updateTextureFromProvider);
  await textureProvider!.initialize();
}
```

And in `build()`, **delete** both `Positioned` / `Opacity` blocks for
`VideoTextureProvider` and `WebRTCTextureProvider`. The hidden widget trick is
gone entirely.

> **Note on `VideoPlayerController.dataSource`**: There is no public API to get
> the URL back from a `VideoPlayerController`. The cleanest solution is to add
> a `videoUrl` parameter to `PanoramaViewer` alongside `videoPlayerController`.
> The user passes the same URL string to both. The native extractor handles its
> own `AVPlayer`; `VideoPlayerController` is retained only for playback UI
> controls (play/pause/seek buttons, duration display). If you have no playback
> UI, you can drop `VideoPlayerController` entirely and use only the native
> extractor.

---

## Part 4 — Thread Safety & Performance Notes

### `FlutterEventSink` thread safety

`FlutterEventSink` is **NOT** documented as thread-safe. Unlike
`FlutterMethodCallHandler` (which has an explicit "This can be invoked from any
thread." annotation), `FlutterEventSink` has no such guarantee. All native code
in this guide dispatches to the main queue before calling the event sink:

```objc
FlutterEventSink sink = _eventSink;
if (!sink) return;
dispatch_async(dispatch_get_main_queue(), ^{
  sink(event);
});
```

### `ui.decodeImageFromPixels` — what actually happens

`decodeImageFromPixels` does the following:
1. `ImmutableBuffer.fromUint8List(pixels)` — copies bytes into engine memory.
   This is a fast `memcpy` that runs on the main isolate.
2. `ImageDescriptor.raw(...)` — creates a descriptor (trivial).
3. `descriptor.instantiateCodec(...)` — dispatched to Flutter's engine IO thread.
4. `codec.getNextFrame()` — GPU texture upload, also on the IO thread.
5. The callback fires back on the main isolate.

Steps 3–4 are off the main thread. Step 1 is a fast copy (~8MB for 1080p BGRA)
that takes ~1ms on Apple Silicon. This is not a "background isolate" — it's the
Flutter engine's native IO thread.

### Frame drops under load

The Dart providers use a "latest-frame-wins" strategy: if a decode is in-flight
when a new native frame arrives, the old pending event is replaced. This means
at most one frame is being decoded at any time, and the display always shows the
most recent available frame.

The native `dispatch_source_timer` + `hasNewPixelBufferForItemTime:` also handles
dropping repeated frames naturally — it only sends when there is actually a new
frame, so a 30-fps video at 30-fps polling fires ~30 events/sec.

### Bandwidth: ~8MB per frame over EventChannel

A 1920×1080 BGRA frame is `1920 × 1080 × 4 = 8,294,400 bytes`. At 30 fps,
that's ~237 MB/sec through the platform channel codec. The standard codec copies
these bytes at least twice (NSData → serialization → Dart Uint8List).

This works but is the throughput ceiling. To reduce it:
- **Extract at half resolution**: pass `pixelRatio: 0.5` equivalent by
  configuring the native extractor to output at 960×540 (~2MB/frame, 4× less).
  Equirect textures get heavily distorted at the poles, so half-res is often
  visually indistinguishable.
- **Use NV12/I420 instead of BGRA**: 1.5 bytes/pixel vs 4 bytes/pixel, but adds
  complexity on the Dart decode side.

---

## Part 5 — Android

The same principle applies on Android:

- **Video**: `ExoPlayer` (used by `video_player`) does not expose a frame
  callback API in its public interface. Alternatives:
  - Use `MediaCodec` directly with a `Surface` backed by `ImageReader`
    (USAGE_CPU_READ_OFTEN flag) to get `Image` objects with CPU-accessible bytes.
  - Or use ExoPlayer's `VideoFrameProcessor` extension (available since
    ExoPlayer 1.1).
- **WebRTC**: `flutter_webrtc` on Android uses `VideoTrack.addSink(VideoSink)`
  with `VideoFrame` objects. Add a custom `VideoSink` (identical approach to iOS)
  and forward bytes via `EventChannel`. No fork needed on Android — the API is
  public.

---

## Part 6 — What This Eliminates

| Before | After |
|---|---|
| `RenderRepaintBoundary.toImage()` — GPU→CPU readback on main thread | Gone |
| `Timer.periodic(33ms)` polling | Gone — event-driven, fires only on new frames |
| Hidden 0.01-opacity widget in widget tree | Gone |
| `GlobalKey` + widget tree coupling | Gone |
| `image.toByteData()` frame validation — second GPU readback | Gone |
| `_isExtracting` guard (race condition risk) | Gone — stream backpressure handles this |
| Double rendering (invisible widget + sphere) | Gone |
| Dual AVPlayer hardware decoder load | Gone (single player) |

The only CPU→GPU copy that remains is the final `ImageShader` upload inside
flutter_cube — that is unavoidable with the current flutter_cube architecture
and is a single forward copy, not a readback.

---

## Part 7 — Audit Fixes Applied

This document has been corrected for the following issues found during audit:

1. **RTCYUVHelper selectors**: Fixed `dst:` → `dstBGRA:`, `dstStride:` → `dstStrideBGRA:` to match actual WebRTC SDK header.
2. **Dart FlutterStandardTypedData**: Bytes arrive as `Uint8List` on Dart side, not `FlutterStandardTypedData` (which is an ObjC-only class).
3. **Missing `dart:async` import**: Added for `Completer` usage.
4. **Remote track lookup**: Replaced incorrect `self.remoteTracks[trackId]` with `[self trackForId:trackId peerConnectionId:peerConnectionId]`, matching the existing `captureFrame` handler pattern.
5. **FlutterEventSink thread safety**: Changed from "thread-safe as of Flutter 3.x" to mandatory `dispatch_async(dispatch_get_main_queue(), ...)` since the header has no thread-safety annotation.
6. **decodeImageFromPixels threading**: Corrected from "background isolate" to "engine IO thread" with accurate description of what runs where.
7. **CADisplayLink on background thread**: Replaced with `dispatch_source_timer` which is GCD-native and reliable.
8. **Frame drop mechanism**: Replaced no-op `StreamTransformer` with a proper latest-frame-wins pattern in both providers.
9. **Dual AVPlayer**: Changed to single player to avoid doubling hardware decoder load.
10. **Bandwidth**: Added concrete numbers and half-resolution recommendation.
